"""Compile the audited Glory crystal-source system and extract its local original icons."""
import argparse
import hashlib
import io
import json
from collections import defaultdict

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, read, write


def build(check=False):
    ensure_crystal_mines(check)
    equipment = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    profiles = []
    # Original GetNewEquip* formulas; tier break occurs after level ten.
    parts = [
        ("shan", 28, "max_health", 300, [30, 40], [20, 30], "industrial_material_3f3f3c3d9d8d", "item:material:7df65e194766", "item:material:0465103df5d2"),
        ("li", 29, "energy_cannon_attack", 20, [4, 5], [3, 4], "industrial_material_cfb4093a1ef4", "item:material:5773d6d74168", "item:material:6ac284bb6c59"),
        ("huo", 30, "rocket_attack", 25, [5, 6], [4, 5], "industrial_material_08713a2f8c65", "item:material:a55a9a5d270a", "item:material:d6e5deb49f86"),
        ("ji", 31, "missile_attack", 15, [3, 4], [2, 3], "industrial_material_2830485bb462", "item:material:390575d3e7c8", "item:material:f5ec2ce95368"),
    ]
    source = (SOURCE / "cltobj/equipclt.fcc").read_text(encoding="utf-8-sig")
    offers = []
    for suffix, location, attr, base, quality, growth, crystal, normal, advanced in parts:
        for prefix in ["NewEquip_", "TNewEquip_"]:
            classname = prefix + suffix
            assert "class " + classname + ":" in source
            row = next(r for r in equipment if r.get("source_class") == classname)
            profiles.append({"definition_id": row["id"], "location": location, "attribute": attr,
                             "base": base, "quality_steps": quality, "growth_steps": growth,
                             "crystal_id": crystal, "source_id": normal, "advanced_source_id": advanced,
                             "bound": prefix.startswith("T"), "source_class": classname})
            if prefix == "NewEquip_": offers.append({"definition_id": row["id"], "unit_price": 50000})
    decoder = indexed.load_decoder()
    manifests = defaultdict(list)

    def icon(logical, directory, filename):
        original = ROOT.parent / "starhome_lz_ry_full/raw" / logical
        ale = decoder.AleFile(original)
        assert len(ale.frames) == 1
        frame = ale.decode_frame(ale.frames[0])
        buffer = io.BytesIO()
        frame.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/crystal_source" / directory / (filename + ".png")
        if check:
            assert target.read_bytes() == buffer.getvalue(), target
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(buffer.getvalue())
        audit = {"source_release": "starhome_lz_ry", "source_path": logical,
                 "sha256": hashlib.sha256(original.read_bytes()).hexdigest()}
        manifests[directory].append({"file": target.name, "native_size": list(frame.size), **audit})
        return {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)}, audit

    items, cores = [], []
    for code, color, label, attr, step in [(2, "red", "红", "energy_cannon_attack", 4),
                                           (3, "yellow", "黄", "max_health", 20),
                                           (4, "black", "黑", "missile_attack", 3)]:
        for level in range(1, 6):
            item_id = f"crystal_source_core_{color}_{level}"
            presentation, audit = icon(f"pic3/stuff/RYSJRime{code}{level}.ale", color, f"level_{level}")
            items.append({"id": item_id, "kind": "crystal_source_core", "display_name": f"{level}级{label}色晶源核",
                          "description": "专用于晶源体。每件同色限一枚；摘取增加裂纹，三裂再摘会损毁。五枚同色同级可向上合成，最高5级。",
                          "max_stack": 999, "presentation": presentation, "source_audit": audit})
            cores.append({"definition_id": item_id, "color": color, "level": level, "attribute": attr, "bonus": step * level})
            if level == 1: offers.append({"definition_id": item_id, "unit_price": 5000})
    presentations = {}
    for item_id, classname, filename, name, price, description in [
        ("crystal_source_core_stabilizer", "JYHStabilizer", "core_stabilizer", "晶源核稳定剂", 2000, "每个增加晶源核合成成功率10个百分点，最高100%。"),
        ("crystal_source_quality_stabilizer", "CrystalStabilizer", "quality_stabilizer", "水晶稳定剂", 5000, "晶源体品质3级起使用，失败防止品质退级；仍消耗本次材料。"),
        ("item:material:f6487f0e04b8", "ColourfulCrystal", "five_color_crystal", "五彩水晶", 100, ""),
        ("item:material:920f37756918", "MorColourfulCrystal", "seven_color_crystal", "七彩水晶", 500, ""),
    ]:
        presentation, audit = icon(f"pic3/stuff/{classname}.ale", "materials", filename)
        if description:
            items.append({"id": item_id, "kind": "material", "display_name": name, "description": description,
                          "max_stack": 999, "presentation": presentation, "source_audit": audit})
        else:
            presentations[item_id] = presentation
        offers.append({"definition_id": item_id, "unit_price": price})
    for directory, frames in manifests.items():
        write(f"assets/items/crystal_source/{directory}/manifest.json", {"source_release": "starhome_lz_ry", "frames": frames}, check)
    write("data/presentation/crystal_source_materials_v1.json", {"schema_version": 1, "definitions": presentations}, check)
    write("data/gameplay/crystal_source_items_v1.json", {"schema_version": 1, "definitions": items}, check)
    write("data/gameplay/crystal_source_rules_v1.json", {
        "schema_version": 1, "required_level": 400, "maximum_level": 15, "equipment": profiles, "cores": cores,
        "core_stabilizer_id": "crystal_source_core_stabilizer", "quality_stabilizer_id": "crystal_source_quality_stabilizer",
        "five_color_id": "item:material:f6487f0e04b8", "seven_color_id": "item:material:920f37756918",
        "crystal_costs": [200,200,200,300,300,300,400,400,400,500,500,600,600,700,700],
        "five_color_costs": [10,10,10,10,10,20,20,20,20,20,30,30,30,40,40],
        "seven_color_costs": [30,30,30,40,40],
        "source_costs": [2,4,6,8,10,12,14,16,18,20,20,20,30,30,40],
        "advanced_source_costs": [5,5,10,10,20],
        "quality_failure_levels": [0,1,2,2,3,4,5,5,5,5,5,5,5,0,0],
        "quality_chances": [1,1,1,.9,.85,.8,.75,.7,.65,.6,.55,.5,.45,.4,.35],
        "growth_chance": 1.0, "core_chances": [.6,.5,.4,.3], "offers": offers,
        "source": "Glory equipclt 5690-6902; globalfunclt 9008-9110; FormClass_ven 46737-47030,48600-49278,49743-51538; stuffclt2 39224-39309,42639-42780",
        "remake_policy": "Body quality chances and guaranteed growth are explicit remake values; workshop sells four non-gift bodies, level-one cores, stabilizers and colored crystals at configured coin prices. Normal and advanced crystal sources retain existing monster drops; refined crystals retain mining/refining. Core synthesis consumes all five inputs and stabilizers on failure, retains maximum input cracks on success, and propagates binding. Compatible cores can stack to 999. Seven-color cost uses the original actual material-check branch, differing from its display branch.",
    }, check)
    print(f"Crystal source: {len(profiles)} profiles, {len(cores)} cores, 19 original icons")


def ensure_crystal_mines(check):
    """Keep 300-level crystal ore obtainable on the existing 300-level mining maps."""
    document = read("data/gameplay/mining_v1.json")
    placements = {"glory_mineral_0f7843d5e272": "d08", "glory_mineral_f8b0d6ec51a5": "d08",
                  "glory_mineral_4f96977fb953": "c08", "glory_mineral_9c533145ffbe": "c08"}
    for mineral_id, coordinate in placements.items():
        for world in ["bl", "bt"]:
            policy = document["maps"][f"glory_nft_{world}_{coordinate}"]
            assert policy["enabled"]
            exists = any(row["mineral_id"] == mineral_id for row in policy["mineral_pool"])
            if check: assert exists, f"Missing crystal mine: {world}/{coordinate}/{mineral_id}"
            elif not exists:
                policy["mineral_pool"].append({"mineral_id": mineral_id, "weight": 1.0})
                policy["crystal_source_supply"] = "复刻P5：300级四色水晶矿加入同级既有矿池；原版刷新地点未确认"
    if not check:
        (ROOT / "data/gameplay/mining_v1.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
