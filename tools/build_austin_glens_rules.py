"""Compile audited Austin growth/rune rules and recover original Glory material icons."""
import argparse
import hashlib
import io
from collections import defaultdict

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, read, write


def build(check=False):
    equipment = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    profiles, offers, items, runes = [], [], [], []
    classes = (SOURCE / "cltobj/stuffclt2.fcc").read_text(encoding="utf-8-sig")
    for suffix, location, effect in [("GH", 24, "mitigation"), ("RY", 25, "pvp_cannon"),
                                     ("JH", 26, "healing"), ("CC", 27, "pvp_missile")]:
        row = next(r for r in equipment if r.get("source_class") == "AustinGlens_" + suffix)
        profiles.append({"definition_id": row["id"], "location": location, "effect": effect})
        offers.append({"definition_id": row["id"], "unit_price": 10000})
    decoder = indexed.load_decoder()
    manifests = defaultdict(list)

    def add_icon(classname, category, name, label, description, price):
        assert "class " + classname + ":" in classes, classname
        logical = f"pic3/stuff/{classname}.ale"
        original = ROOT.parent / "starhome_lz_ry_full/raw" / logical
        ale = decoder.AleFile(original)
        frame = ale.decode_frame(ale.frames[0])
        buffer = io.BytesIO()
        frame.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/austin_glens" / category / (name + ".png")
        if check: assert target.read_bytes() == buffer.getvalue(), target
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(buffer.getvalue())
        audit = {"source_release": "starhome_lz_ry", "source_path": logical,
                 "sha256": hashlib.sha256(original.read_bytes()).hexdigest(), "source_frame": 0}
        manifests[category].append({"file": target.name, "native_size": list(frame.size), **audit})
        definition_id = "austin_" + name
        items.append({"id": definition_id, "kind": "material", "display_name": label,
                      "description": description, "max_stack": 99, "source_class": classname,
                      "presentation": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)},
                      "source_audit": audit})
        offers.append({"definition_id": definition_id, "unit_price": price})
        return definition_id

    material_ids = {}
    for classname, name, label, price, use in [
        ("EssenceGM", "light_essence", "光魔精华", 300, "提升奥斯格兰品质颜色"),
        ("OriginalZL", "primal_spirit", "原始之灵", 100, "提升奥斯格兰成长阶段"),
        ("EternalZN", "eternal_energy", "永恒之能", 100, "提升奥斯格兰基础属性"),
        ("MagicHX", "magic_core", "法力核心", 150, "提升奥斯格兰附加属性"),
        ("FireMagicZS", "dispel_stone", "消魔之石", 500, "开启奥斯格兰符文槽或镶入指定符文"),
        ("CHZDSW", "heritage_blessing", "传承祝福圣物", 500, "一次性祝福奥斯格兰装备"),
        ("SpaceCrystal", "space_crystal", "时空水晶", 200, "奥斯格兰各项成长的共用材料"),
    ]:
        material_ids[name] = add_icon(classname, "materials", name, label, use + "。", price)
    for classname, name, label, location, slot, bonus in [
        ("TallyTT", "totem_rune", "图腾符文", 24, 0, {"max_health": 60, "defense": 5}),
        ("TallyNH", "fury_rune", "怒火符文", 24, 1, {"max_health": 20, "missile_attack": 4}),
        ("TallySH", "guardian_rune", "守护符文", 25, 0, {"max_health": 30, "energy_cannon_attack": 4}),
        ("TallyXC", "star_rune", "星辰符文", 25, 1, {"max_health": 30, "self_repair_bonus": 3}),
        ("TallyGH", "halo_rune", "光环符文", 26, 0, {"defense": 4, "self_repair_bonus": 5}),
        ("TallySJ", "holy_rune", "圣洁符文", 26, 1, {"defense": 4, "energy_cannon_attack": 6}),
        ("TallySY", "blessing_rune", "圣佑符文", 27, 0, {"max_health": 50, "energy_cannon_attack": 8}),
        ("TallyTAT", "heaven_rune", "天堂符文", 27, 1, {"max_health": 50, "missile_attack": 8}),
    ]:
        definition_id = add_icon(classname, "runes_left" if slot == 0 else "runes_right", name, label,
                                 "只能镶入对应奥斯格兰装备的指定孔位；镶嵌为永久安装，不能摘取。", 2000)
        runes.append({"definition_id": definition_id, "location": location, "slot": slot, "bonuses": bonus})
    for category, frames in manifests.items():
        write(f"assets/items/austin_glens/{category}/manifest.json", {"source_release": "starhome_lz_ry", "frames": frames}, check)
    write("data/gameplay/austin_glens_items_v1.json", {"schema_version": 1, "definitions": items}, check)
    write("data/gameplay/austin_glens_rules_v1.json", {
        "schema_version": 1, "profiles": profiles, "runes": runes, "materials": material_ids, "offers": offers,
        "color_health": [30, 50, 70, 90], "color_defense": [1, 2, 3, 4], "color_penetration": [1, 1, 2, 2],
        "stage_cannon": [1,2,2,3,3,4,4,5,5,6,6], "stage_missile": [1,1,2,2,3,3,4,4,5,5,6],
        "stage_penetration": [0,1,1,1,1,1,2,2,2,2,2], "base_repair": [0,1,1,1,1,1,2,2,2,2,2],
        "blessing_bonuses": {"max_health": 60, "self_repair_bonus": 2, "energy_cannon_attack": 5, "missile_attack": 5},
        "level_costs": [2,4,8,12,16,20,24,28,32,36], "space_costs": [1,2,2,2,3,3,3,4,4,5],
        "color_costs": [10,20,40], "color_space_costs": [5,10,20], "blessing_cost": 5, "blessing_space_cost": 10,
        "unlock_cost": 4, "inlay_cost": 1, "mitigation": [20,30,40,50,60,70,80,100,120,140,160],
        "healing": [20,30,40,50,60,70,80,100,120,140,180], "trigger_chance": 0.1, "cooldown_seconds": 60,
        "suspended_set_effect": {"enabled": False, "scope": "other_players", "required_locations": [24,25,26,27],
                                 "required_runes": [r["definition_id"] for r in runes], "all_equipment_healthy": True,
                                 "trigger_chance": 0.05, "cannon_attack": 40, "duration_seconds": 8, "cooldown_seconds": 120},
        "source": "Glory equipclt 7371-7758; equipcltclass 13369-13474; globalfunclt 8976-9730; FormClass_ven 46294-47390; stuffclt2 37593-38190",
        "remake_policy": "Workshop supplies bodies at original worth and fifteen materials/runes at remake coin prices; all original upgrades are certain. PVP-only attacks/set effect are deferred and their add-level upgrades disabled. Penetration retains source values without an unproven PVE formula. On a damaging direct monster hit, mitigation follows defense and healing requires survival; ongoing corrosion does not retrigger. No rune extraction.",
    }, check)
    print("Austin Glens: 4 bodies, 8 fixed runes, 7 materials, 15 original icons")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
