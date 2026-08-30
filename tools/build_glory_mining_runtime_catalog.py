#!/usr/bin/env python3
"""Build all Glory minerals, map pools and ACT-rendered mining sprites."""

from __future__ import annotations

import csv
import hashlib
import io
import json
import re
import zipfile
from pathlib import Path
from typing import Any

from PIL import Image

import audit_monster_asset_sources as indexed_decoder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
SOURCE_CSV = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "catalogs" / "mines" / "glory_ore_catalog.csv"
PARSED_SPRITES = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
RAW_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
MINING_TARGET = PROJECT_ROOT / "data" / "gameplay" / "mining_v1.json"
MANIFEST_TARGET = PROJECT_ROOT / "assets" / "minerals" / "mining_asset_manifest.json"
PACK_TARGET = PROJECT_ROOT / "assets" / "content_packs" / "glory_mine_palettes_v1.zip"
PACK_CATALOG_TARGET = PROJECT_ROOT / "data" / "content" / "glory_mine_palette_content_pack_v1.json"
INDEX_TARGET = PROJECT_ROOT / "data" / "content" / "glory_mine_palette_runtime_index_v1.json"
CONTENT_VERSION = "starhome-remake-mining-v2"
CURATED_IDS = {"铁矿": "iron_ore", "硅矿": "silicon_ore", "石墨矿": "graphite_ore"}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value: Any, pretty: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    separators = None if pretty else (",", ":")
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2 if pretty else None, separators=separators) + "\n", encoding="utf-8")


def digest(value: str, size: int = 12) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:size]


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def number(value: str, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def read_rows() -> list[dict[str, str]]:
    with SOURCE_CSV.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.reader(source))
    if len(rows) != 36 or len(rows[0]) < 20:
        raise RuntimeError("unexpected Glory ore CSV shape")
    keys = [
        "display_name", "item_class", "source_class", "required_level", "tooltip", "description",
        "point_count", "worlds", "maps", "source_status", "level_evidence", "location_evidence",
        "item_asset", "source_asset", "palette", "worth", "sell", "item_source",
        "source_definition", "text_sources",
    ]
    return [dict(zip(keys, row, strict=False)) for row in rows[1:]]


def runtime_id(row: dict[str, str]) -> str:
    return CURATED_IDS.get(row["display_name"], "glory_mineral_" + digest(row["source_class"] or row["display_name"]))


def variant_key(row: dict[str, str]) -> str:
    return digest(row["display_name"] + "|" + row["source_class"])


