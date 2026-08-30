#!/usr/bin/env python3
"""Build reviewable runtime-neutral registries from recovered Glory catalogs.

The generated registries deliberately separate "known to the old client" from
"ready to instantiate in the remake".  Missing assets or server semantics are
never promoted to runnable content merely because a source row exists.
"""

from __future__ import annotations

import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
SOURCE_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed"
CONTENT_ROOT = PROJECT_ROOT / "data" / "content"
CONTENT_VERSION = "glory-known-content-v1"

MAP_SOURCE = SOURCE_ROOT / "catalogs" / "maps" / "glory_map_name_relations.json"
MONSTER_SOURCE = SOURCE_ROOT / "catalogs" / "npc_catalog.json"
MONSTER_MAP_SOURCE = (
    SOURCE_ROOT / "catalogs" / "monsters" / "glory_monster_map_relations.json"
)
EQUIPMENT_SOURCE = SOURCE_ROOT / "catalogs" / "equipment_catalog.json"
MANUFACTURING_SOURCE = SOURCE_ROOT / "catalogs" / "manufacturing_recipes.json"
LOCAL_CRAFT_SOURCE = SOURCE_ROOT / "catalogs" / "local_crafting_recipes.json"
ORE_SOURCE = SOURCE_ROOT / "catalogs" / "mines" / "glory_ore_catalog.json"
RUNTIME_MAP_INDEX = CONTENT_ROOT / "glory_map_runtime_index_v1.json"
RUNTIME_MONSTER_CATALOG = PROJECT_ROOT / "data" / "gameplay" / "glory" / "glory_monsters_v1.json"

MAP_TARGET = CONTENT_ROOT / "known_maps_v1.json"
MONSTER_TARGET = CONTENT_ROOT / "known_monsters_v1.json"
ITEM_TARGET = CONTENT_ROOT / "known_items_v1.json"
MANIFEST_TARGET = CONTENT_ROOT / "known_content_registry_v1.json"

RUNTIME_MAPS = {
    ("roomsvr1", "NFT_BT"): ("yian_harbor_hall_floor_1", "ready"),
    ("roomsvr1", "NFT_SK"): ("yian_harbor_hall_floor_1", "ready"),
    ("city1svr", "NFT_BL"): ("yian_harbor_city", "ready"),
    ("city1svr", "NFT_BT"): ("yian_harbor_city", "ready"),
    ("c03", "NFT_BL"): ("buli_c03_field_zone", "ready"),
    ("c04", "NFT_BL"): ("buli_c04_field_zone", "ready"),
    ("c05", "NFT_BL"): ("buli_c05_field_zone", "ready"),
    ("d03", "NFT_BL"): ("buli_d03_field_zone", "ready"),
    ("d04", "NFT_BL"): ("d04_field_zone", "ready"),
    ("d04", "NFT_BT"): ("d04_field_zone", "ready"),
    ("d04", "NFT_BTB"): ("d04_field_zone", "ready"),
    ("d04", "NFT_PL"): ("d04_field_zone", "ready"),
    ("d05", "NFT_BL"): ("buli_d05_field_zone", "ready"),
    ("g08", "NFT_BL"): ("g08_field_zone", "partial"),
    ("g08", "NFT_BT"): ("g08_field_zone", "partial"),
}

RUNTIME_ITEM_FILES = [
    PROJECT_ROOT / "data" / "gameplay" / "stage3" / "starter_loadout_v1.json",
    PROJECT_ROOT / "data" / "gameplay" / "character_items_v1.json",
    PROJECT_ROOT / "data" / "gameplay" / "material_items_v1.json",
    PROJECT_ROOT / "data" / "gameplay" / "glory" / "glory_items_v1.json",
]


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def short_hash(value: str, length: int = 12) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()[:length]


def token(value: str) -> str:
    normalized = re.sub(r"[^a-z0-9]+", "_", value.strip().lower()).strip("_")
    return normalized[:48] or "source"


