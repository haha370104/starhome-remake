"""Compile Free-client bridge chips, evolved core and six Flame accessories.

Raw source numbers and remake scaling remain separate. No PVP skill is enabled.
"""
import argparse
import hashlib
import io
import re

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, write


def build(check=False):
    source = ROOT.parent / "starhome_lz_fr_fcc_source"
    raw = ROOT.parent / "starhome_lz_fr_full/raw"
    global_source = (source / "globalfunclt.fcc").read_text(encoding="utf-8")
    equipment_source = (source / "cltobj/equipcltclass.fcc").read_text(encoding="utf-8")
    material_source = (source / "cltobj/stuffclt2.fcc").read_text(encoding="utf-8")
    decoder = indexed.load_decoder()
    frames, items, modules, chips, profiles, offers = [], [], [], [], [], []

    def icon(logical, name):
        path = raw / logical
        assert path.is_file(), logical
        ale = decoder.AleFile(path)
        frame = ale.frames[0]
        bitmap = ale.decode_frame(frame)
        buffer = io.BytesIO()
        bitmap.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/central" / (name + ".png")
        if check:
            assert target.read_bytes() == buffer.getvalue(), target
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(buffer.getvalue())
        frames.append({"file": target.name, "source_release": "free", "source_path": logical,
                       "source_frame": 0, "native_size": list(bitmap.size),
                       "offset": [frame.origin_x, frame.origin_y],
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
        return {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(bitmap.size)}

    def material(identifier, classname, label, desc, price, maximum=1, bound=False):
        presentation = icon(f"pic2/stuff/{classname}.ale", identifier)
        items.append({"id": identifier, "kind": "material", "display_name": label,
                      "description": desc, "max_stack": maximum, "bound": bound,
                      "source_class": classname, "presentation": presentation})
        offers.append({"definition_id": identifier, "unit_price": price})

    basic = global_source.split("var GetEquipChipAttr(", 1)[1].split("var GetSpecialEquipChipAttr(", 1)[0]
    special = global_source.split("var GetSpecialEquipChipAttr(", 1)[1].split("\n\t}", 1)[0]
    names = [("tank", "Tank", "战车"), ("engine", "Engine", "引擎"), ("gun", "Gun", "能量炮"),
             ("missile", "Missile", "导弹"), ("armor", "Armor", "护甲"), ("generator", "SubGun", "发生器")]
    for index, (key, cls, label) in enumerate(names, 1):
        block = re.split(r"case\s+" + str(index) + r"://[^\n]*桥接芯片", basic)[1]
        block = block.split("\n\t\t\tcase ", 1)[0]
        numbers = re.findall(r"szValue\[\d+\]\s*=\s*(\d+)", block)
        assert len(numbers) == 9, (key, numbers)
        raw_bonuses = [list(map(int, numbers[i:i + 3])) for i in range(0, 9, 3)]
        effect = re.split(r"case\s+" + str(index) + r"://[^\n]*桥接芯片", special)[1].split("\n\t\t\tcase ", 1)[0]
        effect_values = list(map(int, re.findall(r"szValue\[\d+\]\s*=\s*(\d+)", effect)))
        chips.append({"id": key, "display_name": label + "桥接芯片", "source_kind": index,
                      "original_bonuses": raw_bonuses,
                      "bonuses": [dict(zip(["energy_cannon_attack", "max_health", "defense"], [v // 100 for v in row])) for row in raw_bonuses],
                      "original_effect_values": effect_values,
                      "icon": icon(f"pic2/stuff/{cls}ChipImg.ale", key + "_chip")["icon"]})
        for grade, suffix in [(1, "ChipModule"), (2, "ChipUpTo2"), (3, "ChipModuleUpTo3")]:
            identifier = f"central_{key}_module_{grade}"
            desc = "激活对应桥接芯片。" if grade == 1 else f"将已激活且等级较低的对应芯片提升至{grade}级。"
            material(identifier, cls + suffix, label + ("桥接模块" if grade == 1 else f"桥接模块（{grade}级）"), desc, [20000, 100000, 250000][grade - 1], bound=True)
            if grade == 2: items[-1]["source_class"] = cls + "ChipModuleUpTo2"
            modules.append({"definition_id": identifier, "chip_id": key, "target_grade": grade})

    material("central_evolution_crystal", "ZSHDCrystal", "中枢进化晶体", "六类桥接芯片全部达到3级后，进化中枢核心。每个角色仅可进化一次。", 500000)
    growth_materials = []
    for classname, name, price in [("SYancrystal", "圣焱核晶", 5000), ("SYanOriginiums", "圣焱源石", 10000),
                                   ("SYanQuantum", "圣焱量子", 20000), ("SYanSuccinct", "圣焱精粹", 40000),
                                   ("SYanJingYuan", "圣焱精源", 80000), ("SYanJingHe", "圣焱精核", 160000)]:
        block = material_source.split("class " + classname + ":", 1)[1].split("\nclass ", 1)[0]
        desc = re.search(r'm_sDesc="([^"]+)"', block)[1]
        identifier = "central_" + classname.lower()
        material(identifier, classname, name, desc, price, maximum=20)
        growth_materials.append(identifier)

    increments_block = global_source.split("int PivotControlEquipAttr(", 1)[1].split("\n\t}", 1)[0]
    increments = list(map(int, re.findall(r"szInfo\[0\]\s*=\s*(\d+)", increments_block)))
    assert len(increments) == 19
    for index, classname in enumerate(["FlameLight", "FlamePower", "FlameWoods", "FlameWind", "FlameMountain", "FlameFire"]):
        block = equipment_source.split("class " + classname + ":", 1)[1].split("\nclass ", 1)[0]
        name = re.search(r'm_sObjName\s*=\s*"([^"]+)"', block)[1]
        health = int(re.search(r"m_nPivothealth=(\d+)", block)[1])
        attack = int(re.search(r"m_nPivotattack=(\d+)", block)[1])
        identifier = "central_" + classname.lower()
        visuals = []
        tiers = [(0, f"pic2/equip/bag/{classname}_bag.ale")]
        tiers += [(int(grade), logical) for grade, logical in re.findall(
            r'm_nPivotgrade>=(\d+)\)\s*\{\s*m_sBaseSrc=\$\+"../([^"]+)"', block)]
        for grade, logical in sorted(tiers):
            visuals.append({"grade": grade, **icon(logical, identifier + f"_{grade}")})
        items.append({"id": identifier, "kind": "vehicle_equipment", "display_name": name,
                      "description": "圣焱型中枢附属装备；需进化中枢方可装配。常驻属性用于PVE；六件套玩家战斗技能暂缓。",
                      "max_stack": 1, "source_class": classname, "equipment_location": 40 + index,
                      "equip_kind": 114, "stats": {"durability": 1, "max_durability": 1, "weight": 0},
                      "presentation": {k: visuals[0][k] for k in ["icon", "native_size"]}})
        profiles.append({"definition_id": identifier, "source_location": 33 + index, "location": 40 + index,
                         "original_base": {"max_health": health, "energy_cannon_attack": attack, "missile_attack": attack},
                         "base": {"max_health": health // 100, "energy_cannon_attack": attack // 100, "missile_attack": attack // 100},
                         "visuals": visuals})
        offers.append({"definition_id": identifier, "unit_price": 100000})
    write("assets/items/central/manifest.json", {"frames": frames}, check)
    write("data/gameplay/central_items_v1.json", {"schema_version": 1, "definitions": items}, check)
    write("data/gameplay/central_rules_v1.json", {
        "schema_version": 1, "chips": chips, "modules": modules, "profiles": profiles, "offers": offers,
        "growth_materials": growth_materials, "original_health_increments": increments,
        "health_increments": [n // 100 for n in increments], "attack_increments": [n // 1000 for n in increments],
        "evolution_material": "central_evolution_crystal",
        "evolution_bonus": {"max_health": 2000, "energy_cannon_attack": 120, "defense": 110},
        "fatal_chance_percent": [3, 5, 7], "fatal_current_health_percent": 90, "fatal_damage_cap_multiplier": 5,
        "suspended_effects": ["致命抵抗", "电磁干扰", "制导打击", "集中防御", "异变打击", "核之守护"],
        "suspended_set_effects": [{"minimum_grade": g, "name": n, "enabled": False, "target": "player"} for g, n in
                                  zip([3, 6, 9, 12, 15, 18], ["圣焱苍穹", "圣焱耀光", "圣焱降临", "神圣之言", "圣焱星落", "圣焱星爆"])],
        "source": "Free globalfunclt 7332/7477/18138; ven/stuffclt_ven 4884; mainclient_char 15748; cltobj/equipcltclass 13265; ven/FormClass_ven 55016; menupart_main 18401; Glory npcbasecltmain 337 OnFatalBlow",
        "remake_policy": "All permanent attributes /100. Original no-durability Flame equipment uses separate remake slots 40..45 (source 33..38 conflicts with confirmed joint/generator slots). One module sets any already-active lower chip grade to its target (server gate unknown); one material per guaranteed Flame stage. Fatal: first valid cannon contact per accepted shot, original 3/5/7% and 90% current HP, capped at 5x ordinary hit damage for all monsters. Coin supply is remake until P7 activities. PVP effects deferred.",
    }, check)
    print(f"Central: {len(chips)} chips, {len(items)} items, {len(profiles)} accessories, {len(frames)} source frames")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
