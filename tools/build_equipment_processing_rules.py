"""Build ordinary attribute processing rules from Glory's upgrade table and equipment caps."""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "starhome_lz_ry_fcc_source"
ATTRS = {"生命力": ("max_health", "m_nhealthUL"), "输出功率": ("output_power", "m_noutpowerUL"),
         "射程": ("range", "m_ndistanceUL"), "推进力": ("drive", "m_ndriveUL"),
         "攻击力": ("base_attack", "m_nattackUL"), "载弹量": ("ammunition_capacity", "m_nBulletCountUL")}
STARTERS = {"recruit_tank": "tank1", "beginner_engine": "engine1", "recruit_energy_cannon": "gun1",
            "starter_missile": "Missile1", "starter_rocket_launcher": "FireGun1"}


def read(path):
    return json.loads((ROOT / path).read_text(encoding="utf-8"))


def write(path, value, check):
    text = "{\n" + ",\n".join("  " + json.dumps(key) + ": " + (
        "[\n" + ",\n".join("    " + json.dumps(row, ensure_ascii=False) for row in rows) + "\n  ]"
        if isinstance(rows, list) else json.dumps(rows, ensure_ascii=False)) for key, rows in value.items()) + "\n}\n"
    target = ROOT / path
    if check:
        assert target.read_text(encoding="utf-8") == text, f"Regenerate {path}"
    else:
        target.write_text(text, encoding="utf-8")


