#!/usr/bin/env python3
"""Audit imported Stage-2 map presentation bundles without source archives."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "yian_harbor_city": {
        "directory": PROJECT_ROOT / "assets/maps/yian_harbor/city",
        "minimum_layers": 700,
        "excluded_non_glory_fallbacks": 0,
        "recovered_same_release_unindexed_placements": 31,
        "recovered_same_release_unindexed_assets": 19,
        "missing_placements": 0,
        "excluded_static_transition_placements": 22,
    },
    "d04_field_zone": {
        "directory": PROJECT_ROOT / "assets/maps/exploration/d04_field_zone",
        "minimum_layers": 50,
        "excluded_non_glory_fallbacks": 0,
        "recovered_same_release_unindexed_placements": 10,
        "recovered_same_release_unindexed_assets": 6,
        "missing_placements": 0,
        "excluded_static_transition_placements": 16,
    },
}


def main() -> int:
    """Validate manifest identity, business paths, atlas bounds and provenance."""
    errors: list[str] = []
    summaries: list[str] = []
    for map_id, expected in EXPECTED.items():
        directory: Path = expected["directory"]
        manifest_path = directory / "map_manifest.json"
        for required in ("floor.png", "minimap.jpg", "navigation_grid.bin", "semantic_layer_atlas.png", "map_manifest.json"):
            if not (directory / required).is_file():
                errors.append(f"{map_id}: missing {required}")
        if not manifest_path.is_file():
            continue
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        composition = manifest.get("composition", {})
        validation = composition.get("validation", {})
        layers = composition.get("semantic_layers", [])
        if manifest.get("map_id") != map_id:
            errors.append(f"{map_id}: manifest identity mismatch")
        if manifest.get("source_release") != "starhome_lz_ry":
            errors.append(f"{map_id}: non-Glory source release")
        if composition.get("render_strategy") != "semantic_owner_layers":
            errors.append(f"{map_id}: semantic owner rendering is not enabled")
        if not validation.get("semantic_reconstruction_exact"):
            errors.append(f"{map_id}: importer did not prove exact semantic reconstruction")
        if validation.get("runtime_transition_registry_only") is not True:
            errors.append(f"{map_id}: transition rendering is not registry-owned")
        if (
            validation.get("excluded_static_transition_placements", 0)
            != expected["excluded_static_transition_placements"]
        ):
            errors.append(f"{map_id}: unexpected static transition exclusion count")
        if validation.get("excluded_non_glory_fallbacks") != expected["excluded_non_glory_fallbacks"]:
            errors.append(f"{map_id}: unexpected cross-version fallback count")
        if (
            validation.get("recovered_same_release_unindexed_placements", 0)
            != expected["recovered_same_release_unindexed_placements"]
        ):
            errors.append(f"{map_id}: unexpected same-release recovery count")
        if len(composition.get("missing_dependencies", [])) != expected["missing_placements"]:
            errors.append(f"{map_id}: unexpected missing placement count")
        recovered_assets = manifest.get("source_audit", {}).get(
            "recovered_same_release_unindexed_assets", []
        )
        if len(recovered_assets) != expected["recovered_same_release_unindexed_assets"]:
            errors.append(f"{map_id}: unexpected recovered asset count")
        for recovered in recovered_assets:
            if (
                recovered.get("source_release") != "starhome_lz_ry"
                or recovered.get("resolution") != "official_exact_path_lazy_recovery"
                or len(str(recovered.get("download_md5", ""))) != 32
                or len(str(recovered.get("download_sha256", ""))) != 64
                or int(recovered.get("download_bytes", 0)) <= 0
                or int(recovered.get("placement_count", 0)) <= 0
            ):
                errors.append(f"{map_id}: invalid recovered asset evidence")
                break
        if len(layers) < expected["minimum_layers"]:
            errors.append(f"{map_id}: semantic layer count is unexpectedly low")
        with Image.open(directory / "semantic_layer_atlas.png") as atlas:
            atlas_width, atlas_height = atlas.size
        for layer in layers:
            texture = str(layer.get("texture", ""))
            if not texture.startswith("res://assets/maps/") or any(
                legacy in texture.lower() for legacy in ("/pic/", "/pic2/", ".ale")
            ):
                errors.append(f"{map_id}: non-business runtime texture path {texture}")
                break
            x, y, width, height = layer.get("atlas_region", [0, 0, 0, 0])
            if x < 0 or y < 0 or width <= 0 or height <= 0 or x + width > atlas_width or y + height > atlas_height:
                errors.append(f"{map_id}: atlas region out of bounds")
                break
        summaries.append(f"{map_id}={len(layers)} layers/{atlas_width}x{atlas_height}")

    if errors:
        for error in errors:
            print(error)
        return 1
    print("Stage-2 map presentation audit passed: " + ", ".join(summaries))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
