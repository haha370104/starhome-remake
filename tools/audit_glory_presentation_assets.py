#!/usr/bin/env python3
"""Read-only source and output audit for Glory loot and self-repair assets."""

import hashlib
import json
from pathlib import Path

from glory_paths import PROJECT_ROOT, RAW_ROOT, sprite_dir


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    errors = []
    loot = json.loads((PROJECT_ROOT / "assets/items/materials/source_manifest.json").read_text())
    for row in loot["assets"]:
        label = row["item_definition_id"]
        raw = RAW_ROOT / row["source_logical_path"]
        frames_path = sprite_dir(row["source_logical_path"]) / "frames.json"
        if not raw.is_file() or sha256(raw) != row["source_raw_sha256"]:
            errors.append(f"{label}: original ALE differs")
        if not frames_path.is_file():
            errors.append(f"{label}: materialized frames missing")
        else:
            frames = json.loads(frames_path.read_text())["frames"]
            if len(frames) != row["frame_count"] or [frames[0]["width"], frames[0]["height"]] != row["native_size"] or [frames[0]["origin_x"], frames[0]["origin_y"]] != row["origin"]:
                errors.append(f"{label}: materialized frame geometry differs")
        for key in ("exported_world_texture", "exported_inventory_texture"):
            path = PROJECT_ROOT / row[key]
            if not path.is_file() or sha256(path) != row[key + "_sha256"]:
                errors.append(f"{label}: {key} differs")

    repair = json.loads((PROJECT_ROOT / "assets/equipment_world/shared/self_repair/source_manifest.json").read_text())
    for row in repair["animations"]:
        label = row["semantic_name"]
        source = sprite_dir(row["source_logical_path"])
        frames_path = source / "frames.json"
        sheet_path = source / "sheet.png"
        if not (RAW_ROOT / row["source_logical_path"]).is_file():
            errors.append(f"{label}: original ALE missing")
        if not sheet_path.is_file() or sha256(sheet_path) != row["source_sheet_sha256"]:
            errors.append(f"{label}: materialized sprite sheet differs")
        if not frames_path.is_file() or len(json.loads(frames_path.read_text())["frames"]) != row["frame_count"]:
            errors.append(f"{label}: materialized frame count differs")
        resource = PROJECT_ROOT / row["resource"].removeprefix("res://")
        if not resource.is_file() or not (resource.parent / "frames.png").is_file():
            errors.append(f"{label}: runtime resource missing")
    if errors:
        print("\n".join(errors))
        return 1
    print(f"Glory presentation audit passed: {len(loot['assets'])} loot sprites, {len(repair['animations'])} repair animations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
