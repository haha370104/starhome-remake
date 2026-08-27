#!/usr/bin/env python3
"""Import and audit the first Glory vehicle presentation slice.

The runtime export uses business names only.  Original ALE paths and class
names are retained exclusively in ``source_manifest.json`` for provenance.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
GLORY_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
EQUIPMENT_CATALOG = (
    OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "catalogs_utf8" / "equipment_catalog.csv"
)
TARGET_ROOT = PROJECT_ROOT / "assets" / "equipment_world"

DIRECTIONS = ["east", "north_east", "north", "north_west", "west", "south_west", "south", "south_east"]

SOURCES: dict[str, dict[str, Any]] = {
    "recruit_tank": {
        "legacy_class": "tank1",
        "display_name": "新兵战车",
        "source_logical_path": "pic3/equip/body/tank1.ale",
        "target": "starter_combat_vehicle/chassis/locomotion",
        "expected_frames": 32,
        "direction_mode": "eight_way",
        "frames_per_direction": 4,
        "world_visible": True,
    },
    "recruit_energy_cannon": {
        "legacy_class": "gun1",
        "display_name": "新兵能量炮",
        "source_logical_path": "pic3/equip/body/gun1.ale",
        "target": "starter_combat_vehicle/weapon/aiming",
        "expected_frames": 8,
        "direction_mode": "eight_way",
        "frames_per_direction": 1,
        "world_visible": True,
    },
    "beginner_engine": {
        "legacy_class": "engine1",
        "display_name": "初级引擎",
        "source_logical_path": "pic3/equip/body/engine1.ale",
        "target": "starter_combat_vehicle/engine/component",
        "expected_frames": 1,
        "direction_mode": "shared",
        "frames_per_direction": 1,
        "world_visible": False,
    },
}


def _action(
    resource: str,
    frames_per_direction: int,
    direction_mode: str = "eight_way",
    loop: bool = True,
    offset: list[int] | None = None,
) -> dict[str, Any]:
    """Build one manifest action without importing source-only identifiers."""
    action = {
        "resource": resource,
        "direction_mode": direction_mode,
        "frames_per_direction": frames_per_direction,
        "fps": 10.0,
        "loop": loop,
    }
    action["offset"] = offset if offset is not None else _resource_offset(resource)
    return action


def _resource_offset(resource: str) -> list[int]:
    """Read the normalized entity-anchor offset adjacent to a SpriteFrames resource."""
    resource_path = PROJECT_ROOT / resource.removeprefix("res://")
    metadata_path = resource_path.with_name("import_metadata.json")
    if not metadata_path.is_file():
        return [0, 0]
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    bounds = metadata.get("normalized_cell", {}).get("coordinate_bounds", [0, 0, 0, 0])
    return [int(bounds[0]), int(bounds[1])]


MONSTER_ACTORS: dict[str, dict[str, Any]] = {
    "om_adult_standard": {
        "display_name": "奥姆虫",
        "default_action": "idle",
        "actions": {
            "idle": _action("res://assets/monsters/om_adult/variants/standard/idle/animation_frames.tres", 5),
            "move": _action("res://assets/monsters/om_adult/variants/standard/move/animation_frames.tres", 5),
            "attack": _action("res://assets/monsters/om_adult/variants/standard/attack/animation_frames.tres", 6, loop=False),
        },
    },
    "om_larva_standard": {
        "display_name": "奥姆幼虫",
        "default_action": "idle",
        "actions": {
            "idle": _action("res://assets/monsters/om_larva/variants/standard/idle/animation_frames.tres", 5),
            "move": _action("res://assets/monsters/om_larva/variants/standard/move/animation_frames.tres", 5),
            "attack": _action("res://assets/monsters/om_larva/variants/standard/attack/animation_frames.tres", 5, loop=False),
        },
    },
    "photosensitive_orb_standard": {
        "display_name": "感光质",
        "default_action": "idle",
        "actions": {
            "idle": _action("res://assets/monsters/photosensitive_orb/variants/standard/idle/animation_frames.tres", 5, direction_mode="shared"),
            "move": _action("res://assets/monsters/photosensitive_orb/variants/standard/move_attack/animation_frames.tres", 5, direction_mode="shared"),
            "attack": _action("res://assets/monsters/photosensitive_orb/variants/standard/move_attack/animation_frames.tres", 5, direction_mode="shared", loop=False),
        },
    },
    "toxic_gel_standard": {
        "display_name": "毒胶",
        "default_action": "idle",
        "actions": {
            "idle": _action("res://assets/monsters/toxic_gel/variants/standard/idle/animation_frames.tres", 5, direction_mode="shared"),
            "move": _action("res://assets/monsters/toxic_gel/variants/standard/move/animation_frames.tres", 5),
        },
    },
}


def _atomic_text(path: Path, content: str) -> None:
    """Atomically replace ``path`` with UTF-8 ``content``."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def _atomic_json(path: Path, value: Any) -> None:
    """Atomically serialize ``value`` as readable UTF-8 JSON."""
    _atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def _hash(path: Path, algorithm: str = "sha256") -> str:
    """Return ``path`` content digest using ``algorithm``."""
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _res_path(path: Path) -> str:
    """Return a Godot ``res://`` path for a checked-in project file."""
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


