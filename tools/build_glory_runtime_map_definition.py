#!/usr/bin/env python3
"""Generate one typed remake map definition from a parsed Glory map variant."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
PARSED_MAP_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_maps_parsed" / "maps"
DIRECTORY_PATH = PROJECT_ROOT / "data" / "maps" / "map_directory.json"
CELL_SIZE = (48, 12)


def read_object(path: Path) -> dict[str, Any]:
    """Read a UTF-8 JSON object."""
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def sha256(path: Path) -> str:
    """Return one file's stable SHA-256 digest."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def runtime_targets() -> dict[tuple[str, str], str]:
    """Index currently promoted maps by world and legacy code."""
    directory = read_object(DIRECTORY_PATH)
    result: dict[tuple[str, str], str] = {}
    for definition_path in directory.get("definitions", {}).values():
        local_path = PROJECT_ROOT / str(definition_path).removeprefix("res://")
        definition = read_object(local_path)
        world_id = str(definition.get("world", {}).get("id", "legacy_world"))
        for legacy_code in definition.get("legacy", {}).get("codes", []):
            result[(world_id, str(legacy_code).lower())] = str(definition["map_id"])
    return result


def closest_walkable_center(source: Path, metadata: dict[str, Any]) -> list[int]:
    """Select the walkable navigation cell nearest the map's visual center."""
    width, height = (int(value) for value in metadata["map_pixel_size"])
    grid_width, grid_height = (int(value) for value in metadata["engine_grid_size"])
    navigation = (source / "navigation_grid.bin").read_bytes()
    if len(navigation) != grid_width * grid_height:
        raise ValueError("navigation grid size does not match metadata")
    center = (width / 2.0, height / 2.0)
    best: tuple[float, int, int] | None = None
    for y in range(grid_height):
        offset = y * grid_width
        for x in range(grid_width):
            if navigation[offset + x] == 0:
                continue
            world_x = x * CELL_SIZE[0] + (CELL_SIZE[0] / 2 if y % 2 else 0)
            world_y = y * CELL_SIZE[1]
            distance = (world_x - center[0]) ** 2 + (world_y - center[1]) ** 2
            candidate = (distance, int(world_x), int(world_y))
            if best is None or candidate < best:
                best = candidate
    if best is None:
        raise ValueError("map has no walkable navigation cell")
    return [best[1], best[2]]


def orientation(point: list[int], size: list[int]) -> str:
    """Quantize a marker's center-relative direction to the shared eight-way names."""
    dx = float(point[0]) - float(size[0]) / 2.0
    dy = float(point[1]) - float(size[1]) / 2.0
    sector = int(round(math.atan2(dy, dx) / (math.pi / 4.0))) % 8
    return [
        "east", "south_east", "south", "south_west",
        "west", "north_west", "north", "north_east",
    ][sector]


def transition_definition(
    raw: dict[str, Any],
    world_id: str,
    targets: dict[tuple[str, str], str],
    map_size: list[int],
) -> dict[str, Any]:
    """Convert one recovered transition while preserving unresolved boundaries."""
    legacy_code = str(raw["destination_map_code"]).lower()
    target_id = targets.get((world_id, legacy_code), "")
    destination: dict[str, Any] = {
        "legacy_code": legacy_code,
        "entry_number": int(raw.get("destination_entry_number", 0)),
        "external": not bool(target_id),
    }
    if target_id:
        destination["map_id"] = target_id
    source_anchor = [int(value) for value in raw["icon_anchor"]]
    return {
        "transition_id": f"exit_to_{legacy_code}",
        "kind": "standard",
        "enabled": True,
        "label": str(raw.get("label") or f"通往{legacy_code.upper()}"),
        "source_anchor": source_anchor,
        "approach_point": [int(value) for value in raw["approach_point"]],
        "presentation": {
            "kind": "directional_transition",
            "orientation": orientation(source_anchor, map_size),
            "activation": "enabled_transition",
        },
        "destination": destination,
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_map_code": str(raw["source_map_code"]),
            "source_output": str(raw["source_map_output"]),
            "source_line": int(raw["source_line"]),
            "source_icon_ale": str(raw["icon_ale"]),
        },
    }