def source_indexes() -> tuple[dict[str, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    rows = read_json(PROJECT_ROOT / "data" / "content" / "glory_sprite_runtime_index_v1.json")["sprites"]
    by_id = {row["logical_id"]: row for row in rows}
    by_name: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        by_name.setdefault(Path(row["logical_id"]).name.lower(), []).append(row)
    return by_id, by_name


def normalize_reference(reference: str) -> str:
    value = reference.strip().replace("\\", "/").lower()
    while value.startswith("../"):
        value = value[3:]
    return value[:-4] if value.endswith(".ale") else value


def resolve_source(reference: str, by_id: dict[str, dict[str, Any]], by_name: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    normalized = normalize_reference(reference)
    if normalized in by_id:
        return by_id[normalized]
    candidates = by_name.get(Path(normalized).name.lower(), [])
    preferred = [row for row in candidates if row["logical_id"].startswith("pic3/mine/")]
    if preferred:
        return sorted(preferred, key=lambda row: row["logical_id"])[0]
    if len(candidates) == 1:
        return candidates[0]
    raise RuntimeError(f"cannot resolve mining ALE: {reference}")


def act_index() -> dict[str, Path]:
    result: dict[str, Path] = {}
    for path in sorted(RAW_ROOT.rglob("*.act")):
        result.setdefault(path.name.lower(), path)
    return result


def render_variant(source_row: dict[str, Any], palette: Path, decoder: Any) -> tuple[bytes, bytes]:
    logical_id = source_row["logical_id"]
    ale = decoder.AleFile(RAW_ROOT / (logical_id + ".ale"))
    if ale.version != 1:
        raise RuntimeError(f"mining ACT requires indexed ALE: {logical_id}")
    metadata = read_json(PARSED_SPRITES / logical_id / "frames.json")
    with Image.open(PARSED_SPRITES / logical_id / metadata["pages"][0]) as source_page:
        atlas = Image.new("RGBA", source_page.size)
    palette_bytes = palette.read_bytes()
    if len(palette_bytes) < 256 * 3:
        raise RuntimeError(f"truncated mining ACT: {palette}")
    colors = [(*palette_bytes[offset:offset + 3], 255) for offset in range(0, 256 * 3, 3)]
    for frame, frame_row in zip(ale.frames, metadata["frames"], strict=True):
        if not frame.width or not frame.height:
            continue
        indexed = indexed_decoder.decode_index_alpha(ale, frame)
        rendered = indexed_decoder.apply_palette(indexed, colors)
        atlas.alpha_composite(rendered, (int(frame_row["x"]), int(frame_row["y"])))
        indexed.close()
        rendered.close()
    buffer = io.BytesIO()
    atlas.save(buffer, format="PNG", optimize=True)
    atlas.close()
    clean = dict(metadata)
    clean["source"] = f"starhome_lz_ry/raw/{logical_id}.ale"
    clean["source_release"] = "starhome_lz_ry"
    clean["external_palette"] = palette.relative_to(RAW_ROOT).as_posix()
    clean["pages"] = ["sheet.png"]
    return (json.dumps(clean, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8"), buffer.getvalue()


def fixed_info(path: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    return info


def runtime_row(logical_id: str, source_row: dict[str, Any], metadata: dict[str, Any]) -> dict[str, Any]:
    return {
        "logical_id": logical_id,
        "frames_path": f"res://content/glory/{logical_id}/frames.json",
        "page_paths": [f"res://content/glory/{logical_id}/sheet.png"],
        "frame_count": int(metadata["frame_count"]),
        "cell_size": [int(metadata["cell_width"]), int(metadata["cell_height"])],
        "classification": ["mine_palettes"],
        "source_release": "starhome_lz_ry",
        "source_ale": source_row["logical_id"],
    }


def main() -> int:
    rows = read_rows()
    existing = read_json(MINING_TARGET)
    items = read_json(PROJECT_ROOT / "data" / "gameplay" / "glory" / "glory_items_v1.json")["definitions"]
    item_by_name = {item["display_name"]: item["id"] for item in items}
    map_rows = read_json(PROJECT_ROOT / "data" / "content" / "glory_map_runtime_index_v1.json")["runtime_maps"]
    runtime_by_source = {row["source_id"]: row["runtime_id"] for row in map_rows}
    by_id, by_name = source_indexes()
    palettes = act_index()
    decoder = indexed_decoder.load_decoder()
    definitions: list[dict[str, Any]] = []
    manifest_definitions: dict[str, Any] = {}
    map_pools: dict[str, dict[str, Any]] = {}
    variant_rows: list[dict[str, Any]] = []
    PACK_TARGET.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(PACK_TARGET, "w", allowZip64=True) as archive:
        for row in rows:
            mineral_id = runtime_id(row)
            collectible = bool(row["item_class"])
            item_id = CURATED_IDS.get(row["display_name"], item_by_name.get(row["display_name"], ""))
            presentation: dict[str, str] = {}
            for role, reference in (("inventory", row["item_asset"]), ("world", row["source_asset"])):
                if not reference:
                    continue
                source_row = resolve_source(reference, by_id, by_name)
                if row["palette"]:
                    palette = palettes.get(Path(row["palette"]).name.lower())
                    if palette is None:
                        raise RuntimeError(f"missing mining palette: {row['palette']}")
                    logical_id = f"mine_palettes/{variant_key(row)}/{role}"
                    frames, page = render_variant(source_row, palette, decoder)
                    root = f"content/glory/{logical_id}"
                    archive.writestr(fixed_info(root + "/frames.json"), frames)
                    archive.writestr(fixed_info(root + "/sheet.png"), page)
                    metadata = read_json(PARSED_SPRITES / source_row["logical_id"] / "frames.json")
                    variant_rows.append(runtime_row(logical_id, source_row, metadata))
                    presentation[role + "_animation"] = logical_id
                else:
                    presentation[role + "_animation"] = source_row["logical_id"]
            definitions.append({
                "id": mineral_id,
                "display_name": row["display_name"],
                "item_definition_id": item_id,
                "world_presentation_id": mineral_id,
                "collectible": collectible,
                "required_mining_level": number(row["required_level"]),
                "experience_coefficient": max(1.0, number(row["required_level"], 10) / 10.0),
                "tooltip": row["tooltip"],
                "description": row["description"],
                "worth": number(row["worth"]) if row["worth"] else None,
                "sell_price": number(row["sell"]) if row["sell"] else None,
                "presentation": presentation,
                "source_class": row["source_class"],
                "evidence": {
                    "level": row["level_evidence"],
                    "locations": row["location_evidence"],
                    "definition": row["source_definition"],
                },
            })
            manifest_definitions[mineral_id] = dict(presentation)
            for source_key in re.split(r"[、；;,\s]+", row["maps"].strip()):
                if not source_key:
                    continue
                runtime_map = runtime_by_source.get("map:" + source_key.lower())
                if not runtime_map:
                    continue
                policy = map_pools.setdefault(runtime_map, {
                    "enabled": True,
                    "mineral_pool": [],
                    "evidence": "Glory client map placement relation; remake uses random walkable spawns, not source coordinates.",
                })
                policy["mineral_pool"].append({"mineral_id": mineral_id, "weight": 1.0})
    client_evidence_map_count = len(map_pools)
    map_pools.setdefault("d04_field_zone", {
        "enabled": True,
        "mineral_pool": [{"mineral_id": "iron_ore", "weight": 1.0}],
        "evidence": "User-confirmed beginner-map remake fallback; the retired server spawn table was not recovered.",
    })
    write_json(MINING_TARGET, {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "defaults": existing["defaults"],
        "minerals": definitions,
        "maps": dict(sorted(map_pools.items())),
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "catalog": "starhome_lz_ry_full_parsed/catalogs/mines/glory_ore_catalog.csv",
            "definitions": len(definitions),
            "maps_with_client_evidence": client_evidence_map_count,
            "runtime_enabled_maps": len(map_pools),
            "runtime_authority": "remake server",
        },
    }, pretty=True)
    write_json(MANIFEST_TARGET, {
        "schema_version": 2,
        "source_release": "starhome_lz_ry",
        "definitions": manifest_definitions,
    }, pretty=True)
    write_json(INDEX_TARGET, {
        "schema_version": 1,
        "content_version": "glory-mine-palettes-v1",
        "summary": {"sprites": len(variant_rows)},
        "sprites": variant_rows,
    })
    write_json(PACK_CATALOG_TARGET, {
        "schema_version": 1,
        "content_version": "glory-mine-palettes-v1",
        "packs": [{
            "pack_id": PACK_TARGET.stem,
            "path": "res://assets/content_packs/" + PACK_TARGET.name,
            "size_bytes": PACK_TARGET.stat().st_size,
            "sha256": file_sha256(PACK_TARGET),
            "content_groups": ["mineral_palette_variants"],
        }],
        "summary": {"sprites": len(variant_rows)},
    }, pretty=True)
    print(f"GLORY_MINING_CATALOG_BUILT {len(definitions)} minerals, {len(map_pools)} maps, {len(variant_rows)} palette sprites")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