def _build_tres(texture: Path, frame_count: int, width: int, height: int) -> str:
    """Build a single-raw-animation SpriteFrames resource for a normalized atlas."""
    subresources: list[str] = []
    entries: list[str] = []
    for index in range(frame_count):
        subresources.extend(
            [
                f'[sub_resource type="AtlasTexture" id="frame_{index}"]',
                'atlas = ExtResource("texture")',
                f"region = Rect2({index * width}, 0, {width}, {height})",
                "filter_clip = true",
                "",
            ]
        )
        entries.append(f'{{"duration": 1.0, "texture": SubResource("frame_{index}")}}')
    return (
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]\n\n'
        f'[ext_resource type="Texture2D" path={json.dumps(_res_path(texture))} id="texture"]\n\n'
        + "\n".join(subresources)
        + '[resource]\nanimations = [{\n"frames": ['
        + ", ".join(entries)
        + '],\n"loop": true,\n"name": &"raw",\n"speed": 10.0\n}]\n'
    )


def _catalog_rows() -> dict[str, dict[str, str]]:
    """Load only the three source equipment rows used for provenance validation."""
    with EQUIPMENT_CATALOG.open("r", encoding="utf-8-sig", newline="") as stream:
        rows = {row["class_name"]: row for row in csv.DictReader(stream)}
    return {spec["legacy_class"]: rows[spec["legacy_class"]] for spec in SOURCES.values()}


def _export_asset(asset_id: str, spec: dict[str, Any]) -> dict[str, Any]:
    """Normalize the parsed Glory frames for ``asset_id`` and return source audit data."""
    source_logical = str(spec["source_logical_path"])
    source_path = GLORY_RAW / Path(source_logical)
    parsed_root = GLORY_PARSED / Path(source_logical).with_suffix("")
    frames_path = parsed_root / "frames.json"
    parsed_sheet_path = parsed_root / "sheet.png"
    if not source_path.is_file() or not frames_path.is_file() or not parsed_sheet_path.is_file():
        raise RuntimeError(f"missing Glory source for {asset_id}")

    parsed = json.loads(frames_path.read_text(encoding="utf-8"))
    frames = parsed["frames"]
    if int(parsed["frame_count"]) != int(spec["expected_frames"]):
        raise RuntimeError(f"unexpected frame count for {asset_id}: {parsed['frame_count']}")
    visible = [frame for frame in frames if frame["width"] and frame["height"]]
    left = min(int(frame["origin_x"]) for frame in visible)
    top = min(int(frame["origin_y"]) for frame in visible)
    right = max(int(frame["origin_x"]) + int(frame["width"]) for frame in visible)
    bottom = max(int(frame["origin_y"]) + int(frame["height"]) for frame in visible)
    cell_width = max(1, right - left)
    cell_height = max(1, bottom - top)

    target = TARGET_ROOT / str(spec["target"])
    target.mkdir(parents=True, exist_ok=True)
    atlas = Image.new("RGBA", (cell_width * len(frames), cell_height))
    with Image.open(parsed_sheet_path) as sheet:
        sheet = sheet.convert("RGBA")
        for frame in frames:
            crop = sheet.crop(
                (
                    int(frame["x"]),
                    int(frame["y"]),
                    int(frame["x"]) + int(frame["width"]),
                    int(frame["y"]) + int(frame["height"]),
                )
            )
            atlas.alpha_composite(
                crop,
                (
                    int(frame["index"]) * cell_width + int(frame["origin_x"]) - left,
                    int(frame["origin_y"]) - top,
                ),
            )
            crop.close()
    texture_path = target / "frames.png"
    atlas.save(texture_path, optimize=True)
    atlas.close()
    resource_path = target / "animation_frames.tres"
    _atomic_text(resource_path, _build_tres(texture_path, len(frames), cell_width, cell_height))

    return {
        "asset_id": asset_id,
        "display_name": spec["display_name"],
        "source_logical_path": source_logical,
        "source_sha256": _hash(source_path),
        "parsed_frames_sha256": _hash(frames_path),
        "parsed_sheet_sha256": _hash(parsed_sheet_path),
        "source_catalog": "catalogs_utf8/equipment_catalog.csv",
        "source_class": spec["legacy_class"],
        "source_line": int(_catalog_rows()[spec["legacy_class"]]["source_line"]),
        "frame_count": len(frames),
        "normalized_cell": [cell_width, cell_height],
        "coordinate_bounds": [left, top, right, bottom],
        "runtime_resource": _res_path(resource_path),
        "direction_mode": spec["direction_mode"],
        "frames_per_direction": spec["frames_per_direction"],
        "world_visible": spec["world_visible"],
    }


