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
import io
import json
import math
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

from PIL import Image

try:
    from tools.import_glory_map_presentation import (
        build_scene_ownership,
        load_first_frame,
        resolve_frame_source,
        scene_placement_key,
        transition_placement_keys,
    )
except ModuleNotFoundError:  # Direct execution from the tools directory.
    from import_glory_map_presentation import (  # type: ignore[no-redef]
        build_scene_ownership,
        load_first_frame,
        resolve_frame_source,
        scene_placement_key,
        transition_placement_keys,
    )


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
TRANSITION_RECOVERY_WORLD = "NFT_BL"
TRANSITION_RECOVERY_BRANCH = "NFT_BT"
REQUIRED_SOURCE_FILES = (
    "background.png",
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


def write_runtime_index(
    path: Path,
    summary: dict[str, Any],
    rows: list[dict[str, Any]],
    unresolved: list[str],
) -> None:
    """Keep the large generated index reviewable and below commit line limits."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "{",
        '  "schema_version": 1,',
        '  "content_version": %s,' % json.dumps(CONTENT_VERSION),
        '  "summary": %s,' % json.dumps(summary, ensure_ascii=False, separators=(",", ":")),
        '  "runtime_maps": [',
    ]
    for index, row in enumerate(rows):
        suffix = "," if index + 1 < len(rows) else ""
        lines.append("    " + json.dumps(row, ensure_ascii=False, separators=(",", ":")) + suffix)
    lines.extend([
        "  ],",
        '  "unresolved_source_ids": %s' % json.dumps(unresolved, ensure_ascii=False),
        "}",
    ])
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


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


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def existing_definitions() -> tuple[
    dict[str, str],
    dict[tuple[str, str], str],
    set[str],
]:
    """Return current directory entries and their world/legacy runtime index."""
    directory = read_object(CURRENT_DIRECTORY_PATH)
    paths = dict(directory.get("definitions", {}))
    legacy: dict[tuple[str, str], str] = {}
    presentation_ready: set[str] = set()
    for map_id, resource_path in paths.items():
        path = PROJECT_ROOT / str(resource_path).removeprefix("res://")
        if not path.is_file():
            continue
        definition = read_object(path)
        resources = definition.get("assets", {}).get("resources", {})
        if all(
            (PROJECT_ROOT / str(resources.get(key, "")).removeprefix("res://")).is_file()
            for key in ("floor", "minimap", "scene_manifest")
        ):
            presentation_ready.add(str(map_id))
        world_id = str(definition.get("world", {}).get("id", "legacy_world"))
        for code in definition.get("legacy", {}).get("codes", []):
            legacy[(world_id, str(code).lower())] = str(map_id)
    return paths, legacy, presentation_ready


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


def world_to_cell(position: list[int]) -> tuple[int, int]:
    """Convert one nEngine world position to its diamond navigation cell."""
    projected_y = position[1] * CELL_SIZE[0] / (2.0 * CELL_SIZE[1]) + CELL_SIZE[0] * 0.5
    positive = math.floor((projected_y + position[0]) / CELL_SIZE[0])
    negative = math.floor((projected_y - position[0]) / CELL_SIZE[0])
    return math.floor((positive - negative) / 2.0), positive + negative


def is_walkable(source: Path, metadata: dict[str, Any], position: list[int]) -> bool:
    """Return whether one world position belongs to a passable source cell."""
    grid_width, grid_height = (int(value) for value in metadata["engine_grid_size"])
    cell_x, cell_y = world_to_cell(position)
    if cell_x < 0 or cell_x >= grid_width or cell_y < 0 or cell_y >= grid_height:
        return False
    navigation = (source / "navigation_grid.bin").read_bytes()
    return navigation[cell_y * grid_width + cell_x] != 0


def closest_walkable_to(
    source: Path,
    metadata: dict[str, Any],
    requested: list[int],
) -> list[int]:
    """Keep recovered markers usable when sibling layouts differ locally."""
    if is_walkable(source, metadata, requested):
        return requested
    grid_width, grid_height = (int(value) for value in metadata["engine_grid_size"])
    navigation = (source / "navigation_grid.bin").read_bytes()
    best: tuple[float, int, int] | None = None
    for cell_y in range(grid_height):
        for cell_x in range(grid_width):
            if navigation[cell_y * grid_width + cell_x] == 0:
                continue
            world_x = cell_x * CELL_SIZE[0] + (CELL_SIZE[0] // 2 if cell_y % 2 else 0)
            world_y = cell_y * CELL_SIZE[1]
            candidate = (
                (world_x - requested[0]) ** 2 + (world_y - requested[1]) ** 2,
                world_x,
                world_y,
            )
            if best is None or candidate < best:
                best = candidate
    if best is None:
        raise ValueError(f"map has no walkable cell: {source}")
    return [best[1], best[2]]


def recover_empty_buli_field_transitions(
    row: dict[str, Any],
    presentation: Presentation,
    metadata: dict[str, Any],
    raw_transitions: list[dict[str, Any]],
) -> tuple[list[dict[str, Any]], str]:
    """Recover an empty Buli exit table from the Glory sibling world only.

    Some NFT_BL field FCC files contain the complete map and navigation payload
    but omit every editor Transport record. NFT_BT retains those records for a
    subset of the same 4824x4800 field codes. Recovery is intentionally limited
    to an entirely empty table; existing branch-specific topology always wins.
    """
    if raw_transitions or str(row.get("world_code", "")) != TRANSITION_RECOVERY_WORLD:
        return raw_transitions, ""
    if str(metadata.get("category", "")) != "field_code":
        return raw_transitions, ""
    for sibling in sorted(presentation.source.parent.iterdir()):
        metadata_path = sibling / "map_metadata.json"
        transitions_path = sibling / "transitions.json"
        if not metadata_path.is_file() or not transitions_path.is_file():
            continue
        sibling_metadata = read_object(metadata_path)
        if TRANSITION_RECOVERY_BRANCH not in sibling_metadata.get("source_branches", []):
            continue
        sibling_transitions = list(read_object(transitions_path).get("enabled", []))
        if not sibling_transitions:
            continue
        recovered: list[dict[str, Any]] = []
        for source_record in sibling_transitions:
            record = dict(source_record)
            original_approach = [int(value) for value in record.get("approach_point", [0, 0])]
            record["approach_point"] = closest_walkable_to(
                presentation.source,
                metadata,
                original_approach,
            )
            record["_recovery_original_approach_point"] = original_approach
            record["_recovery_source_output"] = sibling.relative_to(PARSED_MAP_ROOT).as_posix()
            recovered.append(record)
        return recovered, sibling.relative_to(PARSED_MAP_ROOT).as_posix()
    return raw_transitions, ""


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
    source_audit = {
        "source_release": "starhome_lz_ry",
        "source_map_code": str(raw.get("source_map_code", "")),
        "source_output": str(raw.get("source_map_output", "")),
        "source_line": int(raw.get("source_line", 0)),
        "source_icon_ale": str(raw.get("icon_ale", "")),
    }
    recovery_output = str(raw.get("_recovery_source_output", ""))
    if recovery_output:
        source_audit["recovery"] = {
            "kind": "same_release_sibling_world_transport_metadata",
            "source_world": TRANSITION_RECOVERY_BRANCH,
            "source_output": recovery_output,
            "original_approach_point": raw.get("_recovery_original_approach_point", approach),
            "walkable_approach_corrected": approach
                != raw.get("_recovery_original_approach_point", approach),
        }
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
        "source_audit": source_audit,
    }


def build_runtime_floor(presentation: Presentation) -> tuple[bytes, dict[str, Any]]:
    """Return a flattened floor with transition-owned static frames removed."""
    scene = read_object(presentation.source / "scene_objects.json")
    transitions = read_object(presentation.source / "transitions.json")
    transition_keys = transition_placement_keys(transitions)
    matching_items = [
        item
        for item in scene.get("objects", [])
        if isinstance(item, dict) and scene_placement_key(item) in transition_keys
    ]
    source_composite = presentation.source / "composite.png"
    if not matching_items:
        payload = source_composite.read_bytes()
        return payload, {
            "excluded_static_transition_placements": 0,
            "unresolved_static_transition_sources": 0,
            "runtime_floor_sha256": sha256_bytes(payload),
        }

    with Image.open(presentation.source / "background.png") as image:
        background = image.convert("RGBA")
    with Image.open(source_composite) as image:
        runtime_floor = image.convert("RGBA")

    filtered_scene, _, _, _, _, excluded = build_scene_ownership(
        background,
        scene,
        "runtime/flattened",
        transition_keys,
    )
    restored_composite = Image.alpha_composite(background, filtered_scene)
    transition_layer = Image.new("RGBA", background.size, (0, 0, 0, 0))
    frame_cache: dict[str, tuple[Image.Image, dict[str, Any]]] = {}
    unresolved_sources = 0
    for item in matching_items:
        source = resolve_frame_source(item)
        if source is None:
            # The parsed composite could not contain a frame which the source
            # extractor itself marked missing. Keep the registry placement
            # excluded without inventing a footprint for malformed legacy
            # paths such as ``jt-08..ale``.
            if str(item.get("status", "")) == "missing":
                unresolved_sources += 1
                continue
            raise FileNotFoundError(
                "Cannot remove transition placement without its source frame: "
                + str(item.get("source_ale", ""))
            )
        source_image, frame = load_first_frame(source, frame_cache)
        anchor = item.get("anchor", [0, 0])
        if "top_left" in item:
            top_left = (int(item["top_left"][0]), int(item["top_left"][1]))
        else:
            top_left = (
                int(anchor[0]) + int(frame.get("origin_x", 0)),
                int(anchor[1]) + int(frame.get("origin_y", 0)),
            )
        transition_layer.alpha_composite(source_image, top_left)

    # Replace the complete transition footprint rather than alpha-blending it
    # again; the parsed composite already contains the old first frame.
    binary_mask = transition_layer.getchannel("A").point(lambda alpha: 255 if alpha else 0)
    runtime_floor.paste(restored_composite, (0, 0), binary_mask)
    output = io.BytesIO()
    runtime_floor.save(output, format="PNG", compress_level=3)
    payload = output.getvalue()
    return payload, {
        "excluded_static_transition_placements": len(excluded),
        "unresolved_static_transition_sources": unresolved_sources,
        "runtime_floor_sha256": sha256_bytes(payload),
    }


def build_manifest(
    presentation: Presentation,
    metadata: dict[str, Any],
    runtime_floor_audit: dict[str, Any],
) -> dict[str, Any]:
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
                "runtime_floor_sha256": runtime_floor_audit["runtime_floor_sha256"],
                "flattened_static_scene": True,
                "semantic_occlusion_available": False,
                "excluded_static_transition_placements": runtime_floor_audit[
                    "excluded_static_transition_placements"
                ],
                "unresolved_static_transition_sources": runtime_floor_audit[
                    "unresolved_static_transition_sources"
                ],
                "runtime_transition_registry_only": True,
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
    business_asset_root = "maps/runtime/map_" + hashlib.sha256(
        str(row["id"]).encode("utf-8")
    ).hexdigest()[:12]
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
    raw_transitions = list(transitions.get("enabled", []))
    raw_transitions, recovery_output = recover_empty_buli_field_transitions(
        row,
        presentation,
        metadata,
        raw_transitions,
    )
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
                "floor": business_asset_root + "/floor",
                "minimap": business_asset_root + "/minimap",
                "scene_manifest": business_asset_root + "/scene_manifest",
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
            "promoted_transition_count": len(raw_transitions),
            "transition_recovery": ({
                "kind": "same_release_sibling_world_transport_metadata",
                "source_world": TRANSITION_RECOVERY_BRANCH,
                "source_output": recovery_output,
            } if recovery_output else None),
        },
    }


def fixed_zip_info(path: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    return info


def add_file(archive: zipfile.ZipFile, source: Path, target: str) -> None:
    archive.writestr(fixed_zip_info(target), source.read_bytes())


def add_bytes(archive: zipfile.ZipFile, payload: bytes, target: str) -> None:
    archive.writestr(fixed_zip_info(target), payload)


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
    current_paths, existing_legacy, existing_ready = existing_definitions()
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
        presentation = resolve_presentation(row.get("resource_ids", []), presentations)
        if presentation is None:
            unresolved_rows.append(str(row["id"]))
            continue
        target_ids[(world_code, map_code)] = generated_id
        resolved_rows.append((row, presentation, generated_id, world_id))

    generated_definitions: dict[str, dict[str, Any]] = {}
    runtime_rows: list[dict[str, Any]] = []
    used_presentations: dict[str, Presentation] = {}
    for row, presentation, map_id, world_id in resolved_rows:
        is_existing = map_id in existing_ready
        if not is_existing:
            generated_definitions[map_id] = build_definition(
                row, presentation, map_id, world_id, target_ids
            )
        used_presentations[presentation.relative_source.lower()] = presentation
        runtime_rows.append({
            "source_id": row["id"],
            "world_code": row["world_code"],
            "world_id": world_id,
            "map_code": row["map_code"],
            "runtime_id": map_id,
            "definition_path": current_paths[map_id] if is_existing
                else "res://content/glory/map_definitions/%s.json" % map_id,
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

    pack_files = [index_pack]
    if arguments.index_only:
        pack_files.extend(sorted(PACK_ROOT.glob("glory_maps_[0-9][0-9][0-9]_v1.zip")))
        if len(pack_files) == 1:
            raise FileNotFoundError("--index-only requires existing Glory presentation packs")
    else:
        parts = partition_presentations(
            sorted(used_presentations.values(), key=lambda item: item.relative_source.lower()),
            int(arguments.maximum_pack_mib * 1024 * 1024),
        )
        for part_index, part in enumerate(parts, start=1):
            pack_path = PACK_ROOT / ("glory_maps_%03d_v1.zip" % part_index)
            with zipfile.ZipFile(pack_path, "w", allowZip64=True) as archive:
                for presentation in part:
                    root = "content/glory/maps/" + presentation.relative_source
                    metadata = read_object(presentation.source / "map_metadata.json")
                    runtime_floor, runtime_floor_audit = build_runtime_floor(presentation)
                    add_bytes(archive, runtime_floor, root + "/floor.png")
                    add_file(archive, presentation.source / "minimap.jpg", root + "/minimap.jpg")
                    add_file(archive, presentation.source / "navigation_grid.bin", root + "/navigation_grid.bin")
                    add_json(
                        archive,
                        build_manifest(presentation, metadata, runtime_floor_audit),
                        root + "/scene_manifest.json",
                    )
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
    write_runtime_index(RUNTIME_INDEX_PATH, plan, runtime_rows, unresolved_rows)
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
    parser.add_argument("--index-only", action="store_true")
    parser.add_argument("--maximum-pack-mib", type=int, default=1536)
    arguments = parser.parse_args()
    if arguments.maximum_pack_mib < 64:
        parser.error("--maximum-pack-mib must be at least 64")
    build(arguments)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
