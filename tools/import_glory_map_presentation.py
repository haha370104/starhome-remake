#!/usr/bin/env python3
"""Build business-named runtime presentation bundles from parsed Glory maps.

The importer never copies legacy ALE names into ``assets/``.  It composites
resolved first frames in FCC order, records the final visible owner of every
pixel, and groups those pixels by the placement's world-space anchor baseline.
The result is a compact semantic atlas that reconstructs the parsed composite
exactly while allowing Godot actors to sort in front of or behind scenery.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageChops


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
PARSED_MAP_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_maps_parsed" / "maps"
ALE_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
OFFICIAL_CACHE_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "official_lazy_cache"
UNINDEXED_ALE_ROOT = OFFICIAL_CACHE_ROOT / "ale_sprites"
UNINDEXED_RAW_ROOT = OFFICIAL_CACHE_ROOT / "raw"
CHUNK_SIZE = 256
ATLAS_WIDTH = 2048
ATLAS_PADDING = 1

MAPS: dict[str, dict[str, str]] = {
    "yian_harbor_city": {
        "source": "city1svr/variant_01_nft_bl",
        "destination": "assets/maps/yian_harbor/city",
        "asset_prefix": "maps/yian_harbor/city/scenery",
    },
    "d04_field_zone": {
        "source": "d04/variant_01_nft_bl",
        "destination": "assets/maps/exploration/d04_field_zone",
        "asset_prefix": "maps/exploration/d04_field_zone/scenery",
    },
}


def read_json(path: Path) -> dict[str, Any]:
    """Read one UTF-8 JSON object from *path*."""
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"JSON root must be an object: {path}")
    return value


def write_json(path: Path, value: dict[str, Any], *, compact: bool = False) -> None:
    """Write *value* as deterministic UTF-8 JSON, optionally on one line."""
    path.parent.mkdir(parents=True, exist_ok=True)
    indent = None if compact else 2
    separators = (",", ":") if compact else None
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=indent, separators=separators) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    """Return the SHA-256 digest of *path*."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def md5(path: Path) -> str:
    """Return the MD5 digest needed to compare an unindexed HTTP recovery probe."""
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize_source_reference(source_ale: str) -> str:
    """Normalize one FCC-relative ALE reference to a source-root relative stem."""
    normalized = source_ale.replace("\\", "/").strip()
    while normalized.startswith("../"):
        normalized = normalized[3:]
    if normalized.lower().endswith(".ale"):
        normalized = normalized[:-4]
    return normalized


def resolve_frame_source(item: dict[str, Any]) -> dict[str, Any] | None:
    """Resolve an indexed Glory frame or a verified same-release unindexed overlay."""
    direct_logical = normalize_source_reference(str(item.get("source_ale", "")))
    direct_dir = UNINDEXED_ALE_ROOT / Path(direct_logical)
    direct_raw = UNINDEXED_RAW_ROOT / Path(direct_logical + ".ale")
    if (direct_dir / "frames.json").is_file() and direct_raw.is_file():
        return {
            "logical_path": direct_logical,
            "source_dir": direct_dir,
            "raw_path": direct_raw,
            "resolution": "official_exact_path_lazy_recovery",
        }
    if item.get("status") != "ok":
        return None
    logical_path = str(item.get("resolved_ale", ""))
    if logical_path.startswith("@"):
        return None
    source_dir = ALE_ROOT / Path(logical_path)
    if not (source_dir / "frames.json").is_file():
        return None
    return {
        "logical_path": logical_path,
        "source_dir": source_dir,
        "raw_path": None,
        "resolution": "indexed_glory_manifest",
    }


def load_first_frame(
    source: dict[str, Any],
    cache: dict[str, tuple[Image.Image, dict[str, Any]]],
) -> tuple[Image.Image, dict[str, Any]]:
    """Load and cache the first decoded frame and its origin metadata."""
    cache_key = str(source["source_dir"])
    if cache_key in cache:
        return cache[cache_key]
    source_dir: Path = source["source_dir"]
    metadata = read_json(source_dir / "frames.json")
    frame = metadata["frames"][0]
    page_path = source_dir / metadata["pages"][frame["page"]]
    with Image.open(page_path) as page:
        image = page.convert("RGBA").crop(
            (
                int(frame["x"]),
                int(frame["y"]),
                int(frame["x"] + frame["width"]),
                int(frame["y"] + frame["height"]),
            )
        )
    result = (image, frame)
    cache[cache_key] = result
    return result


