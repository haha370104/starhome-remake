#!/usr/bin/env python3
"""Audit generated Glory content and publish the runtime coverage boundary."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "data" / "content" / "glory_runtime_content_manifest_v1.json"


def load(relative: str) -> Any:
    return json.loads((ROOT / relative).read_text(encoding="utf-8-sig"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def main() -> int:
    maps = load("data/content/glory_map_runtime_index_v1.json")
    sprites = load("data/content/glory_sprite_runtime_index_v1.json")
    monster_palettes = load("data/content/glory_monster_palette_runtime_index_v1.json")
    mine_palettes = load("data/content/glory_mine_palette_runtime_index_v1.json")
    monsters = load("data/gameplay/glory/glory_monsters_v1.json")
    encounters = load("data/gameplay/glory/glory_monster_encounters_v1.json")
    items = load("data/gameplay/glory/glory_items_v1.json")
    recipes = load("data/gameplay/glory/glory_recipes_v1.json")
    mining = load("data/gameplay/mining_v1.json")
    known = load("data/content/known_content_registry_v1.json")

    require(maps["summary"]["source_rows"] == 814, "map source count drifted")
    require(maps["summary"]["resolved_runtime_rows"] == 810, "runtime map count drifted")
    require(len(monsters["definitions"]) == 119, "monster count drifted")
    require(len(items["definitions"]) == 1270, "generated item count drifted")
    require(sum(recipes["summary"].values()) == 346, "recipe count drifted")
    require(len(mining["minerals"]) == 35, "mineral count drifted")
    require(known["expected_counts"]["item"]["runtime_item_ids_covered"] == 1284, "runtime item coverage drifted")

    total_animations = (
        sprites["summary"]["sprites"]
        + monster_palettes["summary"]["sprites"]
        + mine_palettes["summary"]["sprites"]
    )
    manifest = {
        "schema_version": 1,
        "content_version": "glory-runtime-coverage-v1",
        "source_policy": {
            "default_release": "starhome_lz_ry",
            "exception": "Free-version assets are allowed only for the HUD.",
        },
        "operational_catalogs": {
            "maps": {
                "source_registrations": 814,
                "runtime_ready": 810,
                "unresolved": len(maps["unresolved_source_ids"]),
            },
            "animations": {
                "decoded_ale": sprites["summary"]["sprites"],
                "monster_act_variants": monster_palettes["summary"]["sprites"],
                "mineral_act_variants": mine_palettes["summary"]["sprites"],
                "runtime_total": total_animations,
            },
            "monsters": {
                "runtime_definitions": len(monsters["definitions"]),
                "maps_with_reliable_encounters": encounters["summary"]["client_evidence_maps"],
                "maps_with_remake_defaults": encounters["summary"]["remake_default_maps"],
                "curated_override_maps": encounters["summary"]["curated_override_maps"],
                "runtime_field_maps": encounters["summary"]["runtime_field_maps"],
            },
            "items": {
                "generated_definitions": len(items["definitions"]),
                "total_runtime_definitions": known["expected_counts"]["item"]["runtime_item_ids"],
                "decoded_asset_references": items["summary"]["decoded_asset_references"],
            },
            "recipes": {
                "registered_records": sum(recipes["summary"].values()),
                "groups": recipes["summary"],
                "execution_status": recipes["execution_status"],
            },
            "minerals": {
                "runtime_definitions": len(mining["minerals"]),
                "client_evidence_maps": mining["source_audit"]["maps_with_client_evidence"],
                "runtime_enabled_maps": mining["source_audit"]["runtime_enabled_maps"],
            },
        },
        "explicit_exceptions": [
            {
                "kind": "map_package_missing",
                "count": len(maps["unresolved_source_ids"]),
                "identifiers": maps["unresolved_source_ids"],
                "effect": "Registered as known but cannot be entered until a source package is recovered.",
            },
            {
                "kind": "item_asset_missing_from_glory_package",
                "count": items["summary"]["missing_asset_references"],
                "effect": "Business data is active; the affected presentation remains empty rather than borrowing another release.",
            },
            {
                "kind": "monster_distribution_remake_default",
                "count": encounters["summary"]["remake_default_maps"],
                "effect": "Fields without recovered placements use explicitly configurable basic-four populations; this is not a recovered original-server distribution.",
            },
            {
                "kind": "server_authority_not_recovered",
                "domains": ["monster_drop_settlement", "shop_inventory", "quest_progression", "recipe_success_settlement"],
                "effect": "Client evidence is queryable; server-authoritative values are not invented.",
            },
        ],
    }
    TARGET.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"GLORY_RUNTIME_CONTENT_AUDITED animations={total_animations} exceptions={len(manifest['explicit_exceptions'])}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
