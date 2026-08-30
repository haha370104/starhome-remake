#!/usr/bin/env python3
"""Build executable monster definitions from the decoded Glory client tables.

The retired server's spawn table and several combat constants are unavailable.
This generator therefore keeps client evidence separate from configurable remake
defaults and only emits map relations that can be joined without guessing.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import defaultdict
from pathlib import Path
from typing import Any


CURATED_IDS = {1: "toxic_gel", 2: "photosensitive_orb", 3: "om_larva", 4: "om_adult"}
CLASS_PALETTES = {
    "Npc成虫1": "NpcChengChong1.act",
    "Npc成虫2": "NpcChengChong2.act",
    "Npc幼虫1": "NpcYouChong1.act",
}
POPULATION_POLICY = {
    "maximum_population": 100,
    "replenish_interval_seconds": 60,
    "critical_threshold_ratio": 0.5,
    "low_threshold_ratio": 0.8,
    "critical_replenish_ratio": 0.2,
    "low_replenish_ratio": 0.1,
    "normal_replenish_ratio": 0.05,
    "spawn_distribution": "full_walkable_map",
    "minimum_spawn_separation": 96,
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def number(value: str, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def split_assets(value: str) -> list[str]:
    return [item.strip() for item in value.split("*") if item.strip()]


def runtime_id(index: int) -> str:
    return CURATED_IDS.get(index, f"glory_monster_{index:03d}")


def actor_id(index: int) -> str:
    curated = {
        1: "toxic_gel_standard",
        2: "photosensitive_orb_standard",
        3: "om_larva_standard",
        4: "om_adult_standard",
    }
    return curated.get(index, f"glory_npc_{index:03d}")


def archetype(row: dict[str, str]) -> str:
    name = row["npc_name"]
    if "感光质" in name:
        return "contact_melee"
    if row.get("attr_23", "").lower() == "rotbullet" or "毒胶" in name:
        return "corrosive_projectile"
    return "ranged_projectile"


def combat_definition(row: dict[str, str]) -> dict[str, Any]:
    attack_type = archetype(row)
    engagement = {0: "unresponsive", 1: "retaliatory", 2: "aggressive"}.get(
        number(row.get("attr_10", "")), "retaliatory"
    )
    contact = attack_type == "contact_melee"
    corrosive = attack_type == "corrosive_projectile"
    return {
        "attack_archetype": attack_type,
        "behavior_profile": "contact_chase" if contact else "ranged_chase",
        "engagement_policy": engagement,
        "runtime_move_speed": 78 if contact else (48 if corrosive else 72),
        "attack_range": 38 if contact else (190 if corrosive else 230),
        "wander_radius": 110 if contact else (88 if corrosive else 120),
        "wander_interval_seconds": 5,
        "aggro_radius": 300 if contact else 400,
        "leash_distance": 600,
        "attack_interval_seconds": 1.5,
        "runtime_projectile_speed": None if contact else (1000 if corrosive else 416.666667),
        "respawn_seconds": 30,
        "projectile_hitbox": {"offset": [0, -30 if contact else -24], "radius": 28},
    }


def presentation(row: dict[str, str], index: int) -> dict[str, Any]:
    body = split_assets(row.get("attr_30", ""))
    shadows = split_assets(row.get("attr_31", ""))
    # The decoded npcinfo layout is move, stand, action for both body and shadow.
    actions = {name: body[i] if i < len(body) else "" for i, name in enumerate(("move", "idle", "attack"))}
    shadow_actions = {
        name: shadows[i] if i < len(shadows) else "" for i, name in enumerate(("move", "idle", "attack"))
    }
    palette = row.get("attr_32", "").strip()
    source_actions = dict(actions)
    if palette:
        actor = actor_id(index)
        actions = {action: f"monster_palettes/{actor}/{action}" for action in actions}
    return {
        "mode": "ale_repository",
        "preferred_prefix": "pic3/npc",
        "actions": actions,
        "source_actions": source_actions,
        "shadow_actions": shadow_actions,
        "hit_effect": row.get("attr_24", "").strip(),
        "projectile": row.get("attr_26", "").strip(),
        "death_effect": row.get("attr_27", "").strip(),
        "death_sound": row.get("attr_28", "").strip(),
        "attack_sound": row.get("attr_29", "").strip(),
        "palette": palette,
        "directions": 8,
        "fps": 10,
    }


def source_drop_candidates(row: dict[str, str]) -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for entry in row.get("produce_obj", "").split("#"):
        fields = entry.split("*")
        if len(fields) < 4 or not fields[0]:
            continue
        result.append(
            {
                "display_name": fields[0],
                "minimum_quantity": number(fields[1]),
                "maximum_quantity": number(fields[2]),
                "raw_weight": number(fields[3]),
            }
        )
    return result


def build_definitions(rows: list[dict[str, str]], source_path: Path) -> list[dict[str, Any]]:
    definitions: list[dict[str, Any]] = []
    for row in rows:
        index = number(row["index"])
        definitions.append(
            {
                "id": runtime_id(index),
                "kind": "monster",
                "display_name": row["npc_name"],
                "combat_actor_id": actor_id(index),
                "stats": {
                    "max_health": max(1, number(row.get("attr_00", ""), 1)),
                    "base_attack": max(0, number(row.get("attr_01", ""))),
                    "defense": None,
                    "move_speed": None,
                },
                "combat": combat_definition(row),
                "drops": None,
                "rewards": None,
                "presentation": presentation(row, index),
                "source_drop_candidates": source_drop_candidates(row),
                "evidence": {
                    "stats": "client_confirmed_fields_attr_00_attr_01",
                    "engagement_policy": "client_inferred_attr_10",
                    "presentation": "client_confirmed_npcinfo_references",
                    "combat_tuning": "reconstructed_default",
                    "drops": "client_candidates_only_not_authoritative",
                },
                "source_audit": {
                    "source_release": "starhome_lz_ry",
                    "catalog": str(source_path).replace("\\", "/"),
                    "index": index,
                    "raw_attributes": row.get("attr_raw", ""),
                    "raw_skills": row.get("skill", ""),
                },
            }
        )
    return sorted(definitions, key=lambda item: int(item["source_audit"]["index"]))


def map_join_keys(row: dict[str, str]) -> set[str]:
    keys = {row["npc_name"], Path(row.get("attr_32", "")).name.lower()}
    return {key for key in keys if key}


def build_encounters(
    rows: list[dict[str, str]], relations: dict[str, Any], map_index: dict[str, Any]
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    source_to_runtime = {row["source_id"]: row["runtime_id"] for row in map_index["runtime_maps"]}
    row_by_key: dict[str, dict[str, str]] = {}
    for row in rows:
        for key in map_join_keys(row):
            row_by_key.setdefault(key, row)
    for class_name, palette in CLASS_PALETTES.items():
        candidate = next((row for row in rows if row.get("attr_32", "").lower() == palette.lower()), None)
        if candidate is not None:
            row_by_key[class_name] = candidate
    groups_by_map: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
    joins: list[dict[str, Any]] = []
    for relation in relations["relations"]:
        keys = [relation["monster_class"], *relation.get("display_names", [])]
        source_row = next((row_by_key[key] for key in keys if key in row_by_key), None)
        if source_row is None:
            continue
        species_id = runtime_id(number(source_row["index"]))
        joined_maps: list[str] = []
        for map_row in relation["maps"]:
            source_id = f"map:{map_row['world_code'].lower()}/{map_row['map_code'].lower()}"
            mapped = source_to_runtime.get(source_id)
            if not mapped:
                continue
            groups_by_map[mapped][species_id] = {
                "group_id": f"{mapped}.{species_id}", "monster_id": species_id, "weight": 1.0
            }
            joined_maps.append(mapped)
        joins.append(
            {
                "monster_class": relation["monster_class"],
                "species_id": species_id,
                "npc_index": number(source_row["index"]),
                "maps": sorted(set(joined_maps)),
                "evidence": "exact_display_name_or_palette_class_join",
            }
        )
    encounters = [
        {
            "encounter_id": f"glory_{map_id}_population",
            "map_id": map_id,
            "enabled": True,
            "population_policy": POPULATION_POLICY,
            "spawn_groups": sorted(groups.values(), key=lambda item: item["monster_id"]),
        }
        for map_id, groups in sorted(groups_by_map.items())
    ]
    return encounters, joins


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("../starhome_lz_ry_full_parsed"))
    parser.add_argument("--output-root", type=Path, default=Path("data/gameplay/glory"))
    args = parser.parse_args()
    source_csv = args.source_root / "catalogs_utf8" / "npc_catalog.csv"
    relations_path = args.source_root / "catalogs" / "monsters" / "glory_monster_map_relations.json"
    map_index_path = Path("data/content/glory_map_runtime_index_v1.json")
    with source_csv.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))
    definitions = build_definitions(rows, source_csv)
    encounters, joins = build_encounters(rows, read_json(relations_path), read_json(map_index_path))
    write_json(
        args.output_root / "glory_monsters_v1.json",
        {
            "schema_version": 1,
            "content_version": "glory-runtime-v1",
            "summary": {"definitions": len(definitions), "curated_overrides": len(CURATED_IDS)},
            "source_audit": {"source_release": "starhome_lz_ry", "npc_catalog_sha256": sha256(source_csv)},
            "definitions": definitions,
        },
    )
    write_json(
        args.output_root / "glory_monster_encounters_v1.json",
        {
            "schema_version": 1,
            "content_version": "glory-runtime-v1",
            "summary": {
                "encounters": len(encounters),
                "joined_classes": len(joins),
                "unjoined_classes": len(read_json(relations_path)["relations"]) - len(joins),
            },
            "encounters": encounters,
            "confirmed_joins": joins,
            "caveat": "Client placements establish map presence, not retired-server spawn coordinates or population counts.",
        },
    )
    print(f"Generated {len(definitions)} monsters and {len(encounters)} map encounters from {len(joins)} safe class joins")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