def paste_owner(
    owner: np.ndarray,
    local_alpha: np.ndarray,
    top_left: tuple[int, int],
    owner_id: int,
) -> None:
    """Assign *owner_id* to non-transparent source pixels clipped to the canvas."""
    destination_height, destination_width = owner.shape
    source_height, source_width = local_alpha.shape
    x, y = top_left
    sx0, sy0 = max(0, -x), max(0, -y)
    sx1 = min(source_width, destination_width - x)
    sy1 = min(source_height, destination_height - y)
    if sx0 >= sx1 or sy0 >= sy1:
        return
    clipped = local_alpha[sy0:sy1, sx0:sx1] > 0
    target = owner[y + sy0 : y + sy1, x + sx0 : x + sx1]
    target[clipped] = owner_id


def build_scene_ownership(
    background: Image.Image,
    scene: dict[str, Any],
    asset_prefix: str,
) -> tuple[
    Image.Image,
    np.ndarray,
    list[dict[str, Any]],
    list[dict[str, Any]],
    int,
]:
    """Composite resolved placements and return final color/owner/audit values."""
    canvas_size = background.size
    scene_color = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    owner = np.full((canvas_size[1], canvas_size[0]), -1, dtype=np.int32)
    owners: list[dict[str, Any]] = []
    missing: list[dict[str, Any]] = []
    frame_cache: dict[str, tuple[Image.Image, dict[str, Any]]] = {}
    recovered_placements = 0

    for source_index, item in enumerate(scene.get("objects", [])):
        source = resolve_frame_source(item)
        if source is None:
            rejected_resolution = str(item.get("resolved_ale", ""))
            reason = item.get("resolution", "missing")
            if rejected_resolution.startswith("@"):
                reason = "excluded_non_glory_fallback"
            missing.append(
                {
                    "source_index": source_index,
                    "source_resource": item.get("source_ale", ""),
                    "anchor": item.get("anchor", [0, 0]),
                    "reason": reason,
                    "rejected_resolution": rejected_resolution,
                }
            )
            continue
        logical_path = str(source["logical_path"])
        source_image, frame = load_first_frame(source, frame_cache)
        anchor = item.get("anchor", [0, 0])
        if "top_left" in item:
            top_left = (int(item["top_left"][0]), int(item["top_left"][1]))
        else:
            top_left = (
                int(anchor[0]) + int(frame.get("origin_x", 0)),
                int(anchor[1]) + int(frame.get("origin_y", 0)),
            )
        if source["resolution"] == "official_exact_path_lazy_recovery":
            recovered_placements += 1
        scene_color.alpha_composite(source_image, top_left)
        owner_id = len(owners)
        paste_owner(
            owner,
            np.asarray(source_image.getchannel("A"), dtype=np.uint8),
            top_left,
            owner_id,
        )
        source_audit = {
            "source_release": "starhome_lz_ry",
            "source_logical_asset": logical_path + ".ale",
            "source_resolution": source["resolution"],
            "placement_kind": item.get("kind", "AddImg"),
            "anchor": anchor,
        }
        raw_path = source.get("raw_path")
        if isinstance(raw_path, Path):
            source_audit.update(
                {
                    "download_md5": md5(raw_path),
                    "download_sha256": sha256(raw_path),
                    "download_bytes": raw_path.stat().st_size,
                }
            )
        owners.append(
            {
                "owner_id": owner_id,
                "source_index": source_index,
                "asset_id": f"{asset_prefix}/placement_{source_index + 1:04d}",
                "sort_baseline": int(item["anchor"][1]),
                "source_audit": source_audit,
            }
        )

    scene_pixels = np.asarray(scene_color, dtype=np.uint8)
    owner[scene_pixels[:, :, 3] == 0] = -1
    return scene_color, owner, owners, missing, recovered_placements


