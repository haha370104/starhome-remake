#!/usr/bin/env python3
"""Batch-decode ALE/RLE0/AEX sprites with the canonical ale_sprite.py decoder."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
import os
import shutil
import sys
import traceback
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any

SUPPORTED = {b"ALE\0": "ALE", b"RLE0": "RLE0", b"AEX\0": "AEX"}


def safe_output_stem(stem: str) -> str:
    trimmed = stem.rstrip(" .")
    suffix = stem[len(trimmed):]
    if not suffix:
        return stem
    return trimmed + "".join(f"__x{ord(ch):02X}" for ch in suffix)


def detect(path: Path) -> str | None:
    try:
        with path.open("rb") as f:
            return SUPPORTED.get(f.read(4))
    except OSError:
        return None


def load_decoder(path: Path):
    name = f"starhome_ale_decoder_{os.getpid()}"
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ImportError(f"cannot load decoder: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def worker(task: tuple[str, str, str, int]) -> dict[str, Any]:
    source_s, output_s, decoder_s, max_sheet = task
    source = Path(source_s)
    output = Path(output_s)
    decoder_path = Path(decoder_s)
    try:
        decoder = load_decoder(decoder_path)
        with source.open("rb") as f:
            magic = f.read(4)
        sprite = decoder.AexFile(source) if magic == b"AEX\0" else decoder.AleFile(source)
        temporary = output.with_name(output.name + f".__tmp_{os.getpid()}")
        if temporary.exists():
            shutil.rmtree(temporary)
        manifest = decoder.build_sheets(sprite, temporary, max_sheet)
        if output.exists():
            shutil.rmtree(output)
        output.parent.mkdir(parents=True, exist_ok=True)
        os.replace(temporary, output)
        return {
            "status": "ok",
            "frames": int(manifest.get("frame_count", 0)),
            "container": str(manifest.get("container", "")),
            "version": int(manifest.get("version", 0)),
            "pages": len(manifest.get("pages", [])),
        }
    except Exception as exc:
        text = f"{type(exc).__name__}: {exc}"
        status = "empty_placeholder" if "no renderable frames" in str(exc) else "error"
        return {
            "status": status,
            "frames": 0,
            "error": text,
            "traceback": traceback.format_exc(limit=8),
        }


def main() -> int:
    ap = argparse.ArgumentParser(description="Batch decode StarHome ALE/RLE0/AEX resources")
    ap.add_argument("raw_root", type=Path)
    ap.add_argument("output_root", type=Path)
    ap.add_argument("--decoder", type=Path, default=Path(__file__).with_name("ale_sprite.py"))
    ap.add_argument("--workers", type=int, default=max(1, min(8, os.cpu_count() or 1)))
    ap.add_argument("--max-sheet-size", type=int, default=8192)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    raw_root = args.raw_root.resolve()
    output_root = args.output_root.resolve()
    decoder = args.decoder.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    if not decoder.is_file():
        raise FileNotFoundError(decoder)

    candidates: list[tuple[Path, str, Path]] = []
    outputs_seen: dict[str, Path] = {}
    for path in sorted(raw_root.rglob("*"), key=lambda p: str(p).lower()):
        if not path.is_file():
            continue
        kind = detect(path)
        if not kind:
            continue
        rel = path.relative_to(raw_root)
        dest = output_root / rel.parent / safe_output_stem(rel.stem)
        key = str(dest).lower()
        prior = outputs_seen.get(key)
        if prior is not None and prior != path:
            raise RuntimeError(f"output collision: {prior} and {path} -> {dest}")
        outputs_seen[key] = path
        candidates.append((path, kind, dest))

    if args.limit:
        candidates = candidates[:args.limit]

    results: list[dict[str, Any]] = []
    pending = []
    for source, kind, dest in candidates:
        frames_json = dest / "frames.json"
        if frames_json.is_file() and not args.force:
            try:
                manifest = json.loads(frames_json.read_text(encoding="utf-8-sig"))
                results.append({
                    "source": source.relative_to(raw_root).as_posix(),
                    "output": dest.relative_to(output_root).as_posix(),
                    "kind": kind,
                    "status": "ok_existing",
                    "frames": int(manifest.get("frame_count", 0)),
                    "version": int(manifest.get("version", 0)),
                    "pages": len(manifest.get("pages", [])),
                })
                continue
            except Exception:
                pass
        pending.append((source, kind, dest))

    print(f"candidates: {len(candidates):,}")
    print(f"existing:   {len(results):,}")
    print(f"pending:    {len(pending):,}")
    print(f"workers:    {args.workers}")

    tasks = [(str(src), str(dest), str(decoder), args.max_sheet_size) for src, _, dest in pending]
    metadata = {(str(src), str(dest)): (src, kind, dest) for src, kind, dest in pending}

    done = 0
    if tasks:
        with ProcessPoolExecutor(max_workers=args.workers) as pool:
            future_map = {
                pool.submit(worker, task): task
                for task in tasks
            }
            for future in as_completed(future_map):
                task = future_map[future]
                source, kind, dest = metadata[(task[0], task[1])]
                result = future.result()
                row = {
                    "source": source.relative_to(raw_root).as_posix(),
                    "output": dest.relative_to(output_root).as_posix(),
                    "kind": kind,
                    **result,
                }
                results.append(row)
                done += 1
                status = result["status"]
                if status == "ok":
                    print(f"[{done:5}/{len(tasks)}] OK    {row['source']}  frames={row['frames']}")
                elif status == "empty_placeholder":
                    print(f"[{done:5}/{len(tasks)}] EMPTY {row['source']}")
                else:
                    print(f"[{done:5}/{len(tasks)}] FAIL  {row['source']}  {result.get('error','')}")

    results.sort(key=lambda r: r["source"].lower())
    converted = sum(r["status"] in {"ok", "ok_existing"} for r in results)
    empty = sum(r["status"] == "empty_placeholder" for r in results)
    failed = sum(r["status"] == "error" for r in results)
    frames = sum(int(r.get("frames", 0)) for r in results if r["status"] in {"ok", "ok_existing"})
    counts = {kind: sum(r["kind"] == kind for r in results) for kind in ("ALE", "RLE0", "AEX")}

    summary = {
        "candidates": len(candidates),
        "converted": converted,
        "empty_placeholders": empty,
        "failed": failed,
        "frames": frames,
        "containers": counts,
        "historical_cross_check": {
            "converted_expected": 13888,
            "frames_expected": 140513,
            "converted_match": converted == 13888,
            "frames_match": frames == 140513,
        },
    }
    (output_root / "ale_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    failures = [r for r in results if r["status"] not in {"ok", "ok_existing"}]
    (output_root / "ale_failures.json").write_text(
        json.dumps(failures, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    with (output_root / "ale_inventory.csv").open("w", encoding="utf-8-sig", newline="") as f:
        fields = ["source", "output", "kind", "status", "version", "frames", "pages", "error"]
        w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(results)

    print("\n" + json.dumps(summary, ensure_ascii=False, indent=2))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
