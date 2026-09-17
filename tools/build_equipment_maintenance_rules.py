"""Extract maintenance eligibility, repair costs and quick-repair tools from the original client."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

from build_equipment_processing_rules import ROOT, STARTERS, read, write


def build(check=False):
    source = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', source.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {row["id"]: row for path in paths if not path.endswith("equipment_maintenance_items_v1.json") for row in read(path)["definitions"]}
    by_name = {row["display_name"]: row for row in definitions.values()}
    for row in definitions.values():
        if row["id"].startswith("low_grade_"):
            by_name[row["display_name"]] = row
    originals = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    original_class = {row.get("source_class"): row for row in originals}
    original_name = {row["display_name"]: row for row in originals}
    raw_rockets = (ROOT.parent / "starhome_lz_ry_fcc_source/cltobj/fireguncltclass.fcc").read_text(encoding="utf-8-sig")
    profiles = []
    unresolved = []
    for row in definitions.values():
        clothing = row.get("kind") == "character_clothing"
        ground = row.get("kind") in ["vehicle_chassis", "vehicle_engine", "energy_cannon", "missile_weapon", "rocket_weapon", "mining_arm"] or 0 <= row.get("equipment_location", -1) <= 18
        if not clothing and not ground:
            continue
        original = original_class.get(STARTERS[row["id"]], row) if row["id"] in STARTERS else row
        if "source_class" not in original and row["id"] not in STARTERS:
            original = original_name.get(row["display_name"], original)
        legacy = dict(original.get("stats", {}).get("legacy_properties", {}))
        lineage = original.get("source_audit", {}).get("inheritance", "").split(" > ")
        if any("space" in name.lower() for name in lineage):
            continue
        source_class = original.get("source_class", STARTERS.get(row["id"], ""))
        if row["id"].startswith("official_rocket_firegun_"):
            source_class = "FireGun" + row["id"].rsplit("_", 1)[1]
        if source_class.startswith("FireGun") and not legacy:
            match = re.search(r"^class " + source_class + r":.*?(?=^class |\Z)", raw_rockets, re.M | re.S)
            if match:
                uncommented = re.sub(r"//[^\n]*", "", match[0])
                legacy.update(dict(re.findall(r"\b(m_\w+)\s*=\s*([^;\n]+);", uncommented)))
        forbidden = int(legacy.get("m_nAgreeRepairHardiness", 0 if "Armor" in lineage or "AGEquip" in lineage else 1)) == 0
        native_max = int(legacy.get("m_nWearDegree" if clothing else "m_nMax_Hardiness", row.get("stats", {}).get("max_durability", 1)))
        no_wear = bool(int(legacy.get("m_nNoDurable", 1 if row.get("kind") == "vehicle_chassis" else 0))) or native_max <= 1
        materials = []
        missing = []
        material_currency = 0
        if clothing:
            terms = re.findall(r'"([^"\n]+)"', legacy.get("m_szDoupStuff", ""))
            pairs = [term.rsplit(" ", 1) for term in terms if re.search(r" \d+$", term)]
        else:
            names = re.findall(r'"([^"\n]*)"', legacy.get("m_szRepairHardinessBagClassname", ""))
            amounts = re.findall(r"\d+", legacy.get("m_szRepairHardinessBagAmount", ""))
            pairs = list(zip(names, amounts))
            if len(names) != len(amounts) and any(names):
                missing.append("malformed_source_cost")
        for name, quantity in pairs:
            if not name or int(quantity) <= 0:
                continue
            if name in ["金币", "星际币"]:
                material_currency += int(quantity)
                continue
            if name not in by_name:
                missing.append(name)
            else:
                materials.append({"definition_id": by_name[name]["id"], "quantity": int(quantity)})
        # Empty vehicle lists are intentional in this client's free-maintenance branch.
        allowed = not forbidden and not missing and (bool(materials) if clothing else native_max > 1)
        if missing:
            unresolved.append({"definition_id": row["id"], "missing_materials": missing})
        fee = material_currency + (int(float(legacy.get("m_nRepaireHardinessUpkeep", 0)) * int(legacy.get("m_nWorth", row.get("stats", {}).get("purchase_value", 0))) / 100) if not clothing else 0)
        max_loss = 0.0 if clothing else 0.01
        profiles.append({"definition_id": row["id"], "display_name": row["display_name"],
                         "family": "clothing" if clothing else "vehicle", "regular_allowed": allowed,
                         "quick_allowed": not forbidden and not clothing and "Armor" not in lineage and native_max > 1,
                         "no_wear": no_wear, "wear_enabled": allowed and not no_wear,
                         "materials": materials, "currency": fee,
                         "skill_id": "tailoring" if clothing else "", "required_skill_level": int(legacy.get("m_nClothClass", 10)) if clothing else 0,
                         "experience": int(legacy.get("m_nDoupOneSuffer", 10)) if clothing else 0,
                         "maximum_loss_fraction": max_loss, "native_maximum": native_max,
                         "source_class": source_class,
                         "reason": "原版不允许常规维护" if forbidden else "未确认完整维护材料，暂不启用磨损" if not allowed else "",
                         "source_status": "client_fields_with_remake_wear_and_vehicle_maximum_loss"})
    tools = [("ElecRepairBox1", "电磁缓释箱（小型）", "ElecRB1", "installed_one", "points", 300, 500),
             ("ElecRepairBox2", "电磁缓释箱（中型）", "ElecRB2", "installed_one", "points", 600, 900),
             ("ElecRepairBox3", "电磁缓释箱（加强型）", "ElecRB3", "installed_one", "points", 1000, 1400),
             ("QuickRepairBox1", "光导速修箱（单体型）", "QuickRB2", "installed_one", "percent", 100, 2000),
             ("QuickRepairBox2", "光导速修箱（群体型）", "QuickRB1", "installed_all", "percent", 100, 6000),
             ("IonRepairBox1", "离子速修箱", "IonBox", "backpack_one", "percent", 100, 2000)]
    items, tool_rules = [], []
    for source_class, name, sprite, scope, kind, amount, price in tools:
        id = "maintenance_" + source_class.lower()
        logical = "pic2/RepairBox/" + sprite + ".ale"
        cache = ROOT.parent / "equipment_maintenance_asset_review/fr"
        raw_path = cache / "raw" / logical
        parsed = cache / "ale_sprites/pic2/RepairBox" / sprite
        frames = json.loads((parsed / "frames.json").read_text(encoding="utf-8"))
        assert frames["frame_count"] == 1
        icon = ROOT / "assets/items/maintenance" / id / "icon.png"
        if check:
            assert icon.read_bytes() == (parsed / "sheet.png").read_bytes()
        else:
            icon.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(parsed / "sheet.png", icon)
        items.append({"id": id, "kind": "maintenance_tool", "display_name": name, "max_stack": 99,
                      "description": "恢复装备耐久，保持当前耐久上限。通过基础加工窗口的维护页使用。",
                      "source_class": source_class, "workshop_unit_price": price,
                      "presentation": {"icon": "res://" + icon.relative_to(ROOT).as_posix(), "native_size": [frames["cell_width"], frames["cell_height"]]},
                      "source_audit": {"source_file": "ven/FastRestoreCltClass.fcc", "source_release": "starhome_lz_fr",
                                       "source_url": "http://update.ftxjjy.com/gameser/fr_www/" + logical,
                                       "sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(), "other_releases": {"ry": "404", "jznp": "404"}, "price_status": "remake_coin_offer"}})
        tool_rules.append({"definition_id": id, "scope": scope, "kind": kind, "amount": amount})
    write("data/gameplay/equipment_maintenance_items_v1.json", {"schema_version": 1, "definitions": items}, check)
    write("data/gameplay/equipment_maintenance_rules_v1.json", {"schema_version": 1,
          "maintenance_maps": sorted(set(read("data/world/manufacturing_facilities_v1.json")["maps"]) | {id for id, path in read("data/maps/map_directory.json")["definitions"].items() if (ROOT / path.removeprefix("res://")).is_file() and read(path.removeprefix("res://")).get("category") in ["city", "city_interior"]}),
          "policy": {"regular_location": "configured bases, city and manufacturing facility maps", "maximum_loss": "ordinary vehicle maintenance loses ceil(current maximum * 1%), remake setting; clothing and quick repair preserve maximum",
                     "wear": "remake: weapon per 20 accepted shots, engine per 60 moving seconds, mining arm per 20 successful cycles, clothing per 100 damaging hits; unsupported maintenance and no-durability equipment do not wear"},
          "equipment": sorted(profiles, key=lambda r: r["definition_id"]), "tools": tool_rules, "unresolved": unresolved}, check)
    print(f"Maintenance: {len(profiles)} profiles, {sum(p['regular_allowed'] for p in profiles)} repairable, {len(unresolved)} incomplete costs, {len(items)} original repair tools")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