def build(check=False):
    source = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', source.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {}
    for path in paths:
        if path == "data/gameplay/equipment_processing_items_v1.json":
            continue
        for row in read(path)["definitions"]:
            definitions[row["id"]] = row
    by_name = {row["display_name"]: row for row in sorted(definitions.values(), key=lambda row: row["id"], reverse=True)}
    for canonical in ["iron_piece", "copper_piece", "low_grade_gel", "low_grade_energy_catalyst", "low_grade_biosilicon", "low_grade_quadruped_shell"]:
        if canonical in definitions:
            by_name[definitions[canonical]["display_name"]] = definitions[canonical]
    originals = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    by_class = {row.get("source_class"): row for row in originals}
    recipes = {row["UpObjCName"]: row for row in read("data/gameplay/glory/glory_recipes_v1.json")["groups"]["equipment_upgrade"]}
    raw_fireguns = (SOURCE / "cltobj/fireguncltclass.fcc").read_text(encoding="utf-8-sig")
    profiles = []
    for row in definitions.values():
        if row.get("kind") not in ["vehicle_chassis", "vehicle_engine", "energy_cannon", "missile_weapon", "rocket_weapon"]:
            continue
        original = by_class.get(STARTERS[row["id"]], row) if row["id"] in STARTERS else row
        legacy = dict(original.get("stats", {}).get("legacy_properties", {}))
        source_class = original.get("source_class", STARTERS.get(row["id"], ""))
        if row["id"].startswith("official_rocket_firegun_"):
            source_class = "FireGun" + row["id"].rsplit("_", 1)[1]
        if source_class.startswith("FireGun") and not legacy.get("m_nattackUL"):
            match = re.search(r"^class " + source_class + r":.*?(?=^class |\Z)", raw_fireguns, re.M | re.S)
            if match:
                legacy.update(dict(re.findall(r"\b(m_n\w+)\s*=\s*(\d+)\s*;", match[0])))
        lineage = original.get("source_audit", {}).get("inheritance", "").split(" > ")
        matched = next((name for name in [source_class] + list(reversed(lineage)) if name in recipes), "")
        extrapolated = False
        if not matched:
            family = {"vehicle_chassis": "tank", "vehicle_engine": "engine", "energy_cannon": "gun",
                      "missile_weapon": "Missile", "rocket_weapon": "FireGun"}[row["kind"]]
            if not any(re.fullmatch(family + r"\d+(?:_\w+)?", name) for name in [source_class] + lineage):
                continue
            matched = max((name for name in recipes if re.fullmatch(family + r"\d+", name)), key=lambda name: int(recipes[name]["NeedSkill"]))
            extrapolated = True
        recipe = recipes[matched]
        repaired_recipe = matched == "engine10_Binding"
        if repaired_recipe:
            # Binding row omits its final quantity; the otherwise identical unbound row is complete.
            recipe = recipes["engine10"]
        skill = max(int(recipe["NeedSkill"]), int(row.get("stats", {}).get("required_skill_level", 0)))
        scale = max(1, math.ceil(skill / int(recipe["NeedSkill"]))) if extrapolated else 1
        attrs = []
        for branch in recipe["NeedObj"].split("/"):
            terms = branch.split("*")
            label = terms[0].split()[0]
            if label not in ATTRS:
                continue
            stat, cap_key = ATTRS[label]
            base = float(row.get("stats", {}).get(stat, legacy.get("m_nBulletCount", 0) if stat == "ammunition_capacity" else 0))
            cap = float(legacy.get(cap_key, row.get("stats", {}).get({"base_attack": "attack_limit", "range": "range_limit", "drive": "drive_limit"}.get(stat, ""), 0)))
            if cap <= base or base <= 0:
                continue
            materials = []
            for term in terms[1:]:
                name, quantity = term.rsplit(" ", 1)
                assert name in by_name, (row["id"], name)
                materials.append({"definition_id": by_name[name]["id"], "quantity": int(quantity) * scale})
            attrs.append({"attribute": stat, "label": label, "base": base, "limit": cap,
                          "required_skill_level": skill, "materials": materials, "currency": 0})
        if attrs:
            profiles.append({"definition_id": row["id"], "display_name": row["display_name"], "attributes": attrs,
                             "source_class": source_class, "recipe_class": matched,
                             "source_status": "unbound_recipe_repairs_missing_quantity" if repaired_recipe else "remake_scaled_last_family_recipe" if extrapolated else "client_table"})
    profiles.sort(key=lambda row: row["definition_id"])
    special = []
    source_text = (SOURCE / "cltobj/stuffclt2.fcc").read_text(encoding="utf-8-sig")
    for row in read("data/gameplay/original_drop_items_v1.json")["definitions"]:
        name = row.get("source_class", "")
        match = re.search(r"^class " + re.escape(name) + r":.*?(?=^class |\Z)", source_text, re.M | re.S)
        pairs = re.findall(r'm_szSpecialAttr\s*=\s*\("([^"]+)",(\d+)\)', match[0]) if match else []
        if pairs and pairs[0][0] in ATTRS:
            # Existing source-approved dropped-item names encode the effective increment.
            points = int(row["display_name"].rsplit("+", 1)[1])
            special.append({"definition_id": row["id"], "attribute": ATTRS[pairs[0][0]][0], "points": points,
                            "source_class": name, "source_status": "existing_drop_catalog_increment",
                            "source_variants": pairs})
    assert profiles and len(special) == 6
    write("data/gameplay/equipment_processing_rules_v1.json", {"schema_version": 1,
          "policy": {"success_chance": 1.0, "status": "remake_server_unknown_probability", "skill_id": "processing",
                     "experience": 0, "recipe_source": "expanded/zyf/maceine/upgradelist/upgradelist.txt.cab",
                     "late_equipment": "last confirmed same-family recipe scaled by ceil(required skill / source skill)",
                     "ammunition": "capacity definitions only; ammunition runtime belongs to P2-B before this attribute is exposed"},
          "materials": special, "equipment": profiles}, check)
    sprites = {row["logical_id"] for row in read("data/content/glory_sprite_runtime_index_v1.json")["sprites"]}
    promoted = []
    for grade in ["低级", "中级", "高级"]:
        for kind in ["硬质素", "复合胶板"]:
            name = grade + kind
            previous = by_name[name]
            assert previous.get("source_audit", {}).get("status") == "name_only", name
            match = re.search(r"^class " + name + r":.*?(?=^class |\Z)", source_text, re.M | re.S)
            logical = re.search(r'src=\$\+"../([^"\n]+)"', match[0])[1].lower().removesuffix(".ale")
            assert logical in sprites, logical
            promoted.append({"id": previous["id"], "kind": "material", "display_name": name, "source_class": name,
                             "max_stack": 999, "replaces_name_only": True, "presentation": {"ale_reference": logical},
                             "description": "基础加工材料，由同级四足甲的壳提炼。" if kind == "硬质素" else "基础加工材料，由同级类胶提炼。",
                             "source_audit": {"source_release": "starhome_lz_ry", "source_file": "cltobj/stuffclt2.fcc",
                                              "source_line": source_text.count("\n", 0, match.start()) + 1,
                                              "presentation_policy": "decoded embedded palette, explicit source sprite per grade"}})
    write("data/gameplay/equipment_processing_items_v1.json", {"schema_version": 1, "definitions": promoted}, check)
    print(f"Processing catalog: {len(profiles)} equipment, {len(special)} enhancement materials, {len(promoted)} existing refining products")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
