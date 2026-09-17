#!/usr/bin/env python3
"""Build executable monster definitions from the decoded Glory client tables.

The retired server's complete spawn table is unavailable. Recovered editor
placements remain audit evidence, while ordinary field populations follow the
remake's explicit radial progression and regional ecology design.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


CURATED_IDS = {1: "toxic_gel", 2: "photosensitive_orb", 3: "om_larva", 4: "om_adult"}
POPULATION_POLICY = {
    "maximum_population": 200,
    "replenish_interval_seconds": 60,
    "critical_threshold_ratio": 0.5,
    "low_threshold_ratio": 0.8,
    "critical_replenish_ratio": 0.2,
    "low_replenish_ratio": 0.1,
    "normal_replenish_ratio": 0.05,
    "spawn_distribution": "full_walkable_map",
    "minimum_spawn_separation": 96,
}

# Coarse remake tiers confirmed with the user. Prefix variants inside one tier
# keep their source stats, so e.g. toxic remains stronger than low-temperature.
MONSTER_TIERS: dict[int, list[tuple[int, str]]] = {
    1: [(1, "slime"), (2, "photosensitive"), (3, "om"), (4, "om")],
    2: [(5, "slime"), (6, "photosensitive"), (7, "om"), (8, "om")],
    3: [(9, "slime"), (10, "photosensitive"), (11, "om"), (12, "om")],
    4: [(13, "slime"), (15, "om"), (14, "mutant_insect"), (16, "mutant_insect")],
    5: [(17, "slime"), (21, "om"), (19, "mutant_insect"), (22, "mutant_insect")],
    6: [
        (23, "slime"), (24, "mutant_insect"), (26, "mutant_insect"),
        (28, "sama"), (29, "mechanical"), (30, "mechanical"),
        (32, "sama"), (34, "sama"),
    ],
    7: [(27, "mutant_insect"), (35, "sama"), (31, "mechanical"), (36, "mechanical")],
    8: [
        (25, "om"), (33, "mutant_insect"), (38, "mechanical"),
        (20, "sama"), (18, "sama"), (40, "mutant_insect"),
        (48, "mechanical"), (49, "mechanical"), (54, "crystal"), (55, "crystal"),
    ],
    9: [(37, "mutant_insect"), (41, "mechanical"), (39, "sama"), (43, "sama"),
        (50, "mechanical"), (51, "mechanical"), (56, "crystal"), (57, "crystal")],
    10: [(42, "sama"), (44, "mechanical"), (45, "mechanical"),
         (46, "mechanical"), (47, "mutant_insect"),
         (52, "mechanical"), (53, "mechanical"), (58, "crystal"), (59, "crystal")],
}
ECOLOGY_FAMILIES = ("slime", "photosensitive", "om", "mutant_insect", "sama", "mechanical")
SECTOR_FAMILIES = {
    "center": ("slime", "photosensitive", "om"),
    "north": ("slime", "photosensitive"),
    "north_east": ("photosensitive", "om"),
    "east": ("om", "sama"),
    "south_east": ("sama", "mechanical"),
    "south": ("mechanical", "sama"),
    "south_west": ("mechanical", "mutant_insect"),
    "west": ("mutant_insect", "slime"),
    "north_west": ("slime", "mutant_insect"),
}
WORLD_THEME_OFFSETS = {
    "nft_bl": 0, "nft_bt": 1, "nft_btb": 2,
    "nft_ds": 3, "nft_pl": 4, "nft_sk": 5,
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
        # 2026-09-17 玩家调速：毒胶喷射采用此前速度的40%，不改普通弹体。
        "runtime_projectile_speed": None if contact else (400 if corrosive else 416.666667),
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


def recover_class_names(source_root: Path) -> dict[str, dict[str, Any]]:
    """Resolve explicit class name assignments, never palette identity aliases."""
    strings_path = source_root / "great/code_string.fcc"
    classes_path = source_root / "npcclt1.fcc"
    strings_text = strings_path.read_text(encoding="utf-8-sig")
    strings = {
        match[1]: (match[2], strings_text.count("\n", 0, match.start()) + 1)
        for match in re.finditer(r'^\s*#define\s+(String\d+)\s+"([^"]+)"', strings_text, re.M)
    }
    text = classes_path.read_text(encoding="utf-8-sig")
    declarations = list(re.finditer(r"^class\s+([^\s:]+)\s*:", text, re.M))
    result = {}
    for index, declaration in enumerate(declarations):
        end = declarations[index + 1].start() if index + 1 < len(declarations) else len(text)
        body = text[declaration.end():end]
        assignment = re.search(r"^\s*m_sNpcName\s*=\s*(String\d+)\s*;", body, re.M)
        if assignment is None or assignment[1] not in strings:
            continue
        name, string_line = strings[assignment[1]]
        result[declaration[1]] = {
            "display_name": name,
            "source_class_file": "npcclt1.fcc",
            "source_class_line": text.count("\n", 0, declaration.start()) + 1,
            "source_name_token": assignment[1],
            "source_string_file": "great/code_string.fcc",
            "source_string_line": string_line,
        }
    return result


def field_progression(source_id: str) -> dict[str, Any]:
    """Return deterministic danger and ecology coordinates for a field map."""
    world, code = source_id.removeprefix("map:").split("/", 1)
    match = re.fullmatch(r"(?:(?P<region>[a-z]+)_)?(?P<row>[a-j])(?P<column>\d{2})", code)
    if match is None:
        raise ValueError(f"Unsupported field map code: {source_id}")
    row = ord(match["row"]) - ord("a")
    column = int(match["column"])
    region = match["region"] or "main"
    if region == "main":
        row_delta, column_delta = row - 3, column - 4  # D04 city exit
        tier = min(10, 1 + max(abs(row_delta), abs(column_delta)))
    else:
        row_delta, column_delta = row - 2, column - 3  # C03 regional center
        tier = min(10, 8 + abs(row_delta) + abs(column_delta))
    vertical = "north" if row_delta < 0 else ("south" if row_delta > 0 else "")
    horizontal = "west" if column_delta < 0 else ("east" if column_delta > 0 else "")
    sector = "_".join(part for part in (vertical, horizontal) if part) or "center"
    offset = WORLD_THEME_OFFSETS.get(world, 0)
    themes = tuple(
        ECOLOGY_FAMILIES[(ECOLOGY_FAMILIES.index(family) + offset) % len(ECOLOGY_FAMILIES)]
        for family in SECTOR_FAMILIES[sector]
    )
    return {"world": world, "region": region, "danger_tier": tier, "sector": sector, "themes": themes}


def designed_spawn_groups(source_id: str, map_id: str) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Choose three to five ordinary species from one ecology and adjacent tiers."""
    progression = field_progression(source_id)
    tier = int(progression["danger_tier"])
    allowed_tiers = [tier] if tier == 1 else [tier - 1, tier]
    themes = set(progression["themes"])
    if "mechanical" in themes:
        themes.add("crystal")
        progression["themes"] = [*progression["themes"], "crystal"]
    ranked: list[tuple[int, int, int, int, str]] = []
    stable_seed = int(hashlib.sha256(map_id.encode("utf-8")).hexdigest()[:8], 16)
    for candidate_tier in reversed(allowed_tiers):
        for index, family in MONSTER_TIERS[candidate_tier]:
            theme_penalty = 0 if family in themes else 1
            stable_order = int(hashlib.sha256(f"{map_id}:{index}".encode("utf-8")).hexdigest()[:8], 16)
            ranked.append((theme_penalty, tier - candidate_tier, stable_order, index, family))
    target_count = min(5, 3 + stable_seed % 3, len(ranked))
    selected = sorted(ranked)[:target_count]
    groups = [
        {
            "group_id": f"{map_id}.{runtime_id(index)}",
            "monster_id": runtime_id(index),
            "weight": 1.0,
            "progression_tier": candidate_tier,
            "ecology_family": family,
        }
        for _, tier_gap, _, index, family in selected
        for candidate_tier in [tier - tier_gap]
    ]
    progression["allowed_tiers"] = allowed_tiers
    progression["ordinary_species_limit"] = 5
    return groups, progression


