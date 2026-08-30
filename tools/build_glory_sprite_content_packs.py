#!/usr/bin/env python3
"""Package every decoded Glory ALE sheet behind a stable runtime index."""

from __future__ import annotations

import argparse
import hashlib
import json
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
SPRITE_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
PACK_ROOT = PROJECT_ROOT / "assets" / "content_packs"
CATALOG_PATH = PROJECT_ROOT / "data" / "content" / "glory_sprite_content_packs_v1.json"
INDEX_PATH = PROJECT_ROOT / "data" / "content" / "glory_sprite_runtime_index_v1.json"
CONTENT_VERSION = "glory-sprite-runtime-v1"


@dataclass(frozen=True)
class SpriteSource:
    logical_id: str
    directory: Path
    metadata: dict[str, Any]
    pages: tuple[Path, ...]
    size_bytes: int


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def discover() -> list[SpriteSource]:
    result: list[SpriteSource] = []
    seen: set[str] = set()
    for frames_path in sorted(SPRITE_ROOT.rglob("frames.json")):
        metadata = json.loads(frames_path.read_text(encoding="utf-8-sig"))
        relative = frames_path.parent.relative_to(SPRITE_ROOT).as_posix().lower()
        if relative in seen:
            raise ValueError(f"case-insensitive ALE path collision: {relative}")
        seen.add(relative)
        page_names = tuple(str(value) for value in metadata.get("pages", []))
        pages = tuple(frames_path.parent / name for name in page_names)
        if not pages or not all(path.is_file() for path in pages):
            raise ValueError(f"decoded ALE pages are incomplete: {frames_path}")
        size = frames_path.stat().st_size + sum(path.stat().st_size for path in pages)
        result.append(SpriteSource(relative, frames_path.parent, metadata, pages, size))
    return result


def partition(sources: list[SpriteSource], maximum_bytes: int) -> list[list[SpriteSource]]:
    parts: list[list[SpriteSource]] = []
    current: list[SpriteSource] = []
    size = 0
    for source in sources:
        if current and size + source.size_bytes > maximum_bytes:
            parts.append(current)
            current = []
            size = 0
        current.append(source)
        size += source.size_bytes
    if current:
        parts.append(current)
    return parts


def fixed_info(path: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    return info


def sanitized_metadata(source: SpriteSource) -> dict[str, Any]:
    value = dict(source.metadata)
    value["source"] = "starhome_lz_ry/raw/%s.ale" % source.logical_id
    value["source_release"] = "starhome_lz_ry"
    return value


def runtime_row(source: SpriteSource) -> dict[str, Any]:
    root = "res://content/glory/sprites/" + source.logical_id
    segments = source.logical_id.split("/")
    return {
        "logical_id": source.logical_id,
        "frames_path": root + "/frames.json",
        "page_paths": [root + "/" + path.name.lower() for path in source.pages],
        "frame_count": int(source.metadata.get("frame_count", 0)),
        "cell_size": [
            int(source.metadata.get("cell_width", 0)),
            int(source.metadata.get("cell_height", 0)),
        ],
        "classification": segments[:2],
        "source_release": "starhome_lz_ry",
    }


def write_index(rows: list[dict[str, Any]], total_bytes: int, pack_count: int) -> None:
    """Write one machine-owned line; 13k source rows are not manually edited."""
    INDEX_PATH.parent.mkdir(parents=True, exist_ok=True)
    value = {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "summary": {
            "sprites": len(rows),
            "decoded_bytes": total_bytes,
            "packs": pack_count,
        },
        "sprites": rows,
    }
    INDEX_PATH.write_text(
        json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )


def write_catalog(pack_files: list[Path], summary: dict[str, Any]) -> None:
    value = {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "packs": [{
            "pack_id": path.stem,
            "path": "res://assets/content_packs/" + path.name,
            "size_bytes": path.stat().st_size,
            "sha256": sha256(path),
            "content_groups": ["sprites", "animations", "ui", "audio_references"],
        } for path in pack_files],
        "summary": summary,
    }
    CATALOG_PATH.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


def build(arguments: argparse.Namespace) -> dict[str, Any]:
    sources = discover()
    parts = partition(sources, int(arguments.maximum_pack_mib * 1024 * 1024))
    total_bytes = sum(source.size_bytes for source in sources)
    summary = {
        "sprites": len(sources),
        "decoded_bytes": total_bytes,
        "packs": len(parts),
    }
    if arguments.plan_only:
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return summary
    PACK_ROOT.mkdir(parents=True, exist_ok=True)
    pack_files: list[Path] = []
    for part_index, part in enumerate(parts, start=1):
        pack_path = PACK_ROOT / ("glory_sprites_%03d_v1.zip" % part_index)
        with zipfile.ZipFile(pack_path, "w", allowZip64=True) as archive:
            for source in part:
                root = "content/glory/sprites/" + source.logical_id
                metadata = (
                    json.dumps(sanitized_metadata(source), ensure_ascii=False, separators=(",", ":"))
                    + "\n"
                ).encode("utf-8")
                archive.writestr(fixed_info(root + "/frames.json"), metadata)
                for page in source.pages:
                    archive.writestr(fixed_info(root + "/" + page.name.lower()), page.read_bytes())
        pack_files.append(pack_path)
        print("BUILT", pack_path.name, len(part), "ALE sprites")
    rows = [runtime_row(source) for source in sources]
    write_index(rows, total_bytes, len(pack_files))
    write_catalog(pack_files, summary)
    print("GLORY_SPRITE_CONTENT_PACKS_BUILT", len(pack_files), "packs")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--maximum-pack-mib", type=int, default=512)
    arguments = parser.parse_args()
    if arguments.maximum_pack_mib < 64:
        parser.error("--maximum-pack-mib must be at least 64")
    build(arguments)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