def build_chunks(
    scene_color: Image.Image,
    owner: np.ndarray,
    owners: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Split final visible pixels into small baseline-owned atlas chunks."""
    scene_pixels = np.asarray(scene_color, dtype=np.uint8)
    owner_lookup = {int(item["owner_id"]): item for item in owners}
    height, width = owner.shape
    chunks: list[dict[str, Any]] = []
    for tile_y in range(0, height, CHUNK_SIZE):
        for tile_x in range(0, width, CHUNK_SIZE):
            tile_owner = owner[
                tile_y : min(tile_y + CHUNK_SIZE, height),
                tile_x : min(tile_x + CHUNK_SIZE, width),
            ]
            visible_ids = [int(value) for value in np.unique(tile_owner) if int(value) >= 0]
            if not visible_ids:
                continue
            ids_by_baseline: dict[int, list[int]] = defaultdict(list)
            for owner_id in visible_ids:
                ids_by_baseline[int(owner_lookup[owner_id]["sort_baseline"])].append(owner_id)
            for baseline, baseline_owner_ids in ids_by_baseline.items():
                local_mask = np.isin(tile_owner, np.asarray(baseline_owner_ids, dtype=np.int32))
                local_y, local_x = np.nonzero(local_mask)
                x0, x1 = int(local_x.min()), int(local_x.max()) + 1
                y0, y1 = int(local_y.min()), int(local_y.max()) + 1
                crop_mask = local_mask[y0:y1, x0:x1]
                world_x, world_y = tile_x + x0, tile_y + y0
                pixels = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.uint8)
                source_crop = scene_pixels[world_y : world_y + pixels.shape[0], world_x : world_x + pixels.shape[1]]
                pixels[crop_mask] = source_crop[crop_mask]
                chunks.append(
                    {
                        "pixels": pixels,
                        "pixel_offset": [world_x, world_y],
                        "size": [pixels.shape[1], pixels.shape[0]],
                        "sort_baseline": baseline,
                        "owner_ids": baseline_owner_ids,
                    }
                )
    return chunks


def pack_chunks(chunks: list[dict[str, Any]]) -> tuple[Image.Image, list[dict[str, Any]]]:
    """Shelf-pack semantic chunks into one atlas and attach atlas regions."""
    ordered = sorted(
        chunks,
        key=lambda item: (
            -item["pixels"].shape[0],
            -item["pixels"].shape[1],
            item["sort_baseline"],
            item["pixel_offset"][1],
            item["pixel_offset"][0],
        ),
    )
    x = y = shelf_height = 0
    for item in ordered:
        height, width = item["pixels"].shape[:2]
        if width > ATLAS_WIDTH:
            raise ValueError(f"Chunk width {width} exceeds atlas width")
        if x and x + width > ATLAS_WIDTH:
            x = 0
            y += shelf_height + ATLAS_PADDING
            shelf_height = 0
        item["atlas_region"] = [x, y, width, height]
        x += width + ATLAS_PADDING
        shelf_height = max(shelf_height, height)
    atlas_height = y + shelf_height
    atlas_pixels = np.zeros((atlas_height, ATLAS_WIDTH, 4), dtype=np.uint8)
    for item in ordered:
        atlas_x, atlas_y, width, height = item["atlas_region"]
        atlas_pixels[atlas_y : atlas_y + height, atlas_x : atlas_x + width] = item["pixels"]
    return Image.fromarray(atlas_pixels, mode="RGBA"), ordered


def validate_reconstruction(
    background: Image.Image,
    source_composite: Image.Image,
    scene_color: Image.Image,
    chunks: list[dict[str, Any]],
    require_source_match: bool,
) -> tuple[str, bool]:
    """Prove chunk union equality and report whether the parsed composite also matches."""
    reconstructed_scene = Image.new("RGBA", background.size, (0, 0, 0, 0))
    for item in chunks:
        reconstructed_scene.alpha_composite(
            Image.fromarray(item["pixels"], mode="RGBA"),
            tuple(item["pixel_offset"]),
        )
    if ImageChops.difference(reconstructed_scene, scene_color).getbbox() is not None:
        raise RuntimeError("Semantic chunk union differs from composed scene pixels")
    reconstructed = background.copy()
    reconstructed.alpha_composite(reconstructed_scene)
    source_matches = ImageChops.difference(reconstructed, source_composite).getbbox() is None
    if require_source_match and not source_matches:
        raise RuntimeError("Resolved semantic presentation differs from parsed source composite")
    return hashlib.sha256(reconstructed.tobytes()).hexdigest(), source_matches


def import_map(map_id: str, config: dict[str, str]) -> dict[str, Any]:
    """Import one configured map and return a concise result summary."""
    source = PARSED_MAP_ROOT / config["source"]
    destination = PROJECT_ROOT / config["destination"]
    if not source.is_dir():
        raise FileNotFoundError(source)
    destination.mkdir(parents=True, exist_ok=True)
    scene = read_json(source / "scene_objects.json")
    with Image.open(source / "background.png") as image:
        background = image.convert("RGBA")
    with Image.open(source / "composite.png") as image:
        source_composite = image.convert("RGBA")
    scene_color, owner, owners, missing, recovered_placements = build_scene_ownership(
        background, scene, config["asset_prefix"]
    )
    chunks = build_chunks(scene_color, owner, owners)
    atlas, packed_chunks = pack_chunks(chunks)
    excluded_non_glory = sum(
        item.get("reason") == "excluded_non_glory_fallback" for item in missing
    )
    composite_sha, source_composite_matches = validate_reconstruction(
        background,
        source_composite,
        scene_color,
        chunks,
        require_source_match=excluded_non_glory == 0,
    )

    floor_path = destination / "floor.png"
    minimap_path = destination / "minimap.jpg"
    navigation_path = destination / "navigation_grid.bin"
    atlas_path = destination / "semantic_layer_atlas.png"
    background.save(floor_path, compress_level=3)
    shutil.copy2(source / "minimap.jpg", minimap_path)
    shutil.copy2(source / "navigation_grid.bin", navigation_path)
    atlas.save(atlas_path, compress_level=3)

    owner_lookup = {int(item["owner_id"]): item for item in owners}
    recovered_assets_by_path: dict[str, dict[str, Any]] = {}
    for owner_entry in owners:
        audit = owner_entry["source_audit"]
        if audit.get("source_resolution") != "official_exact_path_lazy_recovery":
            continue
        logical_asset = str(audit["source_logical_asset"])
        if logical_asset not in recovered_assets_by_path:
            recovered_assets_by_path[logical_asset] = {
                "source_logical_asset": logical_asset,
                "source_release": "starhome_lz_ry",
                "resolution": "official_exact_path_lazy_recovery",
                "download_md5": audit["download_md5"],
                "download_sha256": audit["download_sha256"],
                "download_bytes": audit["download_bytes"],
                "placement_count": 0,
            }
        recovered_assets_by_path[logical_asset]["placement_count"] += 1
    layers: list[dict[str, Any]] = []
    atlas_resource = "res://" + str(atlas_path.relative_to(PROJECT_ROOT)).replace("\\", "/")
    for layer_index, item in enumerate(
        sorted(
            packed_chunks,
            key=lambda value: (
                value["sort_baseline"],
                value["pixel_offset"][1],
                value["pixel_offset"][0],
            ),
        )
    ):
        layers.append(
            {
                "layer_id": f"semantic_scene_{layer_index:04d}",
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
            }
        )

    manifest = {
        "schema_version": 1,
        "map_id": map_id,
        "source_release": "starhome_lz_ry",
        "composition": {
            "render_strategy": "semantic_owner_layers",
            "semantic_atlas": atlas_resource,
            "semantic_atlas_size": list(atlas.size),
            "semantic_layers": layers,
            "props": [],
            "missing_dependencies": missing,
            "validation": {
                "source_composite_pixel_sha256": composite_sha,
                "semantic_reconstruction_exact": True,
                "parsed_composite_matches_glory_only": source_composite_matches,
                "excluded_non_glory_fallbacks": excluded_non_glory,
                "recovered_same_release_unindexed_placements": recovered_placements,
            },
        },
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_map_code": source.parent.name,
            "source_output": str(source.relative_to(OUTPUTS_ROOT)).replace("\\", "/"),
            "source_scene_objects_sha256": sha256(source / "scene_objects.json"),
            "resolved_placements": len(owners),
            "missing_placements": len(missing),
            "recovered_same_release_unindexed_placements": recovered_placements,
            "recovered_same_release_unindexed_assets": sorted(
                recovered_assets_by_path.values(),
                key=lambda value: value["source_logical_asset"].lower(),
            ),
            "runtime_asset_naming": "business_map_path_plus_placement_sequence",
        },
    }
    write_json(destination / "map_manifest.json", manifest, compact=True)
    return {
        "map_id": map_id,
        "resolved": len(owners),
        "missing": len(missing),
        "recovered_same_release_unindexed": recovered_placements,
        "semantic_layers": len(layers),
        "atlas_size": list(atlas.size),
        "composite_sha256": composite_sha,
    }


def main() -> int:
    """Parse command line selections and import the requested map presentations."""
    parser = argparse.ArgumentParser()
    parser.add_argument("--map", action="append", choices=sorted(MAPS), dest="maps")
    arguments = parser.parse_args()
    selected = arguments.maps or list(MAPS)
    results = [import_map(map_id, MAPS[map_id]) for map_id in selected]
    print(json.dumps(results, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
