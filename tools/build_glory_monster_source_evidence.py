#!/usr/bin/env python3
"""Rebuild Glory NPC rows and map-editor monster references from local raw files."""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from build_glory_monster_runtime_catalog import recover_class_names
from recovery.fcc_workspace import RawFccWorkspace, decode_text


ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = ROOT / "../starhome_lz_ry_full/raw"
EVIDENCE_ROOT = ROOT / "data/source_evidence/glory"
MAP_RECORD = re.compile(r"['\"]NpcNewAddress['\"].*,\s*['\"](?P<spec>[^'\"\r\n]+)['\"]\s*\)\s*;")
NPC_FIELDS = ["index", "npc_name", "attr_raw", "produce_obj", "skill", "source_file"] + [
    f"attr_{index:02d}" for index in range(35)
]


def npc_csv(payload: bytes) -> tuple[bytes, list[dict[str, str]]]:
    text, encoding = decode_text(payload)
    if encoding.endswith("-replace"):
        raise UnicodeError("Glory npcinfo.tab cannot be decoded without replacement")
    lines = text.splitlines()
    if lines[:2] != ["FTDTVER1.00", "npcinfo:*d,s,s,s,s"]:
        raise ValueError("unexpected Glory npcinfo.tab header")
    rows = []
    for source in csv.DictReader(lines[2:]):
        attributes = source["attr"].split("#")
        if len(attributes) != 35:
            raise ValueError(f"NPC {source['index']} has {len(attributes)} attributes, expected 35")
        rows.append({
            "index": source["index"], "npc_name": source["npcname"],
            "attr_raw": source["attr"], "produce_obj": source["produceobj"],
            "skill": source["skill"], "source_file": "loadfile/npcinfo.tab",
            **{f"attr_{index:02d}": value for index, value in enumerate(attributes)},
        })
    rows.sort(key=lambda row: int(row["index"]))
    if len({row["index"] for row in rows}) != len(rows):
        raise ValueError("duplicate Glory NPC index")
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, NPC_FIELDS, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue().encode("utf-8"), rows


def map_records(logical: str, payload: bytes) -> tuple[list[tuple[str, str, str, str, int]], list[dict]]:
    text, encoding = decode_text(payload)
    if encoding.endswith("-replace"):
        raise UnicodeError(f"{logical} cannot be decoded without replacement")
    world, _, filename = logical.split("/", 2)
    records = []
    unbound = []
    for line_number, line in enumerate(text.splitlines(), 1):
        if "NpcNewAddress" not in line:
            continue
        if not line.lstrip().startswith("//"):
            raise ValueError(f"active NpcNewAddress at {logical}:{line_number}")
        match = MAP_RECORD.search(line)
        if match is None:
            if not re.search(r",\s*-?\d+\s*,\s*-?\d+\s*\)\s*;", line):
                raise ValueError(f"unparsed NpcNewAddress at {logical}:{line_number}: {line}")
            unbound.append({"source_file": logical, "source_line": line_number})
            continue
        class_name = match["spec"].split()[0]
        records.append((class_name, world, Path(filename).stem.lower(), logical, line_number))
    return records, unbound


def decode_maps(raw_root: Path, fkernel: Path, paths: list[str]) -> tuple[list[tuple[str, str, str, str, int]], list[dict]]:
    records = []
    unbound = []
    with RawFccWorkspace(raw_root, fkernel) as workspace:
        for logical in paths:
            found, missing = map_records(logical, workspace.payload(logical))
            records.extend(found)
            unbound.extend(missing)
    return records, unbound


def map_relations(
    raw_root: Path, fkernel: Path, class_names: dict[str, dict], workers: int,
) -> dict:
    paths = sorted(
        path.relative_to(raw_root).as_posix()
        for path in raw_root.glob("NFT_*/map/*.fcc") if path.is_file()
    )
    groups = [paths[index::workers] for index in range(workers) if paths[index::workers]]
    with ThreadPoolExecutor(max_workers=workers) as pool:
        batches = list(pool.map(lambda group: decode_maps(raw_root, fkernel, group), groups))
    by_class: dict[str, dict[tuple[str, str, str], list[int]]] = defaultdict(lambda: defaultdict(list))
    unbound = []
    for records, missing in batches:
        unbound.extend(missing)
        for class_name, world, map_code, source, line in records:
            by_class[class_name][(world, map_code, source)].append(line)
    unknown = sorted(set(by_class) - set(class_names))
    if unknown:
        raise ValueError(f"unresolved map-editor monster classes: {unknown}")
    return {
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "evidence_kind": "client_map_editor_NpcNewAddress",
        "scanned_map_scripts": len(paths),
        "unbound_markers": sorted(unbound, key=lambda row: (row["source_file"], row["source_line"])),
        "relations": [
            {
                "monster_class": class_name,
                "display_names": [class_names[class_name]["display_name"]],
                "maps": [
                    {
                        "world_code": world, "map_code": map_code,
                        "source_file": source, "source_lines": sorted(lines),
                        "evidence_record_count": len(lines),
                    }
                    for (world, map_code, source), lines in sorted(by_class[class_name].items())
                ],
            }
            for class_name in sorted(by_class)
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-root", type=Path, default=RAW_ROOT)
    parser.add_argument("--fkernel", type=Path)
    parser.add_argument("--output-root", type=Path, default=EVIDENCE_ROOT)
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.workers < 1:
        parser.error("--workers must be positive")
    fkernel = args.fkernel or args.raw_root.parent / "fkernel.dll"
    with RawFccWorkspace(args.raw_root, fkernel) as workspace:
        catalog, rows = npc_csv(workspace.payload("loadfile/npcinfo.tab"))
        workspace.path("great/code_string.fcc")
        names = recover_class_names(workspace.path("npcclt1.fcc").parent)
    relations = map_relations(args.raw_root, fkernel, names, args.workers)
    outputs = {
        args.output_root / "catalogs_utf8/npc_catalog.csv": catalog,
        args.output_root / "catalogs/monsters/glory_monster_map_relations.json":
            (json.dumps(relations, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
    }
    for path, content in outputs.items():
        if args.check:
            if path.read_bytes() != content:
                raise ValueError(f"Glory source evidence differs: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    print(f"Glory evidence: {len(rows)} NPCs, {len(relations['relations'])} classes, "
          f"{relations['scanned_map_scripts']} map scripts")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
