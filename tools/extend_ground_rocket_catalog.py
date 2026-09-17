"""Restore two ordinary rockets explicitly referenced by manufacturing and dismantling tables."""
import json
import re
from build_equipment_processing_rules import ROOT, SOURCE
from build_extra_attribute_rules import source_classes, inherited


def main():
    path = ROOT / "data/gameplay/official_rocket_items_v1.json"
    document = json.loads(path.read_text(encoding="utf-8"))
    original = (SOURCE / "cltobj/fireguncltclass.fcc").read_text(encoding="utf-8-sig")
    classes = source_classes()
    available = {r["logical_id"] for r in json.loads((ROOT / "data/content/glory_sprite_runtime_index_v1.json").read_text(encoding="utf-8"))["sprites"]}
    document["definitions"] = [r for r in document["definitions"] if r["id"] not in ["official_rocket_firegun_8", "official_rocket_firegun_9"]]
    for number in [8, 9]:
        name = "FireGun" + str(number)
        match = re.search(r"^class " + name + r":.*?(?=^class |\Z)", original, re.M | re.S)
        body = re.sub(r"//[^\n]*", "", match[0])
        properties = dict(re.findall(r"\b(m_\w+)\s*=\s*([^;\n]+);", body))
        def number_property(field): return int(properties[field])
        stats = {new: number_property(old) for new, old in {
            "required_skill_level": "m_nSkillLevel", "purchase_value": "m_nWorth", "sell_value": "m_nSell",
            "weight": "m_nweight", "base_attack": "m_nattack", "attack_limit": "m_nattackUL",
            "working_energy_per_shot": "m_nenergy", "minimum_range": "m_nMinDistance", "range": "m_nMaxDistance",
            "max_durability": "m_nMax_Hardiness"}.items()}
        stats["attack_interval_seconds"] = int(inherited(classes, name, r"m_nacttime\s*=\s*(\d+)")[1]) / 1000
        stats["legacy_properties"] = {k: v.strip() for k, v in properties.items() if not k.startswith("m_sz") or k in ["m_szRepairHardinessBagClassname", "m_szRepairHardinessBagAmount"]}
        presentation = {}
        for usage, suffix in [("inventory", 1), ("dialog", 2), ("world", 1)]:
            logical = f"pic3/equip/body/firegun{number}-{suffix}"
            assert logical in available, logical
            presentation[usage] = {"ale_reference": "../" + logical + ".ale", "frame": 0}
        document["definitions"].append({"id": f"official_rocket_firegun_{number}", "kind": "rocket_weapon",
            "display_name": properties["m_sObjName"].strip('"'), "description": properties["m_sDesc"].strip('"'),
            "max_stack": 1, "equipment_location": 13, "stats": stats, "presentation": presentation,
            "source_class": name, "source_audit": {"source_release": "starhome_lz_ry",
            "source_file": "cltobj/fireguncltclass.fcc", "source_line": original[:match.start()].count("\n") + 1}})
    path.write_text('{\n  "schema_version": 1,\n  "definitions": [\n' + ',\n'.join(
        '    ' + json.dumps(row, ensure_ascii=False, separators=(',', ':')) for row in document['definitions']) + '\n  ]\n}\n', encoding="utf-8")
    print("Restored FireGun8/9 with existing Glory sprites")


if __name__ == "__main__":
    main()
