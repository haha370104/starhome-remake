"""Recover equipped generator base abilities; keep server-only trigger policy explicit."""
import argparse
import re
from build_equipment_processing_rules import ROOT, SOURCE, read, write


def build(check=False):
    source = (SOURCE / "globalfunclt.fcc").read_text(encoding="utf-8-sig")
    constants = (SOURCE / "great/wk_great.fcc").read_text(encoding="utf-8-sig")
    constants = {name: int(value) for name, value in re.findall(r"^#define\s+(\w+)\s+(\d+)", constants, re.M)}
    source = source.split("var GetSubGunAttribute(", 1)[1].split("return szValue;", 1)[0]
    values = {}
    for kind, block in re.findall(r"^\t{3}case (\d+):(.*?)(?=^\t{3}case |\Z)", source, re.M | re.S):
        # Only the zero-upgrade arm is in this base-ability stage, never its later quality tiers.
        block = block.split("case 1:", 1)[0]
        fields = {}
        for index, expression in re.findall(r"szValue\[(\d+)\]\s*=\s*(\w+)\s*;", block):
            fields[int(index)] = int(expression) if expression.isdigit() else constants[expression]
        values[int(kind)] = fields
    equipment = []
    old = {"gaoregun": (0.03, 5, 17, 0, 0, 0), "fushigun": (0.04, 4, 0, 0.35, 0, 0),
           "cihuagun": (0.05, 5, 0, 0, 0.28, 3)}
    for row in read("data/gameplay/glory/glory_items_v1.json")["definitions"]:
        if row.get("equipment_location") != 14: continue
        name = row["source_class"]
        legacy = row["stats"]["legacy_properties"]
        profile = {"definition_id": row["id"], "source_class": name,
                   "label": re.sub(r"\\#[0-9a-fA-F]{6}", "", row["display_name"]),
                   "working_energy_cost": int(legacy.get("m_nenergy", 0)),
                   "cooldown_seconds": int(legacy.get("m_nacttime", 0)) / 1000,
                   "chance": 0, "duration_seconds": 0, "heat_damage": 0,
                   "defense_flat_reduction": 0, "defense_percent_reduction": 0,
                   "attack_percent_reduction": 0, "energy_attack_percent_reduction": 0,
                   "max_health": 0, "defense": 0, "energy_cannon_attack": 0}
        if name.lstrip("T") in old:
            chance, duration, heat, defense, attack, cooldown = old[name.lstrip("T")]
            profile.update(chance=chance, duration_seconds=duration, heat_damage=heat,
                           defense_percent_reduction=defense, attack_percent_reduction=attack,
                           cooldown_seconds=cooldown)
            profile["label"] = {"gaoregun": "高热发生器", "fushigun": "腐蚀发生器", "cihuagun": "磁化发生器"}[name.lstrip("T")] + ("（赠）" if name.startswith("T") else "")
        elif name == "FireSubGun":
            profile["energy_cannon_attack"] = int(legacy["m_nAddEGAttack"])
        else:
            v = values[int(legacy["m_nNewSubGunKind"])]
            profile.update(chance=v.get(2, 0) / 100, duration_seconds=v.get(3, 0),
                           heat_damage=v.get(4, 0), defense_flat_reduction=v.get(5, 0),
                           energy_attack_percent_reduction=v.get(6, 0) / 100,
                           max_health=v.get(0, 0), defense=v.get(1, 0), energy_cannon_attack=v.get(7, 0))
            if name == "MonarchTSubGun_16": profile["label"] = "紫电级发生器（赠）"
        profile["source_audit"] = row["source_audit"]
        equipment.append(profile)
    document = {"schema_version": 1, "source_release": "starhome_lz_ry",
                "source_files": ["cltobj/appendequipcltclass.fcc:1637-1861", "globalfunclt.fcc:2851-3794", "great/wk_great.fcc:847-889,1444-1483"],
                "remake_policy": {"trigger": "one independent roll per installed generator per accepted energy-cannon hit; misses and killing hits do not activate",
                                  "cost": "consume one round and configured energy only on successful activation; cooldown from activation",
                                  "stacking": "same status uses strongest active value, not sum; refresh never postpones periodic ticks",
                                  "heat": "one tick per second including final second; bypass defense; credited to source player via existing loot and quest pipeline",
                                  "lifecycle": "clear on source unequip, death, disconnect or map exit and target death; not persisted",
                                  "scope": "ordinary magnetic reduction applies to monster attacks; energy-only suppression requires an explicitly verified energy-cannon target channel"},
                "deferred": ["generator grade/quality growth", "new generator cleanse and purple special skills", "unverified NPC energy-weapon identities"],
                "equipment": sorted(equipment, key=lambda p: p["definition_id"])}
    write("data/gameplay/generator_rules_v1.json", document, check)
    print(f"Generator base profiles: {len(equipment)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
