#!/usr/bin/env python3
"""Promote every decoded Glory item row into typed remake content."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any


NUMERIC_STATS = {
    "skill_level": "required_skill_level",
    "worth": "purchase_value",
    "sell": "sell_value",
    "attack": "base_attack",
    "attack_limit": "attack_limit",
    "energy": "energy_cost",
    "distance": "range",
    "distance_limit": "range_limit",
    "weight": "weight",
    "required_grade": "required_grade",
    "health": "max_health",
    "output_power": "output_power",
    "drive": "drive",
    "defense": "defense",
    "max_hardiness": "max_durability",
    "wear_degree": "wear_degree",
}


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def integer(value: Any, default: int = 0) -> int:
    try:
        return int(float(str(value).strip()))
    except (TypeError, ValueError):
        return default


def resolved_properties(row: dict[str, str]) -> dict[str, Any]:
    try:
        return json.loads(row.get("resolved_properties_json", "{}"))
    except json.JSONDecodeError:
        return {}


def equipment_kind(row: dict[str, str]) -> str:
    category = row.get("category", "")
    base = row.get("base_class", "").lower()
    if "missile" in base:
        return "missile_weapon"
    if "firegun" in base or "rocket" in base or "huojian" in base:
        return "rocket_weapon"
    if category == "服装":
        return "character_clothing"
    if category == "战车/载具":
        return "vehicle_chassis"
    if category == "引擎":
        return "vehicle_engine"
    if category == "武器":
        if "energygun" in base:
            return "energy_cannon"
        return "vehicle_weapon"
    return "vehicle_equipment" if category in {"护甲", "其他装备", "机甲", "飞船装备"} else "equipment"


def character_slot(row: dict[str, str]) -> str:
    base = row.get("base_class", "").lower()
    name = row.get("display_name", "")
    if "hair" in base or "wawatou" in base or "头" in name or "发" in name:
        return "head"
    if any(token in name for token in ("裤", "裙", "下装")):
        return "lower_body"
    if any(token in name for token in ("鞋", "靴")):
        return "shoes"
    if any(token in name for token in ("手套", "手甲")):
        return "hands"
    return "upper_body"


def required_sex(properties: dict[str, Any]) -> str:
    value = integer(properties.get("m_nWearSex", -1), -1)
    return {0: "male", 1: "female"}.get(value, "any")


def equipment_definition(row: dict[str, str], known: dict[str, Any]) -> dict[str, Any]:
    props = resolved_properties(row)
    stats = {
        output: integer(row[source])
        for source, output in NUMERIC_STATS.items()
        if str(row.get(source, "")).strip()
    }
    stats["legacy_properties"] = props
    definition: dict[str, Any] = {
        "id": known["id"],
        "kind": equipment_kind(row),
        "display_name": known.get("display_name", row["display_name"]),
        "description": known.get("description", row.get("description", "")),
        "max_stack": 1,
        "stats": stats,
        "presentation": {
            "inventory": {"ale_reference": row.get("asset_base", "").strip(), "frame": 0},
            "dialog": {"ale_reference": row.get("asset_dialog", "").strip(), "frame": 0},
            "world": {"ale_reference": row.get("asset_move", "").strip(), "frame": 0},
        },
        "source_class": row["class_name"],
        "source_category": row.get("category", ""),
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_file": row.get("source_file", ""),
            "source_line": integer(row.get("source_line", "")),
            "inheritance": row.get("inheritance", ""),
            "repair_materials": row.get("repair_materials", ""),
            "material_recipe": row.get("material_recipe", ""),
        },
    }
    if definition["kind"] == "character_clothing":
        definition["character_slot"] = character_slot(row)
        definition["required_sex"] = required_sex(props)
        definition["stats"]["skill_modifiers"] = {}
        definition["presentation"]["dialog"]["z_layer"] = integer(props.get("m_nLayer", 60), 60)
    else:
        location = integer(props.get("m_nLocation", -1), -1)
        if location >= 0:
            definition["equipment_location"] = location
        definition["equip_kind"] = integer(props.get("m_nEquipKind", -1), -1)
    return definition


def material_definition(known: dict[str, Any]) -> dict[str, Any]:
    return {
        "id": known["id"],
        "kind": "material",
        "display_name": known["display_name"],
        "description": "荣耀版客户端已登记的材料或消耗品。具体用途见配方和掉落证据。",
        "max_stack": 99,
        "evidence_roles": known.get("evidence_roles", []),
        "presentation": {},
        "source_audit": {"source_release": "starhome_lz_ry", "status": "name_only"},
    }


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")


def build_recipes(source_root: Path) -> dict[str, Any]:
    files = {
        "local_crafting": "local_crafting_recipes.json",
        "manufacturing": "manufacturing_recipes.json",
        "equipment_upgrade": "equipment_upgrade_recipes.json",
        "equipment_dismantle": "equipment_dismantle_recipes.json",
    }
    groups = {key: read_json(source_root / "catalogs" / filename) for key, filename in files.items()}
    return {
        "schema_version": 1,
        "content_version": "glory-runtime-v1",
        "summary": {key: len(rows) for key, rows in groups.items()},
        "execution_status": "registered_client_evidence_not_yet_authoritative_settlement",
        "groups": groups,
        "source_audit": {"source_release": "starhome_lz_ry", "files": files},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("../starhome_lz_ry_full_parsed"))
    parser.add_argument("--output-root", type=Path, default=Path("data/gameplay/glory"))
    args = parser.parse_args()
    known_path = Path("data/content/known_items_v1.json")
    known_rows = read_json(known_path)["definitions"]
    equipment_known = {
        row["source_class"]: row for row in known_rows if row.get("record_type") == "equipment_row"
    }
    material_known = [row for row in known_rows if row.get("record_type") == "material_name"]
    source_csv = args.source_root / "catalogs_utf8" / "equipment_catalog.csv"
    with source_csv.open(encoding="utf-8-sig", newline="") as source:
        equipment_rows = list(csv.DictReader(source))
    equipment = [equipment_definition(row, equipment_known[row["class_name"]]) for row in equipment_rows]
    materials = [material_definition(row) for row in material_known]
    definitions = equipment + materials
    write_json(
        args.output_root / "glory_items_v1.json",
        {
            "schema_version": 1,
            "content_version": "glory-runtime-v1",
            "summary": {"definitions": len(definitions), "equipment": len(equipment), "materials": len(materials)},
            "source_audit": {
                "source_release": "starhome_lz_ry",
                "equipment_catalog_sha256": sha256(source_csv),
                "known_item_registry_sha256": sha256(known_path),
            },
            "definitions": definitions,
        },
    )
    write_json(args.output_root / "glory_recipes_v1.json", build_recipes(args.source_root))
    print(f"Generated {len(equipment)} equipment, {len(materials)} materials and four recipe groups")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
