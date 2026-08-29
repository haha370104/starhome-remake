#!/usr/bin/env python3
"""Import Glory ground-loot sprites into semantic remake paths.

Legacy paths remain in the evidence manifest only. Runtime presentation data
contains business identifiers and project-native resource paths.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
GLORY_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
TARGET_ROOT = PROJECT_ROOT / "assets" / "items" / "materials"
PRESENTATION_PATH = PROJECT_ROOT / "data" / "presentation" / "ground_loot_v1.json"

SOURCES: dict[str, dict[str, str]] = {
    "low_grade_gel": {
        "display_name": "低级类胶",
        "source": "pic3/stuff/gluey.ale",
    },
    "low_grade_energy_pack": {
        "display_name": "低级能量包",
        "source": "pic3/stuff/NLB01.ale",
    },
    "low_grade_energy_catalyst": {
        "display_name": "低级能量催化剂",
        "source": "pic3/stuff/CHN_2005_06_28_18_34_48_776.ale",
    },
    "low_grade_biosilicon": {
        "display_name": "低级生物硅",
        "source": "pic3/stuff/CHN_2005_06_28_18_35_21_781.ale",
    },
    "low_grade_quadruped_shell": {
        "display_name": "低级四足甲的壳",
        "source": "pic3/stuff/CHN_2005_06_28_18_35_28_782.ale",
    },
}


def sha256(path: Path) -> str:
    """Return the SHA-256 digest for one source or exported file."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_json(path: Path) -> dict[str, Any]:
    """Load and validate one JSON object."""
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"JSON root is not an object: {path}")
    return value


def write_json(path: Path, value: Any) -> None:
    """Write readable UTF-8 JSON with stable line endings."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def import_one(item_id: str, spec: dict[str, str]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Export one decoded ALE frame and return runtime and audit records."""
    source_logical = Path(spec["source"])
    raw_path = GLORY_RAW / source_logical
    parsed_root = GLORY_PARSED / source_logical.with_suffix("")
    frames_path = parsed_root / "frames.json"
    frames = load_json(frames_path)
    if frames.get("frame_count") != 1 or len(frames.get("frames", [])) != 1:
        raise RuntimeError(f"ground item must contain exactly one frame: {source_logical}")
    frame = frames["frames"][0]
    page_path = parsed_root / str(frames["pages"][int(frame["page"])])
    source_image = Image.open(page_path).convert("RGBA")
    crop = source_image.crop(
        (
            int(frame["x"]),
            int(frame["y"]),
            int(frame["x"]) + int(frame["width"]),
            int(frame["y"]) + int(frame["height"]),
        )
    )
    world_target = TARGET_ROOT / item_id / "world_icon.png"
    inventory_target = TARGET_ROOT / item_id / "inventory_icon.png"
    world_target.parent.mkdir(parents=True, exist_ok=True)
    crop.save(world_target)
    crop.save(inventory_target)
    runtime = {
        "display_name": spec["display_name"],
        "world": {
            "texture": f"res://assets/items/materials/{item_id}/world_icon.png",
            "native_size": [crop.width, crop.height],
            "origin": [int(frame["origin_x"]), int(frame["origin_y"])],
        },
        "inventory": {
            "icon": f"res://assets/items/materials/{item_id}/inventory_icon.png",
        },
    }
    audit = {
        "item_definition_id": item_id,
        "source_release": "starhome_lz_ry",
        "source_logical_path": source_logical.as_posix(),
        "source_raw_sha256": sha256(raw_path),
        "source_frames_sha256": sha256(frames_path),
        "exported_world_texture": world_target.relative_to(PROJECT_ROOT).as_posix(),
        "exported_world_texture_sha256": sha256(world_target),
        "exported_inventory_texture": inventory_target.relative_to(PROJECT_ROOT).as_posix(),
        "exported_inventory_texture_sha256": sha256(inventory_target),
        "frame_count": 1,
        "native_size": runtime["world"]["native_size"],
        "origin": runtime["world"]["origin"],
        "runtime_scale": 1.0,
    }
    return runtime, audit


def main() -> int:
    """Rebuild all configured material sprites and their provenance records."""
    definitions: dict[str, Any] = {}
    audit_entries: list[dict[str, Any]] = []
    for item_id, spec in SOURCES.items():
        runtime, audit = import_one(item_id, spec)
        definitions[item_id] = runtime
        audit_entries.append(audit)
    write_json(PRESENTATION_PATH, {
        "schema_version": 1,
        "definitions": definitions,
    })
    write_json(TARGET_ROOT / "source_manifest.json", {
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "display_contract": "native_ale_frame_at_1_to_1_scale",
        "original_pickup_radius_px": 125,
        "assets": audit_entries,
    })
    print(f"Imported and audited {len(definitions)} Glory ground-loot sprites.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