def compact_document(
    path: Path,
    catalog_kind: str,
    definitions: list[dict[str, Any]],
    summary: dict[str, Any],
    source_audit: dict[str, Any],
    extra: dict[str, Any] | None = None,
    one_line: bool = False,
) -> None:
    """Write one definition per line so large generated catalogs remain reviewable."""
    fields: list[tuple[str, Any]] = [
        ("schema_version", 1),
        ("content_version", CONTENT_VERSION),
        ("catalog_kind", catalog_kind),
        ("summary", summary),
        ("source_audit", source_audit),
    ]
    if extra:
        fields.extend(extra.items())
    path.parent.mkdir(parents=True, exist_ok=True)
    if one_line:
        document = {key: value for key, value in fields}
        document["definitions"] = definitions
        path.write_text(
            json.dumps(document, ensure_ascii=False, separators=(",", ":")) + "\n",
            encoding="utf-8",
            newline="\n",
        )
        return
    lines = ["{"]
    for key, value in fields:
        lines.append(
            "  " + json.dumps(key, ensure_ascii=False) + ": "
            + json.dumps(value, ensure_ascii=False, separators=(",", ":")) + ","
        )
    lines.append('  "definitions": [')
    for index, definition in enumerate(definitions):
        suffix = "," if index + 1 < len(definitions) else ""
        lines.append(
            "    "
            + json.dumps(definition, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
            + suffix
        )
    lines.extend(["  ]", "}", ""])
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def map_content_id(runtime_key: str) -> str:
    return "map:" + runtime_key.strip().lower()


def build_maps() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    source = read_json(MAP_SOURCE)
    runtime_index = read_json(RUNTIME_MAP_INDEX)
    runtime_by_source = {
        row["source_id"]: row for row in runtime_index["runtime_maps"]
    }
    definitions: list[dict[str, Any]] = []
    runtime_ready = 0
    presentation_ready = 0
    for row in sorted(source["runtime_maps"], key=lambda value: value["runtime_key"].lower()):
        map_code = str(row["map_code"])
        world_code = str(row["world_code"])
        source_id = "map:%s/%s" % (world_code.lower(), map_code.lower())
        runtime_row = runtime_by_source.get(source_id)
        runtime_mapping = RUNTIME_MAPS.get((map_code.lower(), world_code))
        runtime_ids = [runtime_row["runtime_id"]] if runtime_row else []
        presentation_state = (
            runtime_mapping[1] if runtime_mapping and runtime_mapping[1] == "partial"
            else ("ready" if runtime_row else "unimplemented")
        )
        if runtime_ids:
            runtime_ready += 1
        if presentation_state == "ready":
            presentation_ready += 1
        display_names = [str(name) for name in row.get("display_names", []) if str(name)]
        definitions.append({
            "id": map_content_id(row["runtime_key"]),
            "record_type": "runtime_map",
            "display_name": display_names[0] if display_names else map_code.upper(),
            "display_names": display_names,
            "world_code": world_code,
            "world_name": str(row.get("world_name", "")),
            "map_code": map_code,
            "category": str(row.get("category", "unknown")),
            "resource_ids": list(row.get("resource_ids", [])),
            "source_scripts": list(row.get("source_scripts", [])),
            "legacy_keys": [str(row["runtime_key"])],
            "runtime_ids": runtime_ids,
            "availability": {
                "registration": "known",
                "runtime": "ready" if runtime_ids else "unimplemented",
                "presentation": presentation_state,
            },
        })
    summary = {
        "definitions": len(definitions),
        "worlds": len(source.get("worlds", {})),
        "resource_groups": len(source.get("resource_groups", [])),
        "runtime_ready_source_keys": runtime_ready,
        "presentation_ready_source_keys": presentation_ready,
    }
    return definitions, summary


def normalize_scalar(value: str) -> Any:
    text = str(value)
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    if re.fullmatch(r"-?(?:\d+\.\d*|\d*\.\d+)", text):
        return float(text)
    return text


def split_assets(value: str) -> list[str]:
    return [part for part in str(value).split("*") if part]


def parse_drop_candidates(value: str) -> list[dict[str, Any]]:
    candidates: list[dict[str, Any]] = []
    for segment in str(value).split("#"):
        fields = segment.split("*")
        if not fields or not fields[0].strip():
            continue
        candidate: dict[str, Any] = {"display_name": fields[0].strip()}
        for key, index in (("minimum_quantity", 1), ("maximum_quantity", 2), ("raw_weight", 3)):
            if len(fields) > index and re.fullmatch(r"\d+", fields[index].strip()):
                candidate[key] = int(fields[index])
        candidates.append(candidate)
    return candidates


def build_monsters(
    known_map_ids: set[str],
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    rows = read_json(MONSTER_SOURCE)
    runtime_monsters = {
        str(row["source_audit"]["index"]): row["id"]
        for row in read_json(RUNTIME_MONSTER_CATALOG)["definitions"]
    }
    relation_source = read_json(MONSTER_MAP_SOURCE)
    relations_by_name: dict[str, list[dict[str, Any]]] = defaultdict(list)
    relation_definitions: list[dict[str, Any]] = []
    relation_count = 0
    for relation in relation_source["relations"]:
        maps: list[dict[str, Any]] = []
        for map_row in relation.get("maps", []):
            runtime_key = f"{map_row['world_code']}/{str(map_row['map_code']).lower()}"
            map_id = map_content_id(runtime_key)
            if map_id not in known_map_ids:
                raise RuntimeError(f"monster relation references unknown map: {runtime_key}")
            maps.append({
                "map_id": map_id,
                "evidence_record_count": int(map_row.get("evidence_record_count", 0)),
                "source_file": str(map_row.get("source_file", "")),
                "source_lines": list(map_row.get("source_lines", [])),
            })
        relation_count += len(maps)
        relation_id = "monster:class:%s:%s" % (
            token(str(relation["monster_class"])),
            short_hash(str(relation["monster_class"]), 8),
        )
        display_names = [str(name) for name in relation.get("display_names", []) if str(name)]
        relation_definition = {
            "id": relation_id,
            "record_type": "map_archetype",
            "display_name": display_names[0] if display_names else str(relation["monster_class"]),
            "display_names": display_names,
            "source_class": str(relation["monster_class"]),
            "map_presence": maps,
            "legacy_keys": [f"class:{relation['monster_class']}"],
            "runtime_ids": [],
            "availability": {
                "registration": "known",
                "runtime": "unimplemented",
                "presentation": "source_relation_only",
            },
        }
        relation_definitions.append(relation_definition)
        for name in display_names:
            relations_by_name[name].append(relation_definition)

    definitions: list[dict[str, Any]] = []
    runtime_ready = 0
    with_source_presentation = 0
    for row in sorted(rows, key=lambda value: int(value["index"])):
        index = str(row["index"])
        display_name = str(row.get("npc_name", ""))
        runtime_ids = [runtime_monsters[index]] if index in runtime_monsters else []
        if runtime_ids:
            runtime_ready += 1
        body_assets = split_assets(row.get("attr_30", ""))
        shadow_assets = split_assets(row.get("attr_31", ""))
        effect_assets = [
            str(row.get(field, ""))
            for field in ("attr_24", "attr_26", "attr_27")
            if str(row.get(field, ""))
        ]
        if body_assets or shadow_assets or effect_assets:
            with_source_presentation += 1
        matched_relations = relations_by_name.get(display_name, [])
        map_presence_by_id: dict[str, dict[str, Any]] = {}
        for relation in matched_relations:
            for presence in relation["map_presence"]:
                map_presence_by_id[presence["map_id"]] = presence
        attributes = {
            field: normalize_scalar(row.get(field, ""))
            for field in (f"attr_{number:02d}" for number in range(35))
        }
        definitions.append({
            "id": f"monster:npc:{int(index):03d}",
            "record_type": "npc_row",
            "display_name": display_name,
            "source_index": int(index),
            "attributes": attributes,
            "raw_attributes": str(row.get("attr_raw", "")),
            "drop_candidates": parse_drop_candidates(row.get("produce_obj", "")),
            "raw_skills": str(row.get("skill", "")),
            "source_presentation": {
                "body_assets": body_assets,
                "shadow_assets": shadow_assets,
                "effect_assets": effect_assets,
                "palette": str(row.get("attr_32", "")),
            },
            "map_archetype_ids": [relation["id"] for relation in matched_relations],
            "map_presence": list(map_presence_by_id.values()),
            "legacy_keys": [f"npc_index:{index}", f"name:{display_name}"],
            "runtime_ids": runtime_ids,
            "availability": {
                "registration": "known",
                "runtime": "ready" if runtime_ids else "unimplemented",
                "presentation": "ready" if runtime_ids else (
                    "source_references_known" if body_assets else "unknown"
                ),
            },
            "source_audit": {
                "source_file": str(row.get("source_file", "")),
            },
        })
    definitions.extend(relation_definitions)
    definitions.sort(key=lambda value: value["id"])
    summary = {
        "definitions": len(definitions),
        "npc_rows": len(rows),
        "map_archetypes": len(relation_definitions),
        "monster_map_relations": relation_count,
        "runtime_ready_npc_rows": runtime_ready,
        "npc_rows_with_source_presentation": with_source_presentation,
    }
    return definitions, summary


def equipment_registration_id(row: dict[str, Any]) -> str:
    locator = f"{row.get('source_file', '')}:{row.get('source_line', '')}"
    return "item:equipment:%s:%s" % (
        token(str(row.get("class_name", ""))), short_hash(locator, 10)
    )


def runtime_item_definitions() -> list[dict[str, Any]]:
    result: list[dict[str, Any]] = []
    for path in RUNTIME_ITEM_FILES:
        document = read_json(path)
        for definition in document.get("definitions", []):
            copied = dict(definition)
            copied["_runtime_source"] = path.relative_to(PROJECT_ROOT).as_posix()
            result.append(copied)
    return result


def build_items() -> tuple[list[dict[str, Any]], dict[str, Any]]:
    equipment_rows = read_json(EQUIPMENT_SOURCE)
    manufacturing_rows = read_json(MANUFACTURING_SOURCE)
    local_rows = read_json(LOCAL_CRAFT_SOURCE)
    ore_rows = read_json(ORE_SOURCE)["catalog"]
    runtime_rows = runtime_item_definitions()

    runtime_by_source_class: dict[str, list[str]] = defaultdict(list)
    runtime_by_known_registration: dict[str, list[str]] = defaultdict(list)
    runtime_by_name: dict[str, list[str]] = defaultdict(list)
    runtime_by_id: dict[str, dict[str, Any]] = {}
    for definition in runtime_rows:
        runtime_id = str(definition["id"])
        runtime_by_id[runtime_id] = definition
        runtime_by_name[str(definition.get("display_name", ""))].append(runtime_id)
        selector = definition.get("source_audit", {}).get("row_selector", {})
        if isinstance(selector, dict) and selector.get("class_name"):
            runtime_by_source_class[str(selector["class_name"])].append(runtime_id)
        known_registration = definition.get("source_audit", {}).get("known_registry_id", "")
        if known_registration:
            runtime_by_known_registration[str(known_registration)].append(runtime_id)
        if runtime_id.startswith("item:material:"):
            runtime_by_known_registration[runtime_id].append(runtime_id)

    definitions: list[dict[str, Any]] = []
    attached_runtime_ids: set[str] = set()
    for row in sorted(
        equipment_rows,
        key=lambda value: (
            str(value.get("class_name", "")).lower(),
            str(value.get("source_file", "")),
            int(value.get("source_line", 0) or 0),
        ),
    ):
        source_class = str(row.get("class_name", ""))
        registration_id = equipment_registration_id(row)
        runtime_ids = list(dict.fromkeys([
            *runtime_by_known_registration.get(registration_id, []),
            *runtime_by_source_class.get(source_class, []),
        ]))
        if not runtime_ids:
            candidates = runtime_by_name.get(str(row.get("display_name", "")), [])
            if len(candidates) == 1:
                runtime_ids = list(candidates)
        attached_runtime_ids.update(runtime_ids)
        stats = {
            key: row[key]
            for key in (
                "skill_level", "worth", "sell", "attack", "attack_limit", "energy",
                "distance", "distance_limit", "weight", "required_grade", "health",
                "output_power", "drive", "defense", "max_hardiness", "wear_degree",
                "repair_materials", "material_recipe",
            )
            if row.get(key, "") != ""
        }
        definitions.append({
            "id": registration_id,
            "record_type": "equipment_row",
            "display_name": str(row.get("display_name", source_class)),
            "description": str(row.get("description", "")),
            "source_class": source_class,
            "base_class": str(row.get("base_class", "")),
            "inheritance": str(row.get("inheritance", "")),
            "category": str(row.get("category", "")),
            "stats": stats,
            "source_assets": {
                key: str(row.get(key, ""))
                for key in ("asset_base", "asset_dialog", "asset_move")
                if str(row.get(key, ""))
            },
            "legacy_keys": [f"class:{source_class}", f"name:{row.get('display_name', '')}"],
            "runtime_ids": runtime_ids,
            "availability": {
                "registration": "known",
                "runtime": "ready" if runtime_ids else "unimplemented",
                "presentation": "ready" if runtime_ids else (
                    "source_references_known" if row.get("asset_base") else "unknown"
                ),
            },
            "source_audit": {
                "source_file": str(row.get("source_file", "")),
                "source_line": int(row.get("source_line", 0) or 0),
            },
        })

    material_sources: dict[str, list[dict[str, Any]]] = defaultdict(list)

    def add_material(name: str, role: str, source: str) -> None:
        cleaned = str(name).strip()
        if not cleaned:
            return
        evidence = {"role": role, "source": source}
        if evidence not in material_sources[cleaned]:
            material_sources[cleaned].append(evidence)

    for ore in ore_rows:
        add_material(str(ore.get("display_name", "")), "ore", "glory_ore_catalog")
    for row in manufacturing_rows:
        source = str(row.get("source_file", ""))
        for material in row.get("materials", []):
            add_material(
                str(material.get("name", material.get("raw", ""))),
                "manufacturing_material",
                source,
            )
    for row in local_rows:
        source = f"{row.get('source_file', '')}:{row.get('source_line', '')}"
        try:
            materials = json.loads(str(row.get("materials_json", "[]")))
        except json.JSONDecodeError:
            materials = []
        for material in materials:
            add_material(str(material.get("name", "")), "local_crafting_material", source)
    for row in read_json(MONSTER_SOURCE):
        source = f"npc_index:{row.get('index', '')}"
        for candidate in parse_drop_candidates(row.get("produce_obj", "")):
            add_material(candidate["display_name"], "monster_drop_candidate", source)

    for name in sorted(material_sources):
        registration_id = "item:material:" + short_hash(name)
        runtime_ids = list(dict.fromkeys([
            *runtime_by_known_registration.get(registration_id, []),
            *runtime_by_name.get(name, []),
        ]))
        attached_runtime_ids.update(runtime_ids)
        definitions.append({
            "id": registration_id,
            "record_type": "material_name",
            "display_name": name,
            "evidence_roles": material_sources[name],
            "legacy_keys": [f"name:{name}"],
            "runtime_ids": runtime_ids,
            "availability": {
                "registration": "known",
                "runtime": "ready" if runtime_ids else "unimplemented",
                "presentation": "ready" if runtime_ids else "unknown",
            },
        })

    for row in local_rows:
        source_class = str(row.get("class_name", ""))
        locator = f"{row.get('source_file', '')}:{row.get('source_line', '')}"
        definitions.append({
            "id": "item:craft:%s:%s" % (token(source_class), short_hash(locator, 10)),
            "record_type": "local_crafting_product",
            "display_name": str(row.get("display_name", source_class)),
            "source_class": source_class,
            "raw_materials": str(row.get("materials", "")),
            "legacy_keys": [f"class:{source_class}"],
            "runtime_ids": [],
            "availability": {
                "registration": "known",
                "runtime": "unimplemented",
                "presentation": "unknown",
            },
            "source_audit": {
                "source_file": str(row.get("source_file", "")),
                "source_line": int(row.get("source_line", 0) or 0),
            },
        })

    # Runtime definitions absent from recovered normalized tables still belong to
    # the registry, but remain explicitly sourced from the remake definition.
    for runtime_id in sorted(set(runtime_by_id) - attached_runtime_ids):
        definition = runtime_by_id[runtime_id]
        definitions.append({
            "id": "item:runtime:" + token(runtime_id),
            "record_type": "runtime_definition",
            "display_name": str(definition.get("display_name", runtime_id)),
            "runtime_kind": str(definition.get("kind", "")),
            "legacy_keys": [f"runtime:{runtime_id}"],
            "runtime_ids": [runtime_id],
            "availability": {
                "registration": "known",
                "runtime": "ready",
                "presentation": "ready",
            },
            "source_audit": {"runtime_source": definition["_runtime_source"]},
        })

    definitions.sort(key=lambda value: value["id"])
    runtime_covered = {
        runtime_id
        for definition in definitions
        for runtime_id in definition.get("runtime_ids", [])
    }
    missing_runtime = sorted(set(runtime_by_id) - runtime_covered)
    if missing_runtime:
        raise RuntimeError(f"runtime items are missing from known registry: {missing_runtime}")
    summary = {
        "definitions": len(definitions),
        "equipment_rows": len(equipment_rows),
        "material_names": len(material_sources),
        "local_crafting_products": len(local_rows),
        "runtime_item_ids": len(runtime_by_id),
        "runtime_item_ids_covered": len(runtime_covered),
    }
    return definitions, summary


def ensure_unique(definitions: list[dict[str, Any]], context: str) -> None:
    identifiers = [definition["id"] for definition in definitions]
    if len(identifiers) != len(set(identifiers)):
        duplicates = sorted(
            identifier for identifier in set(identifiers) if identifiers.count(identifier) > 1
        )
        raise RuntimeError(f"duplicate {context} registry IDs: {duplicates[:10]}")


def main() -> int:
    source_paths = [
        MAP_SOURCE, MONSTER_SOURCE, MONSTER_MAP_SOURCE, EQUIPMENT_SOURCE,
        MANUFACTURING_SOURCE, LOCAL_CRAFT_SOURCE, ORE_SOURCE, *RUNTIME_ITEM_FILES,
        RUNTIME_MAP_INDEX, RUNTIME_MONSTER_CATALOG,
    ]
    missing = [path for path in source_paths if not path.is_file()]
    if missing:
        raise RuntimeError(f"known-content sources are missing: {missing}")

    maps, map_summary = build_maps()
    map_ids = {definition["id"] for definition in maps}
    monsters, monster_summary = build_monsters(map_ids)
    items, item_summary = build_items()
    ensure_unique(maps, "map")
    ensure_unique(monsters, "monster")
    ensure_unique(items, "item")

    compact_document(
        MAP_TARGET, "map", maps, map_summary,
        {"source": str(MAP_SOURCE.relative_to(OUTPUTS_ROOT)), "sha256": sha256(MAP_SOURCE)},
    )
    compact_document(
        MONSTER_TARGET, "monster", monsters, monster_summary,
        {
            "npc_source": str(MONSTER_SOURCE.relative_to(OUTPUTS_ROOT)),
            "npc_sha256": sha256(MONSTER_SOURCE),
            "map_relation_source": str(MONSTER_MAP_SOURCE.relative_to(OUTPUTS_ROOT)),
            "map_relation_sha256": sha256(MONSTER_MAP_SOURCE),
        },
    )
    compact_document(
        ITEM_TARGET, "item", items, item_summary,
        {
            "equipment_source": str(EQUIPMENT_SOURCE.relative_to(OUTPUTS_ROOT)),
            "equipment_sha256": sha256(EQUIPMENT_SOURCE),
            "manufacturing_source": str(MANUFACTURING_SOURCE.relative_to(OUTPUTS_ROOT)),
            "manufacturing_sha256": sha256(MANUFACTURING_SOURCE),
            "local_crafting_source": str(LOCAL_CRAFT_SOURCE.relative_to(OUTPUTS_ROOT)),
            "local_crafting_sha256": sha256(LOCAL_CRAFT_SOURCE),
            "ore_source": str(ORE_SOURCE.relative_to(OUTPUTS_ROOT)),
            "ore_sha256": sha256(ORE_SOURCE),
        },
        one_line=True,
    )
    manifest = {
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "catalogs": {
            "map": "res://data/content/known_maps_v1.json",
            "monster": "res://data/content/known_monsters_v1.json",
            "item": "res://data/content/known_items_v1.json",
        },
        "expected_counts": {
            "map": map_summary,
            "monster": monster_summary,
            "item": item_summary,
        },
        "semantics": {
            "known": "Recovered client evidence exists for this registration.",
            "runtime_ready": "A controlled remake definition can instantiate this content.",
            "presentation_ready": "Business-named Godot presentation resources are available.",
        },
    }
    MANIFEST_TARGET.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    print(
        "KNOWN_CONTENT_REGISTRIES_BUILT "
        f"maps={len(maps)} monsters={len(monsters)} items={len(items)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