def build_encounters(
    rows: list[dict[str, str]], relations: dict[str, Any], map_index: dict[str, Any],
    known_maps: dict[str, Any], class_names: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    field_sources = {row["id"] for row in known_maps["definitions"] if row["category"] == "field_code"}
    source_to_runtime = {
        row["source_id"]: row["runtime_id"] for row in map_index["runtime_maps"]
        if row["source_id"] in field_sources
    }
    rows_by_name: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        rows_by_name[row["npc_name"]].append(row)
    groups_by_map: dict[str, dict[str, dict[str, Any]]] = defaultdict(dict)
    classes_by_map: dict[str, list[str]] = defaultdict(list)
    joins: list[dict[str, Any]] = []
    for relation in relations["relations"]:
        class_name = relation["monster_class"]
        class_evidence = class_names.get(class_name, {})
        names = [class_evidence.get("display_name", ""), *relation.get("display_names", []), class_name]
        candidates = {row["index"]: row for name in names for row in rows_by_name.get(name, [])}
        if len(candidates) != 1:
            continue
        source_row = next(iter(candidates.values()))
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
            classes_by_map[mapped].append(class_name)
            joined_maps.append(mapped)
        joins.append(
            {
                "monster_class": relation["monster_class"],
                "species_id": species_id,
                "npc_index": number(source_row["index"]),
                "maps": sorted(set(joined_maps)),
                "evidence": "exact_client_class_display_name",
                "source_name_resolution": class_evidence,
            }
        )
    elite = read_json(Path(__file__).resolve().parents[1] / "data/gameplay/elite_population_v1.json")
    encounters = []
    for source_id, map_id in sorted(source_to_runtime.items()):
        # Kept in the existing stage3 definition; the runtime applies that override.
        if map_id == "d04_field_zone":
            continue
        groups, progression = designed_spawn_groups(source_id, map_id)
        encounter = {
            "encounter_id": f"glory_{map_id}_population",
            "map_id": map_id,
            "enabled": True,
            "population_policy": POPULATION_POLICY,
            "spawn_groups": groups,
            "distribution_evidence": "design_inferred_radial_ecology",
            "source_map_id": source_id,
            "progression": progression,
        }
        if progression["danger_tier"] == elite["danger_tier"]:
            encounter["elite_population_policy"] = {key: elite[key] for key in ("maximum_population", "replenish_interval_seconds")}
            encounter["elite_spawn_groups"] = [dict(monster_id=runtime_id(index), weight=1.0) for index in elite["species_indices"]]
        if groups_by_map.get(map_id):
            encounter["supporting_client_evidence"] = {
                "kind": "historical_client_editor_placement",
                "monster_ids": sorted(groups_by_map[map_id]),
                "monster_classes": sorted(set(classes_by_map[map_id])),
            }
        encounters.append(encounter)
    return encounters, joins


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("../starhome_lz_ry_full_parsed"))
    parser.add_argument("--fcc-source-root", type=Path, default=Path("../starhome_lz_ry_fcc_source"))
    parser.add_argument("--output-root", type=Path, default=Path("data/gameplay/glory"))
    args = parser.parse_args()
    source_csv = args.source_root / "catalogs_utf8" / "npc_catalog.csv"
    relations_path = args.source_root / "catalogs" / "monsters" / "glory_monster_map_relations.json"
    map_index_path = Path("data/content/glory_map_runtime_index_v1.json")
    with source_csv.open(encoding="utf-8-sig", newline="") as source:
        rows = list(csv.DictReader(source))
    definitions = build_definitions(rows, source_csv)
    encounters, joins = build_encounters(
        rows, read_json(relations_path), read_json(map_index_path),
        read_json(Path("data/content/known_maps_v1.json")),
        recover_class_names(args.fcc_source_root),
    )
    known_maps = read_json(Path("data/content/known_maps_v1.json"))
    field_sources = {row["id"] for row in known_maps["definitions"] if row["category"] == "field_code"}
    runtime_field_maps = sum(
        row["source_id"] in field_sources for row in read_json(map_index_path)["runtime_maps"]
    )
    configured_field_maps = len(encounters) + 1
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
                "client_evidence_maps": sum("supporting_client_evidence" in row for row in encounters),
                "design_inferred_maps": len(encounters),
                "curated_override_maps": 1,
                "configured_field_maps": configured_field_maps,
                "unconfigured_field_maps": runtime_field_maps - configured_field_maps,
                "runtime_field_maps": runtime_field_maps,
            },
            "source_audit": {
                "source_release": "starhome_lz_ry",
                "map_relations_sha256": sha256(relations_path),
                "class_names_sha256": sha256(args.fcc_source_root / "npcclt1.fcc"),
                "string_constants_sha256": sha256(args.fcc_source_root / "great/code_string.fcc"),
            },
            "encounters": encounters,
            "confirmed_joins": joins,
            "progression_tiers": {
                str(tier): [runtime_id(index) for index, _ in members]
                for tier, members in MONSTER_TIERS.items()
            },
            "caveat": "Client editor placements remain historical supporting evidence, not live server tables. Ordinary field populations use an explicit remake radial/ecology design, contain at most five species, and spawn at randomized authoritative navigation positions. D04 retains its curated tier-one override.",
        },
    )
    print(f"Generated {len(definitions)} monsters and {len(encounters)} map encounters from {len(joins)} safe class joins")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