def _runtime_manifest(source_assets: list[dict[str, Any]]) -> dict[str, Any]:
    """Build the runtime-only combat visual manifest with business-semantic paths."""
    source_by_id = {entry["asset_id"]: entry for entry in source_assets}
    chassis = _res_path(TARGET_ROOT / SOURCES["recruit_tank"]["target"] / "animation_frames.tres")
    weapon = _res_path(TARGET_ROOT / SOURCES["recruit_energy_cannon"]["target"] / "animation_frames.tres")
    engine = _res_path(TARGET_ROOT / SOURCES["beginner_engine"]["target"] / "animation_frames.tres")
    chassis_offset = list(source_by_id["recruit_tank"]["coordinate_bounds"][:2])
    weapon_offset = list(source_by_id["recruit_energy_cannon"]["coordinate_bounds"][:2])
    engine_offset = list(source_by_id["beginner_engine"]["coordinate_bounds"][:2])
    actors: dict[str, Any] = {
        "starter_combat_vehicle": {
            "display_name": "新兵战车",
            "default_action": "idle",
            "layers": [
                {
                    "id": "chassis",
                    "z_index": 0,
                    "actions": {
                        "idle": _action(chassis, 4, offset=chassis_offset),
                        "move": _action(chassis, 4, offset=chassis_offset),
                    },
                },
                {
                    "id": "primary_weapon",
                    "z_index": 1,
                    "actions": {
                        "idle": _action(weapon, 1, offset=weapon_offset),
                        "move": _action(weapon, 1, offset=weapon_offset),
                        "attack": _action(weapon, 1, loop=False, offset=weapon_offset),
                    },
                },
            ],
            "installed_components": [
                "recruit_tank",
                "recruit_energy_cannon",
                "beginner_engine",
            ],
        }
    }
    for actor_id, actor in MONSTER_ACTORS.items():
        actors[actor_id] = {
            "display_name": actor["display_name"],
            "default_action": actor["default_action"],
            "layers": [{"id": "body", "z_index": 0, "actions": actor["actions"]}],
        }
    return {
        "schema_version": 1,
        "direction_order": DIRECTIONS,
        "source_audit": "res://assets/equipment_world/source_manifest.json",
        "components": {
            "recruit_tank": {
                "render_policy": "world_layer",
                "action": _action(chassis, 4, offset=chassis_offset),
            },
            "recruit_energy_cannon": {
                "render_policy": "world_layer",
                "action": _action(weapon, 1, offset=weapon_offset),
            },
            "beginner_engine": {
                "render_policy": "installed_only",
                "action": _action(
                    engine,
                    1,
                    direction_mode="shared",
                    offset=engine_offset,
                ),
            },
        },
        "actors": actors,
    }


