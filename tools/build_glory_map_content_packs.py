#!/usr/bin/env python3
"""Materialize Glory map presentations and typed runtime definitions.

Map presentations are rendered on demand from workspace-local raw FCC, images,
sprites and saved transition evidence. Existing hand-promoted maps keep their
semantic-layer definitions and are not duplicated in the generated directory.
Run --prepare-import to expose existing maps to Godot's native texture importer
without regenerating maps; sprite and palette archives remain ignored.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import re
import shutil
from dataclasses import dataclass, replace
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageChops
if __package__:
    from tools.glory_map_workspace import RawMapWorkspace
else:
    from glory_map_workspace import RawMapWorkspace

try:
    from tools.import_glory_map_presentation import (
        build_scene_ownership,
        build_chunks,
        load_first_frame,
        pack_chunks,
        resolve_frame_source,
        scene_placement_key,
        transition_placement_keys,
    )
except ModuleNotFoundError:  # Direct execution from the tools directory.
    from import_glory_map_presentation import (  # type: ignore[no-redef]
        build_scene_ownership,
        build_chunks,
        load_first_frame,
        pack_chunks,
        resolve_frame_source,
        scene_placement_key,
        transition_placement_keys,
    )


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MAP_EVIDENCE_ROOT = PROJECT_ROOT / "data" / "source_evidence" / "glory" / "map_recovery"
PARSED_MAP_ROOT = MAP_EVIDENCE_ROOT / "maps"
KNOWN_MAPS_PATH = PROJECT_ROOT / "data" / "content" / "known_maps_v1.json"
CURRENT_DIRECTORY_PATH = PROJECT_ROOT / "data" / "maps" / "map_directory.json"
MAP_CONTENT_ROOT = PROJECT_ROOT / "assets" / "glory" / "maps"
DEFINITION_CONTENT_ROOT = PROJECT_ROOT / "assets" / "glory" / "map_definitions"
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
    "navigation_grid.bin",
    "map_metadata.json",
    "scene_objects.json",
    "transitions.json",
)
CURATED_SEMANTIC_PRESENTATIONS = frozenset({
    "2beautyroom",
    "armshop1",
    "city1svr/variant_01_nft_bl",
    "clothshop1",
    "factory1",
    "foodroom1",
    "funroom1/variant_01_nft_bl",
    "nasa1/variant_01_nft_bl",
    "roomsvr1/variant_01_nft_bl",
    "shop1",
    "traderoom1",
    "treeroom1",
    "weaponshop1",
})
OFFICIAL_FULL_MAP_IMAGES = {
    "nasa1/variant_01_nft_bl": PROJECT_ROOT / "../starhome_lz_ry_full/raw/map/mapimg/jpg/NASA1.jpg",
}
@dataclass(frozen=True)
class Presentation:
    resource_id: str
    source: Path
    relative_source: str


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
    """Index audited map definitions without materializing their large images."""
    result: dict[str, Presentation] = {}
    for metadata_path in sorted(PARSED_MAP_ROOT.rglob("map_metadata.json")):
        source = metadata_path.parent
        if not all((source / filename).is_file() for filename in REQUIRED_SOURCE_FILES):
            continue
        if not (source / "minimap.jpg").is_file() and not (source / "thumbnail.jpg").is_file():
            continue
        relative = source.relative_to(PARSED_MAP_ROOT).as_posix()
        resource_id = "maps/" + relative
        result[resource_id.lower()] = Presentation(resource_id, source, relative)
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
        # The extractor preserves the FCC-expanded spelling for this legacy
        # source key, while the author registry records the logical map name.
        expanded = presentations.get((resource_id + "_fcc_expanded").lower())
        if expanded is not None:
            return expanded
    return None


def minimap_source(source: Path) -> Path:
    for name in ("minimap.jpg", "thumbnail.jpg"):
        candidate = source / name
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"map has neither minimap.jpg nor thumbnail.jpg: {source}")


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
    official_image = OFFICIAL_FULL_MAP_IMAGES.get(presentation.relative_source.lower())
    if official_image is not None and official_image.is_file() and not matching_items:
        with Image.open(official_image) as image:
            output = io.BytesIO()
            image.convert("RGBA").save(output, format="PNG", compress_level=3)
        payload = output.getvalue()
        return payload, {
            "excluded_static_transition_placements": 0,
            "unresolved_static_transition_sources": 0,
            "runtime_floor_sha256": sha256_bytes(payload),
            "official_full_map_image": official_image.relative_to(PROJECT_ROOT).as_posix(),
        }
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
    semantic: dict[str, Any] | None = None,
) -> dict[str, Any]:
    scene = read_object(presentation.source / "scene_objects.json")
    if semantic is not None:
        missing_dependencies = semantic["missing_dependencies"]
        partial = bool(missing_dependencies)
        return {
            "schema_version": 1,
            "source_release": "starhome_lz_ry",
            "composition": {
                "render_strategy": "semantic_foreground_overlay" if partial else "semantic_owner_layers",
                "semantic_atlas": semantic["atlas_resource"],
                "semantic_atlas_size": semantic["atlas_size"],
                "semantic_layers": semantic["layers"],
                "props": [],
                "missing_dependencies": missing_dependencies,
                "validation": {
                    "semantic_reconstruction_exact": not partial,
                    "semantic_occlusion_available": True,
                    "flattened_static_scene": partial,
                    "flattened_floor_overlay": partial,
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
                "minimap_source": minimap_source(presentation.source).name,
                "resolved_placements": int(metadata.get("scene_objects", {}).get("resolved", 0)),
                "missing_placements": len(missing_dependencies),
                "presentation_quality": "semantic_foreground_overlay" if partial else "semantic_foreground_layers",
            },
        }
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
                "official_full_map_image": runtime_floor_audit.get("official_full_map_image", ""),
            },
        },
        "source_audit": {
            "source_map_code": str(metadata.get("map_code", "")),
            "source_output": "starhome_lz_ry_maps_parsed/maps/" + presentation.relative_source,
            "minimap_source": minimap_source(presentation.source).name,
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
    semantic_presentation: bool,
) -> dict[str, Any]:
    metadata = read_object(presentation.source / "map_metadata.json")
    transitions = read_object(presentation.source / "transitions.json")
    map_size = [int(value) for value in metadata["map_pixel_size"]]
    map_code = str(row["map_code"]).lower()
    asset_root = "assets/glory/maps/" + presentation.relative_source
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
            "presentation_state": "runtime_ready_semantic" if semantic_presentation else "runtime_ready_flattened",
            "promoted_transition_count": len(raw_transitions),
            "transition_recovery": ({
                "kind": "same_release_sibling_world_transport_metadata",
                "source_world": TRANSITION_RECOVERY_BRANCH,
                "source_output": recovery_output,
            } if recovery_output else None),
        },
    }


def build_semantic_atlas(
    scene_color: Image.Image,
    owner: Any,
    owners: list[dict[str, Any]],
    atlas_path: Path,
) -> dict[str, Any] | None:
    chunks = build_chunks(scene_color, owner, owners)
    if not chunks:
        return None
    atlas, packed_chunks = pack_chunks(chunks)
    atlas.save(atlas_path, compress_level=3)
    owner_lookup = {int(item["owner_id"]): item for item in owners}
    atlas_resource = "res://" + str(atlas_path.relative_to(PROJECT_ROOT)).replace("\\", "/")
    layers = []
    for index, item in enumerate(sorted(
        packed_chunks,
        key=lambda value: (value["sort_baseline"], value["pixel_offset"][1], value["pixel_offset"][0]),
    )):
        layers.append({
            "layer_id": "semantic_scene_%04d" % index,
            "texture": atlas_resource,
            "atlas_region": item["atlas_region"],
            "pixel_offset": item["pixel_offset"],
            "size": item["size"],
            "sort_baseline": item["sort_baseline"],
            "owners": [
                {
                    "owner_id": owner_id,
                    "source_index": owner_lookup[owner_id]["source_index"],
                    "asset_id": owner_lookup[owner_id]["asset_id"],
                }
                for owner_id in item["owner_ids"]
            ],
        })
    return {
        "atlas_resource": atlas_resource,
        "atlas_size": list(atlas.size),
        "layers": layers,
    }


def _semantic_presentation(
    presentation: Presentation,
    target: Path,
    runtime_floor: bytes,
    runtime_floor_audit: dict[str, Any],
) -> dict[str, Any] | None:
    scene = read_object(presentation.source / "scene_objects.json")
    transitions = read_object(presentation.source / "transitions.json")
    transition_keys = transition_placement_keys(transitions)
    with Image.open(presentation.source / "background.png") as image:
        background = image.convert("RGBA")
    scene_color, owner, owners, missing, _, _ = build_scene_ownership(
        background,
        scene,
        "maps/runtime/" + presentation.relative_source,
        transition_keys,
    )
    semantic = build_semantic_atlas(
        scene_color,
        owner,
        owners,
        target / "semantic_layer_atlas.png",
    )
    if semantic is None:
        return None
    with Image.open(io.BytesIO(runtime_floor)) as image:
        runtime_floor_image = image.convert("RGBA")
    if not missing and ImageChops.difference(
        Image.alpha_composite(background, scene_color), runtime_floor_image
    ).getbbox() is not None:
        return None
    expected_floor = runtime_floor_image if missing else background
    expected_floor.save(target / "floor.png", compress_level=3)
    return {
        **semantic,
        "missing_dependencies": missing,
    }


def materialize_presentation(
    presentation: Presentation,
    target_root: Path,
    semantic_presentation: bool,
) -> Path:
    source = presentation.source
    target = target_root / presentation.relative_source
    target.mkdir(parents=True, exist_ok=True)
    metadata = read_object(source / "map_metadata.json")
    runtime_floor, floor_audit = build_runtime_floor(presentation)
    semantic = _semantic_presentation(
        presentation, target, runtime_floor, floor_audit
    ) if semantic_presentation else None
    if semantic is None:
        (target / "floor.png").write_bytes(runtime_floor)
    shutil.copyfile(minimap_source(source), target / "minimap.jpg")
    for source_name, target_name in (
        ("navigation_grid.bin", "navigation_grid.bin"),
        ("scene_objects.json", "source_scene_objects.json"),
        ("transitions.json", "source_transitions.json"),
        ("map_metadata.json", "source_metadata.json"),
    ):
        shutil.copyfile(source / source_name, target / target_name)
    write_object(target / "scene_manifest.json", build_manifest(
        presentation, metadata, floor_audit, semantic
    ))
    return target


def materialize_cached_semantic_overlay(target: Path) -> bool:
    floor_path = target / "floor.png"
    scene_path = target / "source_scene_objects.json"
    transition_path = target / "source_transitions.json"
    manifest_path = target / "scene_manifest.json"
    if not all(path.is_file() for path in (floor_path, scene_path, transition_path, manifest_path)):
        return False
    scene = read_object(scene_path)
    transitions = read_object(transition_path)
    with Image.open(floor_path) as image:
        background = Image.new("RGBA", image.size, (0, 0, 0, 0))
    scene_color, owner, owners, _, _, _ = build_scene_ownership(
        background,
        scene,
        "maps/runtime/" + target.relative_to(MAP_CONTENT_ROOT).as_posix(),
        transition_placement_keys(transitions),
    )
    semantic = build_semantic_atlas(
        scene_color,
        owner,
        owners,
        target / "semantic_layer_atlas.png",
    )
    if semantic is None:
        return False
    manifest = read_object(manifest_path)
    manifest["composition"] = {
        "render_strategy": "semantic_foreground_overlay",
        "semantic_atlas": semantic["atlas_resource"],
        "semantic_atlas_size": semantic["atlas_size"],
        "semantic_layers": semantic["layers"],
        "props": [],
        "missing_dependencies": scene.get("missing", []),
        "validation": {
            "semantic_occlusion_available": True,
            "semantic_reconstruction_exact": False,
            "flattened_floor_overlay": True,
            "runtime_transition_registry_only": True,
        },
    }
    manifest.setdefault("source_audit", {})["presentation_quality"] = "semantic_foreground_overlay"
    write_object(manifest_path, manifest)
    return True


def build(arguments: argparse.Namespace) -> dict[str, Any]:
    known = read_object(KNOWN_MAPS_PATH)
    current_paths, existing_legacy, existing_ready = existing_definitions()
    presentations = discover_presentations()
    rows: list[dict[str, Any]] = list(known.get("definitions", []))
    target_ids: dict[tuple[str, str], str] = {}
    resolved_rows: list[tuple[dict[str, Any], Presentation, str, str]] = []
    unresolved_rows: list[str] = []
    for row in rows:
        if row.get("availability", {}).get("runtime") != "ready":
            unresolved_rows.append(str(row["id"]))
            continue
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
    field_presentations = {
        presentation.relative_source.lower()
        for row, presentation, _, _ in resolved_rows
        if row.get("category") == "field_code"
    }
    materialized_semantic_presentations = {
        presentation.relative_source.lower()
        for _, presentation, _, _ in resolved_rows
        if (
            (MAP_CONTENT_ROOT / presentation.relative_source / "scene_manifest.json").is_file()
            and read_object(MAP_CONTENT_ROOT / presentation.relative_source / "scene_manifest.json")
            .get("composition", {}).get("render_strategy")
            in ["semantic_owner_layers", "semantic_foreground_overlay"]
        )
    }
    semantic_presentations = materialized_semantic_presentations
    semantic_candidates = semantic_presentations | CURATED_SEMANTIC_PRESENTATIONS
    for row, presentation, map_id, world_id in resolved_rows:
        is_existing = map_id in existing_ready
        if not is_existing:
            generated_definitions[map_id] = build_definition(
                row,
                presentation,
                map_id,
                world_id,
                target_ids,
                presentation.relative_source.lower() in semantic_presentations,
            )
        used_presentations[presentation.relative_source.lower()] = presentation
        runtime_rows.append({
            "source_id": row["id"],
            "world_code": row["world_code"],
            "world_id": world_id,
            "map_code": row["map_code"],
            "runtime_id": map_id,
            "definition_path": current_paths[map_id] if is_existing
                else "res://assets/glory/map_definitions/%s.json" % map_id,
            "presentation_id": presentation.resource_id,
            "presentation_mode": "semantic" if presentation.relative_source.lower() in semantic_presentations else "flattened_source_composite",
        })

    plan = {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "source_rows": len(rows),
        "resolved_runtime_rows": len(runtime_rows),
        "generated_definitions": len(generated_definitions),
        "existing_semantic_definitions": len(runtime_rows) - len(generated_definitions),
        "unique_presentations": len(used_presentations),
        "field_presentations": len(field_presentations),
        "semantic_presentations": len(semantic_presentations),
        "unresolved_source_rows": len(unresolved_rows),
    }
    if arguments.plan_only:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return plan

    if not arguments.materialize_only:
        for map_id, definition in sorted(generated_definitions.items()):
            write_object(DEFINITION_CONTENT_ROOT / (map_id + ".json"), definition)
    if arguments.cached_semantic_only or (arguments.semantic_only and not arguments.index_only):
        for indexed in sorted(used_presentations.values(), key=lambda item: item.relative_source.lower()):
            if arguments.field_only and indexed.relative_source.lower() not in field_presentations:
                continue
            if arguments.semantic_only and indexed.relative_source.lower() not in semantic_candidates:
                continue
            if materialize_cached_semantic_overlay(MAP_CONTENT_ROOT / indexed.relative_source):
                print("BUILT CACHED", indexed.relative_source)
    elif not arguments.index_only:
        with RawMapWorkspace() as workspace:
            selected_presentations = sorted(
                used_presentations.values(), key=lambda item: item.relative_source.lower()
            )
            if arguments.semantic_batches > 1:
                selected_presentations = [
                    indexed
                    for index, indexed in enumerate(selected_presentations)
                    if index % arguments.semantic_batches == arguments.semantic_batch
                ]
            for indexed in selected_presentations:
                if arguments.field_only and indexed.relative_source.lower() not in field_presentations:
                    continue
                if arguments.semantic_only and indexed.relative_source.lower() not in semantic_candidates:
                    continue
                with workspace.render(indexed.relative_source) as (source, _):
                    materialize_presentation(
                        replace(indexed, source=source),
                        MAP_CONTENT_ROOT,
                        indexed.relative_source.lower() in semantic_candidates,
                    )
                print("BUILT", indexed.relative_source)
    if arguments.cached_semantic_only or (arguments.semantic_only and not arguments.index_only):
        semantic_presentations = {
            indexed.relative_source.lower()
            for indexed in used_presentations.values()
            if (
                (MAP_CONTENT_ROOT / indexed.relative_source / "scene_manifest.json").is_file()
                and read_object(MAP_CONTENT_ROOT / indexed.relative_source / "scene_manifest.json")
                .get("composition", {}).get("render_strategy")
                in ["semantic_owner_layers", "semantic_foreground_overlay"]
            )
        }
        for runtime_row in runtime_rows:
            presentation_id = str(runtime_row["presentation_id"]).removeprefix("maps/").lower()
            runtime_row["presentation_mode"] = (
                "semantic" if presentation_id in semantic_presentations
                else "flattened_source_composite"
            )
        for row, presentation, map_id, _ in resolved_rows:
            definition = generated_definitions.get(map_id)
            if definition is None:
                continue
            definition["source_audit"]["presentation_state"] = (
                "runtime_ready_semantic"
                if presentation.relative_source.lower() in semantic_presentations
                else "runtime_ready_flattened"
            )
            if not arguments.materialize_only:
                write_object(DEFINITION_CONTENT_ROOT / (map_id + ".json"), definition)
        plan["semantic_presentations"] = len(semantic_presentations)
    if arguments.materialize_only:
        return plan
    write_runtime_index(RUNTIME_INDEX_PATH, plan, runtime_rows, unresolved_rows)
    merged_paths = dict(current_paths)
    for map_id in generated_definitions:
        merged_paths[map_id] = "res://assets/glory/map_definitions/%s.json" % map_id
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
    print("GLORY_MAP_CONTENT_BUILT", len(used_presentations), "presentations")
    return plan


def prepare_godot_import() -> None:
    glory = PROJECT_ROOT / "assets" / "glory"
    for name in ("sprites", "mine_palettes", "monster_palettes", "map_definitions"):
        directory = glory / name
        directory.mkdir(parents=True, exist_ok=True)
        (directory / ".gdignore").touch()
    (glory / ".gdignore").unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan-only", action="store_true")
    parser.add_argument("--index-only", action="store_true")
    parser.add_argument("--field-only", action="store_true")
    parser.add_argument("--semantic-only", action="store_true")
    parser.add_argument("--semantic-batch", type=int, default=0)
    parser.add_argument("--semantic-batches", type=int, default=1)
    parser.add_argument("--materialize-only", action="store_true")
    parser.add_argument("--cached-semantic-only", action="store_true")
    parser.add_argument("--prepare-import", action="store_true", help="Configure native map imports without rebuilding")
    arguments = parser.parse_args()
    if arguments.semantic_batches <= 0 or not 0 <= arguments.semantic_batch < arguments.semantic_batches:
        parser.error("semantic batch must be within semantic batch count")
    if arguments.prepare_import:
        prepare_godot_import()
        return 0
    build(arguments)
    if not arguments.plan_only:
        prepare_godot_import()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
