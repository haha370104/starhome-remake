#!/usr/bin/env python3
"""Build mountable Glory map packs and typed runtime definitions.

Decoded source data remains outside the remake repository.  This tool copies
only the runtime contract: flattened map presentation, minimap, navigation,
scene provenance and transitions.  Existing hand-promoted maps keep their
semantic-layer definitions and are not duplicated in the generated directory.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
PARSED_MAP_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_maps_parsed" / "maps"
KNOWN_MAPS_PATH = PROJECT_ROOT / "data" / "content" / "known_maps_v1.json"
CURRENT_DIRECTORY_PATH = PROJECT_ROOT / "data" / "maps" / "map_directory.json"
PACK_ROOT = PROJECT_ROOT / "assets" / "content_packs"
CATALOG_PATH = PROJECT_ROOT / "data" / "content" / "glory_map_content_packs_v1.json"
RUNTIME_INDEX_PATH = PROJECT_ROOT / "data" / "content" / "glory_map_runtime_index_v1.json"
GENERATED_DIRECTORY_PATH = PROJECT_ROOT / "data" / "maps" / "glory_map_directory_v1.json"
CONTENT_VERSION = "glory-map-runtime-v1"
CELL_SIZE = (48, 12)
WORLD_IDS = {
    "NFT_BL": "buli",
    "NFT_BT": "glory_nft_bt",
    "NFT_BTB": "glory_nft_btb",
    "NFT_DS": "glory_nft_ds",
    "NFT_PL": "glory_nft_pl",
    "NFT_SK": "glory_nft_sk",
}
REQUIRED_SOURCE_FILES = (
    "composite.png",
    "minimap.jpg",
    "navigation_grid.bin",
    "map_metadata.json",
    "scene_objects.json",
    "transitions.json",
)


@dataclass(frozen=True)
class Presentation:
    resource_id: str
    source: Path
    relative_source: str
    size_bytes: int


def read_object(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8-sig"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be object: {path}")
    return value


def write_object(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2, sort_keys=False) + "\n",
        encoding="utf-8",
    )


def stable_token(value: str) -> str:
    token = re.sub(r"[^a-z0-9]+", "_", value.lower()).strip("_")
    if token:
        return token
    return "source_" + hashlib.sha256(value.encode("utf-8")).hexdigest()[:12]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def existing_definitions() -> tuple[dict[str, str], dict[tuple[str, str], str]]:
    """Return current directory entries and their world/legacy runtime index."""
    directory = read_object(CURRENT_DIRECTORY_PATH)
    paths = dict(directory.get("definitions", {}))
    legacy: dict[tuple[str, str], str] = {}
    for map_id, resource_path in paths.items():
        path = PROJECT_ROOT / str(resource_path).removeprefix("res://")
        if not path.is_file():
            continue
        definition = read_object(path)
        world_id = str(definition.get("world", {}).get("id", "legacy_world"))
        for code in definition.get("legacy", {}).get("codes", []):
            legacy[(world_id, str(code).lower())] = str(map_id)
    return paths, legacy


def discover_presentations() -> dict[str, Presentation]:
    """Index every complete parsed presentation by known registry resource ID."""
    result: dict[str, Presentation] = {}
    for metadata_path in sorted(PARSED_MAP_ROOT.rglob("map_metadata.json")):
        source = metadata_path.parent
        if not all((source / filename).is_file() for filename in REQUIRED_SOURCE_FILES):
            continue
        relative = source.relative_to(PARSED_MAP_ROOT).as_posix()
        resource_id = "maps/" + relative
        size = sum((source / name).stat().st_size for name in REQUIRED_SOURCE_FILES)
        result[resource_id.lower()] = Presentation(resource_id, source, relative, size)
    return result


def resolve_presentation(
    resource_ids: Iterable[Any],
    presentations: dict[str, Presentation],
) -> Presentation | None:
    for resource_id_value in resource_ids:
        resource_id = str(resource_id_value).replace("\\", "/").strip("/")
        candidate = presentations.get(resource_id.lower())
        if candidate is not None:
            return candidate
        # Older registry rows may omit the sole variant directory.
        prefix = resource_id.lower() + "/variant_"
        matches = [value for key, value in presentations.items() if key.startswith(prefix)]
        if len(matches) == 1:
            return matches[0]
    return None


def runtime_id(world_code: str, map_code: str) -> str:
    return "glory_%s_%s" % (stable_token(world_code), stable_token(map_code))


def closest_walkable(source: Path, metadata: dict[str, Any]) -> list[int]:
    width, height = (int(value) for value in metadata["map_pixel_size"])
    grid_width, grid_height = (int(value) for value in metadata["engine_grid_size"])
    navigation = (source / "navigation_grid.bin").read_bytes()
    if len(navigation) != grid_width * grid_height:
        raise ValueError(f"navigation size mismatch: {source}")
    center_x, center_y = width / 2.0, height / 2.0
    best: tuple[float, int, int] | None = None
    for y in range(grid_height):
        row_offset = y * grid_width
        for x in range(grid_width):
            if navigation[row_offset + x] == 0:
                continue
            world_x = x * CELL_SIZE[0] + (CELL_SIZE[0] // 2 if y % 2 else 0)
            world_y = y * CELL_SIZE[1]
            candidate = (
                (world_x - center_x) ** 2 + (world_y - center_y) ** 2,
                world_x,
                world_y,
            )
            if best is None or candidate < best:
                best = candidate
    if best is None:
        raise ValueError(f"map has no walkable cell: {source}")
    return [best[1], best[2]]


def direction(point: list[int], size: list[int]) -> str:
    angle = math.atan2(point[1] - size[1] / 2.0, point[0] - size[0] / 2.0)
    sector = int(round(angle / (math.pi / 4.0))) % 8
    return (
        "east", "south_east", "south", "south_west",
        "west", "north_west", "north", "north_east",
    )[sector]


def build_transition(
    raw: dict[str, Any],
    ordinal: int,
    world_code: str,
    world_id: str,
    target_ids: dict[tuple[str, str], str],
    map_size: list[int],
) -> dict[str, Any]:
    destination_code = str(raw.get("destination_map_code", "")).lower()
    destination_id = target_ids.get((world_code, destination_code), "")
    destination: dict[str, Any] = {
        "world_id": world_id,
        "legacy_code": destination_code,
        "entry_number": int(raw.get("destination_entry_number", 0)),
        "external": not bool(destination_id),
    }
    if destination_id:
        destination["map_id"] = destination_id
    raw_anchor = raw.get("icon_anchor") or [0, 0]
    anchor = [int(value) for value in raw_anchor]
    raw_approach = raw.get("approach_point") or anchor
    approach = [int(value) for value in raw_approach]
    return {
        "transition_id": "exit_to_%s_%02d" % (stable_token(destination_code), ordinal),
        "kind": "standard",
        "enabled": True,
        "label": str(raw.get("label") or "通往%s" % destination_code.upper()),
        "source_anchor": anchor,
        "approach_point": approach,
        "presentation": {
            "kind": "directional_transition",
            "orientation": direction(anchor, map_size),
            "activation": "enabled_transition",
        },
        "destination": destination,
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_map_code": str(raw.get("source_map_code", "")),
            "source_output": str(raw.get("source_map_output", "")),
            "source_line": int(raw.get("source_line", 0)),
            "source_icon_ale": str(raw.get("icon_ale", "")),
        },
    }


def build_manifest(presentation: Presentation, metadata: dict[str, Any]) -> dict[str, Any]:
    scene = read_object(presentation.source / "scene_objects.json")
    return {
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "composition": {
            "render_strategy": "flattened_source_composite",
            "props": [],
            "missing_dependencies": scene.get("missing", []),
            "validation": {
                "source_composite_sha256": sha256(presentation.source / "composite.png"),
                "flattened_static_scene": True,
                "semantic_occlusion_available": False,
            },
        },
        "source_audit": {
            "source_map_code": str(metadata.get("map_code", "")),
            "source_output": "starhome_lz_ry_maps_parsed/maps/" + presentation.relative_source,
            "resolved_placements": int(metadata.get("scene_objects", {}).get("resolved", 0)),
            "missing_placements": int(metadata.get("scene_objects", {}).get("missing", 0)),
        },
    }


def build_definition(
    row: dict[str, Any],
    presentation: Presentation,
    map_id: str,
    world_id: str,
    target_ids: dict[tuple[str, str], str],
) -> dict[str, Any]:
    metadata = read_object(presentation.source / "map_metadata.json")
    transitions = read_object(presentation.source / "transitions.json")
    map_size = [int(value) for value in metadata["map_pixel_size"]]
    map_code = str(row["map_code"]).lower()
    asset_root = "content/glory/maps/" + presentation.relative_source
    category = "field" if metadata.get("category") == "field_code" else "scene"
    actor = {
        "kind": "combat_actor",
        "actor_id": "starter_combat_vehicle",
        "manifest": "res://assets/equipment_world/combat_visual_manifest.json",
        "animation_evidence": {
            "directional_coverage": "source_confirmed_eight_way",
            "move_cycle": "source_confirmed_four_frames_per_direction",
            "idle_cycle": "reconstructed_directional_first_frame",
        },
    } if category == "field" else {"kind": "character"}
    raw_transitions = transitions.get("enabled", [])
    return {
        "schema_version": 1,
        "map_id": map_id,
        "display_name": str(metadata.get("map_system_label") or metadata.get("map_name") or row["display_name"]),
        "category": category,
        "legacy": {"codes": [map_code]},
        "world": {
            "id": world_id,
            "size": map_size,
            "navigation": {
                "grid_size": [int(value) for value in metadata["engine_grid_size"]],
                "cell_size": list(CELL_SIZE),
                "data_path": "res://%s/navigation_grid.bin" % asset_root,
            },
        },
        "assets": {
            "ids": {
                "floor": asset_root + "/floor",
                "minimap": asset_root + "/minimap",
                "scene_manifest": asset_root + "/scene_manifest",
            },
            "resources": {
                "floor": "res://%s/floor.png" % asset_root,
                "minimap": "res://%s/minimap.jpg" % asset_root,
                "scene_manifest": "res://%s/scene_manifest.json" % asset_root,
            },
        },
        "spawn_points": {
            "default_id": "map_center",
            "points": [{
                "spawn_id": "map_center",
                "entry_number": 0,
                "position": closest_walkable(presentation.source, metadata),
                "enabled": True,
                "evidence_level": "navigation_derived",
                "source_audit": {
                    "source_release": "starhome_lz_ry",
                    "source_map_code": map_code,
                    "source_output": presentation.relative_source + "/navigation_grid.bin",
                    "derivation": "nearest confirmed walkable cell to map center",
                },
            }],
        },
        "navigation_overrides": [],
        "player_presentation": actor,
        "transitions": [
            build_transition(raw, index, str(row["world_code"]), world_id, target_ids, map_size)
            for index, raw in enumerate(raw_transitions)
        ],
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_world": str(row["world_code"]),
            "source_map_code": map_code,
            "source_map_name": str(metadata.get("map_name", "")),
            "source_output": presentation.relative_source,
            "source_script_sha256": str(metadata.get("script_sha256", "")),
            "navigation_sha256": sha256(presentation.source / "navigation_grid.bin"),
            "navigation_passable": int(metadata["navigation"]["passable"]),
            "navigation_blocked": int(metadata["navigation"]["blocked"]),
            "presentation_state": "runtime_ready_flattened",
        },
    }


def fixed_zip_info(path: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    return info


def add_file(archive: zipfile.ZipFile, source: Path, target: str) -> None:
    archive.writestr(fixed_zip_info(target), source.read_bytes())


def add_json(archive: zipfile.ZipFile, value: dict[str, Any], target: str) -> None:
    payload = (json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    archive.writestr(fixed_zip_info(target), payload)


def partition_presentations(
    presentations: list[Presentation],
    maximum_bytes: int,
) -> list[list[Presentation]]:
    parts: list[list[Presentation]] = []
    current: list[Presentation] = []
    current_size = 0
    for presentation in presentations:
        if current and current_size + presentation.size_bytes > maximum_bytes:
            parts.append(current)
            current = []
            current_size = 0
        current.append(presentation)
        current_size += presentation.size_bytes
    if current:
        parts.append(current)
    return parts


def build(arguments: argparse.Namespace) -> dict[str, Any]:
    known = read_object(KNOWN_MAPS_PATH)
    current_paths, existing_legacy = existing_definitions()
    presentations = discover_presentations()
    rows: list[dict[str, Any]] = list(known.get("definitions", []))
    target_ids: dict[tuple[str, str], str] = {}
    resolved_rows: list[tuple[dict[str, Any], Presentation, str, str]] = []
    unresolved_rows: list[str] = []
    for row in rows:
        world_code = str(row["world_code"])
        world_id = WORLD_IDS.get(world_code, "glory_" + stable_token(world_code))
        map_code = str(row["map_code"]).lower()
        existing_id = existing_legacy.get((world_id, map_code), "")
        generated_id = existing_id or runtime_id(world_code, map_code)
        target_ids[(world_code, map_code)] = generated_id
        presentation = resolve_presentation(row.get("resource_ids", []), presentations)
        if presentation is None:
            unresolved_rows.append(str(row["id"]))
            continue
        resolved_rows.append((row, presentation, generated_id, world_id))

    generated_definitions: dict[str, dict[str, Any]] = {}
    runtime_rows: list[dict[str, Any]] = []
    used_presentations: dict[str, Presentation] = {}
    for row, presentation, map_id, world_id in resolved_rows:
        is_existing = map_id in current_paths
        if not is_existing:
            generated_definitions[map_id] = build_definition(
                row, presentation, map_id, world_id, target_ids
            )
        used_presentations[presentation.relative_source.lower()] = presentation
        runtime_rows.append({
            "source_id": row["id"],
            "world_code": row["world_code"],
            "map_code": row["map_code"],
            "runtime_id": map_id,
            "definition_path": current_paths.get(
                map_id, "res://content/glory/map_definitions/%s.json" % map_id
            ),
            "presentation_id": presentation.resource_id,
            "presentation_mode": "semantic" if is_existing else "flattened_source_composite",
        })

    plan = {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "source_rows": len(rows),
        "resolved_runtime_rows": len(runtime_rows),
        "generated_definitions": len(generated_definitions),
        "existing_semantic_definitions": len(runtime_rows) - len(generated_definitions),
        "unique_presentations": len(used_presentations),
        "unresolved_source_rows": len(unresolved_rows),
    }
    if arguments.plan_only:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return plan

    PACK_ROOT.mkdir(parents=True, exist_ok=True)
    index_pack = PACK_ROOT / "glory_maps_index_v1.zip"
    with zipfile.ZipFile(index_pack, "w", allowZip64=True) as archive:
        for map_id, definition in sorted(generated_definitions.items()):
            add_json(archive, definition, "content/glory/map_definitions/%s.json" % map_id)

    parts = partition_presentations(
        sorted(used_presentations.values(), key=lambda item: item.relative_source.lower()),
        int(arguments.maximum_pack_mib * 1024 * 1024),
    )
    pack_files = [index_pack]
    for part_index, part in enumerate(parts, start=1):
        pack_path = PACK_ROOT / ("glory_maps_%03d_v1.zip" % part_index)
        with zipfile.ZipFile(pack_path, "w", allowZip64=True) as archive:
            for presentation in part:
                root = "content/glory/maps/" + presentation.relative_source
                metadata = read_object(presentation.source / "map_metadata.json")
                add_file(archive, presentation.source / "composite.png", root + "/floor.png")
                add_file(archive, presentation.source / "minimap.jpg", root + "/minimap.jpg")
                add_file(archive, presentation.source / "navigation_grid.bin", root + "/navigation_grid.bin")
                add_json(archive, build_manifest(presentation, metadata), root + "/scene_manifest.json")
                add_file(archive, presentation.source / "scene_objects.json", root + "/source_scene_objects.json")
                add_file(archive, presentation.source / "transitions.json", root + "/source_transitions.json")
                add_file(archive, presentation.source / "map_metadata.json", root + "/source_metadata.json")
        pack_files.append(pack_path)
        print("BUILT", pack_path.name, len(part), "presentations")

    pack_entries = []
    for path in pack_files:
        pack_entries.append({
            "pack_id": path.stem,
            "path": "res://assets/content_packs/" + path.name,
            "size_bytes": path.stat().st_size,
            "sha256": sha256(path),
            "content_groups": ["maps"],
        })
    write_object(CATALOG_PATH, {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "packs": pack_entries,
        "summary": plan,
    })
    write_object(RUNTIME_INDEX_PATH, {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "summary": plan,
        "runtime_maps": runtime_rows,
        "unresolved_source_ids": unresolved_rows,
    })
    merged_paths = dict(current_paths)
    for map_id in generated_definitions:
        merged_paths[map_id] = "res://content/glory/map_definitions/%s.json" % map_id
    write_object(GENERATED_DIRECTORY_PATH, {
        "schema_version": 1,
        "directory_id": "glory_all_runtime_maps",
        "definitions": dict(sorted(merged_paths.items())),
        "content_pack_catalog": "res://data/content/glory_map_content_packs_v1.json",
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_registry": "res://data/content/known_maps_v1.json",
        },
    })
    print(json.dumps(plan, ensure_ascii=False))
    print("GLORY_MAP_CONTENT_PACKS_BUILT", len(pack_files), "packs")
    return plan


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--maximum-pack-mib", type=int, default=1536)
    arguments = parser.parse_args()
    if arguments.maximum_pack_mib < 64:
        parser.error("--maximum-pack-mib must be at least 64")
    build(arguments)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
