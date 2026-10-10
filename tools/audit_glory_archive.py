#!/usr/bin/env python3
"""Audit the workspace-local Glory original archive against its downloaded index."""

import csv
import hashlib
import json
from pathlib import Path

from glory_paths import EVIDENCE_ROOT, RAW_ROOT, SPRITE_ROOT


def digest(path: Path, algorithm: str) -> str:
    value = hashlib.new(algorithm)
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def main() -> int:
    manifest = json.loads((EVIDENCE_ROOT / "manifest.json").read_text(encoding="utf-8"))
    index = EVIDENCE_ROOT / "resource_index.csv"
    errors = []
    if digest(index, "sha256") != manifest["resource_index_sha256"]:
        errors.append("resource index SHA-256 differs from the recorded source")
    valid = 0
    tombstones = 0
    total_bytes = 0
    indexed_paths = set()
    with index.open(encoding="utf-8-sig", newline="") as stream:
        for row in csv.DictReader(stream):
            if row["kind"] == "tombstone":
                tombstones += 1
                continue
            if row["kind"] != "valid":
                errors.append(f"unknown index record kind: {row['kind']}")
                continue
            logical = Path(row["logical_path"].replace("\\", "/"))
            indexed_paths.add(logical.as_posix())
            source = RAW_ROOT / logical
            valid += 1
            if not source.is_file():
                errors.append(f"missing original file: {logical}")
                continue
            size = source.stat().st_size
            total_bytes += size
            if size != int(row["size"]) or digest(source, "md5") != row["md5"]:
                errors.append(f"original bytes differ from index: {logical}")
    actual_paths = {path.relative_to(RAW_ROOT).as_posix() for path in RAW_ROOT.rglob("*") if path.is_file()}
    errors.extend(f"unindexed original file: {path}" for path in sorted(actual_paths - indexed_paths))
    for key, count in (("valid_files", valid), ("tombstones", tombstones), ("valid_bytes", total_bytes)):
        if manifest[key] != count:
            errors.append(f"{key}: expected {manifest[key]}, found {count}")
    for name, expected in manifest["derived_evidence"].items():
        path = EVIDENCE_ROOT / name
        if not path.is_file() or digest(path, "sha256") != expected:
            errors.append(f"derived evidence differs: {name}")
    sprite_count = sum(1 for _ in SPRITE_ROOT.rglob("frames.json"))
    if sprite_count != manifest["materialized_sprites"]:
        errors.append(f"materialized sprites: expected {manifest['materialized_sprites']}, found {sprite_count}")
    if errors:
        print("\n".join(errors[:30]))
        print(f"Glory archive audit failed: {len(errors)} errors")
        return 1
    print(f"Glory archive audit passed: {valid} originals ({total_bytes} bytes), {tombstones} tombstones, {sprite_count} sprites")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
