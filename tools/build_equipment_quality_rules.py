"""Recover ordinary equipment quality bonuses and explicit dismantling outcomes from Glory."""
import argparse
import re

from build_equipment_processing_rules import read, write, ROOT
from build_extra_attribute_rules import source_classes
from build_equipment_memory_rules import method_body


def build(check=False):
    classes = source_classes()
    text = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', text.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {r["id"]: r for p in paths for r in read(p)["definitions"]}
    by_name, by_class, profiles = {}, {}, []
    for row in sorted(definitions.values(), key=lambda r: r["id"], reverse=True):
        by_name[row["display_name"]] = row
    for name in ["iron_piece", "copper_piece", "low_grade_gel", "low_grade_energy_catalyst", "low_grade_biosilicon", "low_grade_quadruped_shell"]:
        if name in definitions: by_name[definitions[name]["display_name"]] = definitions[name]
    for row in definitions.values():
        name = row.get("source_class", "")
        if row["id"].startswith("official_rocket_firegun_"): name = "FireGun" + row["id"].rsplit("_", 1)[1]
        if name: by_class[name] = row
        method = method_body(classes, name, "OnInitEx")
        bonuses = {}
        for attr, values in re.findall(r"m_sz(\w+)QualityAdd\s*=\s*\(([^)]+)\)", method):
            assert attr in ["attack", "health", "outpower", "drive"]
            values = [int(v.strip()) for v in values.split(",")]
            assert len(values) == 4 and values[0] == 0 and all(v >= 0 for v in values)
            bonuses[{"attack": "base_attack", "health": "max_health", "outpower": "output_power", "drive": "drive"}[attr]] = values
        if bonuses:
            profiles.append({"definition_id": row["id"], "source_class": name, "bonuses": bonuses})
    dismantle, unavailable = [], []
    for row in read("data/gameplay/glory/glory_recipes_v1.json")["groups"]["equipment_dismantle"]:
        if row["ProductClass"] not in by_class:
            unavailable.append({"source_class": row["ProductClass"], "reason": "equipment definition not registered"})
            continue
        item = by_class[row["ProductClass"]]
        probabilities = [int(v) / 100 for v in row["Probability"].split()]
        groups = row["GetStuff"].split("|")
        assert len(groups) == len(probabilities) == 4 and sum(probabilities) == 1
        outcomes = []
        for probability, group in zip(probabilities, groups):
            materials = []
            for part in group.split("&") if group else []:
                name, count = part.split("@")
                assert name in by_name, name
                materials.append({"definition_id": by_name[name]["id"], "quantity": int(count)})
            outcomes.append({"probability": probability, "materials": materials})
        dismantle.append({"definition_id": item["id"], "source_class": row["ProductClass"],
                          "minimum_quality": int(row["LowestQuality"]), "outcomes": outcomes})
    write("data/gameplay/equipment_quality_rules_v1.json", {"schema_version": 1,
          "source": "cltobj/equipcltclass.fcc, appendequipcltclass.fcc, fireguncltclass.fcc inherited OnInitEx",
          "manufacturing_chances": [0.8, 0.15, 0.04, 0.01],
          "remake_policy": "Quality chances are remake defaults; original server probabilities unavailable. Existing and purchased equipment remains white. Only manufacturing eligible ordinary equipment rolls quality; quality bonuses are original fixed additions and never processing points.",
          "equipment": sorted(profiles, key=lambda r: r["definition_id"])}, check)
    write("data/gameplay/equipment_dismantle_rules_v1.json", {"schema_version": 1, "currency_cost": 200,
          "minimum_free_slots": 3, "source": "wk/Interface.fcc DismemberEquipWnd; glory_recipes_v1 equipment_dismantle",
          "interpretation": "Probability and GetStuff columns are paired in original order, including first empty outcome. Equipment and all attached growth/crystals are consumed. Bound equipment yields bound materials (remake anti-laundering rule). All outcomes must fit before random roll.",
          "equipment": dismantle, "unavailable": unavailable}, check)
    print(f"Ordinary quality: {len(profiles)} equipment; dismantling: {len(dismantle)}; unavailable: {len(unavailable)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