def migrate() -> None:
    """Generate business-named runtime resources and the separate provenance manifest."""
    rows = _catalog_rows()
    for spec in SOURCES.values():
        row = rows[str(spec["legacy_class"])]
        if row["display_name"] != spec["display_name"]:
            raise RuntimeError(f"catalog identity mismatch: {spec['legacy_class']}")
    source_assets = [_export_asset(asset_id, spec) for asset_id, spec in SOURCES.items()]
    _atomic_json(
        TARGET_ROOT / "source_manifest.json",
        {
            "schema_version": 1,
            "source_version": "starhome_lz_ry",
            "source_root": str(GLORY_RAW.resolve()),
            "parsed_root": str(GLORY_PARSED.resolve()),
            "evidence": [
                "荣耀版装备目录确认显示名、类别与世界素材映射",
                "荣耀版角色合成脚本仅将底盘与武器渲染为战车世界层",
                "每项原始容器、解析帧清单和解析图集均记录 SHA-256",
            ],
            "assets": source_assets,
        },
    )
    _atomic_json(TARGET_ROOT / "combat_visual_manifest.json", _runtime_manifest(source_assets))


def audit() -> dict[str, Any]:
    """Validate source identity, generated resources, and runtime naming boundaries."""
    errors: list[str] = []
    runtime_path = TARGET_ROOT / "combat_visual_manifest.json"
    source_path = TARGET_ROOT / "source_manifest.json"
    if not runtime_path.is_file() or not source_path.is_file():
        errors.append("generated manifests are missing")
        return {"assets": 0, "actors": 0, "errors": errors}
    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    source = json.loads(source_path.read_text(encoding="utf-8"))
    forbidden = re.compile(r"(?:pic2?|\.ale\b|CHN_\d{4}|\d{4}_\d{2}_\d{2})", re.IGNORECASE)
    runtime_text = json.dumps(runtime, ensure_ascii=False)
    if forbidden.search(runtime_text):
        errors.append("runtime manifest leaks a legacy path, container, or timestamp identifier")
    catalog_rows = _catalog_rows()
    for entry in source.get("assets", []):
        asset_id = str(entry["asset_id"])
        spec = SOURCES.get(asset_id)
        if spec is None:
            errors.append(f"unknown source asset: {asset_id}")
            continue
        resource = PROJECT_ROOT / str(entry["runtime_resource"]).removeprefix("res://")
        texture = resource.with_name("frames.png")
        if not resource.is_file() or not texture.is_file():
            errors.append(f"runtime files missing for {asset_id}")
        if int(entry["frame_count"]) != int(spec["expected_frames"]):
            errors.append(f"frame count mismatch for {asset_id}")
        raw_path = GLORY_RAW / Path(str(spec["source_logical_path"]))
        parsed_root = GLORY_PARSED / Path(str(spec["source_logical_path"])).with_suffix("")
        frames_path = parsed_root / "frames.json"
        sheet_path = parsed_root / "sheet.png"
        if not raw_path.is_file() or _hash(raw_path) != entry.get("source_sha256"):
            errors.append(f"raw source digest mismatch for {asset_id}")
        if not frames_path.is_file() or _hash(frames_path) != entry.get("parsed_frames_sha256"):
            errors.append(f"parsed frame digest mismatch for {asset_id}")
        if not sheet_path.is_file() or _hash(sheet_path) != entry.get("parsed_sheet_sha256"):
            errors.append(f"parsed sheet digest mismatch for {asset_id}")
        source_class = str(spec["legacy_class"])
        if catalog_rows[source_class]["display_name"] != spec["display_name"]:
            errors.append(f"catalog display name mismatch for {asset_id}")
    return {
        "source_version": source.get("source_version", ""),
        "assets": len(source.get("assets", [])),
        "actors": len(runtime.get("actors", {})),
        "errors": errors,
    }


def main() -> int:
    """Run optional migration followed by the read-only audit."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrate", action="store_true")
    args = parser.parse_args()
    if args.migrate:
        migrate()
    result = audit()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