def build_definition(arguments: argparse.Namespace) -> dict[str, Any]:
    """Build a complete runtime map document from source and business arguments."""
    source = PARSED_MAP_ROOT / arguments.source
    metadata = read_object(source / "map_metadata.json")
    transitions = read_object(source / "transitions.json")
    manifest = read_object(PROJECT_ROOT / arguments.destination / "map_manifest.json")
    map_code = str(metadata["map_code"]).lower()
    map_size = [int(value) for value in metadata["map_pixel_size"]]
    resource_root = arguments.destination.replace("\\", "/")
    asset_root = resource_root.replace("assets/", "", 1)
    parsed_transitions = [
        transition_definition(raw, arguments.world_id, runtime_targets(), map_size)
        for raw in transitions.get("enabled", [])
    ]
    return {
        "schema_version": 1,
        "map_id": arguments.runtime_map_id,
        "display_name": str(metadata.get("map_system_label") or metadata["map_name"]),
        "category": "field" if metadata.get("category") == "field_code" else "scene",
        "legacy": {"codes": [map_code]},
        "world": {
            "id": arguments.world_id,
            "size": map_size,
            "navigation": {
                "grid_size": [int(value) for value in metadata["engine_grid_size"]],
                "cell_size": list(CELL_SIZE),
                "data_path": f"res://{resource_root}/navigation_grid.bin",
            },
        },
        "assets": {
            "ids": {
                "floor": f"{asset_root}/floor",
                "minimap": f"{asset_root}/minimap",
                "scene_manifest": f"{asset_root}/scene_manifest",
            },
            "resources": {
                "floor": f"res://{resource_root}/floor.png",
                "minimap": f"res://{resource_root}/minimap.jpg",
                "scene_manifest": f"res://{resource_root}/map_manifest.json",
            },
        },
        "spawn_points": {
            "default_id": "field_center",
            "points": [{
                "spawn_id": "field_center",
                "entry_number": 0,
                "position": closest_walkable_center(source, metadata),
                "enabled": True,
                "evidence_level": "navigation_derived",
                "source_audit": {
                    "source_release": "starhome_lz_ry",
                    "source_map_code": map_code,
                    "source_output": f"{arguments.source}/navigation_grid.bin",
                    "derivation": "nearest confirmed walkable cell to map center",
                },
            }],
        },
        "navigation_overrides": [],
        "player_presentation": {
            "kind": "combat_actor",
            "actor_id": "starter_combat_vehicle",
            "manifest": "res://assets/equipment_world/combat_visual_manifest.json",
            "animation_evidence": {
                "directional_coverage": "source_confirmed_eight_way",
                "move_cycle": "source_confirmed_four_frames_per_direction",
                "idle_cycle": "reconstructed_directional_first_frame",
            },
        },
        "transitions": parsed_transitions,
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_world": arguments.source_branch,
            "source_map_code": map_code,
            "source_map_name": str(metadata["map_name"]),
            "source_output": arguments.source,
            "source_branches": metadata.get("source_branches", []),
            "source_script_sha256": str(metadata["script_sha256"]),
            "navigation_sha256": sha256(source / "navigation_grid.bin"),
            "navigation_passable": int(metadata["navigation"]["passable"]),
            "navigation_blocked": int(metadata["navigation"]["blocked"]),
            "scene_objects_resolved": int(metadata["scene_objects"]["resolved"]),
            "scene_objects_missing": int(metadata["scene_objects"]["missing"]),
            "semantic_layers": len(manifest["composition"]["semantic_layers"]),
            "presentation_state": "runtime_ready",
            "promoted_transition_count": len(parsed_transitions),
        },
    }


def main() -> int:
    """Parse arguments and write one deterministic runtime definition."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--runtime-map-id", required=True)
    parser.add_argument("--world-id", required=True)
    parser.add_argument("--source-branch", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--output", required=True)
    arguments = parser.parse_args()
    output = PROJECT_ROOT / arguments.output
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(build_definition(arguments), ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"GLORY_RUNTIME_MAP_DEFINITION_BUILT {arguments.runtime_map_id} -> {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
