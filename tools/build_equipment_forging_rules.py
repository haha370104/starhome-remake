"""Recover PVE-relevant equipment forging caps; server step sizes are explicit remake policy."""
import argparse
import hashlib
import io
import re
import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, STARTERS, read, write
from build_extra_attribute_rules import source_classes
from build_equipment_memory_rules import method_body
from build_equipment_strengthening_rules import lineage, code_only

ATTRIBUTES = {1: ("max_health", "生命上限", 10), 2: ("drive", "推进上限", 1),
              3: ("output_power", "输出上限", 1), 4: ("range", "射程上限", 1),
              5: ("base_attack", "能量炮攻击", 1), 6: ("ammunition_capacity", "载弹上限", 10),
              7: ("range", "火箭射程", 1), 8: ("base_attack", "副武器攻击上限", 1)}
MATERIALS = {1: "镭铬合金", 2: "钡镁合金", 3: "锆钪合金", 4: "钡镁合金",
             5: "锌钛合金", 6: "锆钪合金", 7: "镍铱合金", 8: "镭铬合金"}


def build(check=False):
    classes = source_classes()
    text = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', text.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {r["id"]: r for p in paths if not p.endswith("equipment_forging_items_v1.json") for r in read(p)["definitions"]}
    by_name = {r["display_name"]: r for r in definitions.values()}
    source_materials = (SOURCE / "cltobj/stuffclt2.fcc").read_text(encoding="utf-8-sig")
    sprites = {r["logical_id"] for r in read("data/content/glory_sprite_runtime_index_v1.json")["sprites"]}
    supplies = []
    for name, semantic in [("锆钪合金", "zirconium_scandium"), ("镍铱合金", "nickel_iridium")]:
        if name in by_name: continue
        match = re.search(r"^class " + name + r":.*?(?=^class |\Z)", source_materials, re.M | re.S)
        logical = re.search(r'src=\$\+"../([^"\n]+)"', match[0])[1].lower().removesuffix(".ale")
        assert logical in sprites
        item = {"id": "forging_" + semantic + "_alloy", "kind": "material", "display_name": name,
                "source_class": name, "max_stack": 999, "description": "装备锻造所需合金，可在锻造页购买。",
                "workshop_unit_price": int(re.search(r"m_nWorth\s*=\s*(\d+)", match[0])[1]),
                "presentation": {"ale_reference": logical}, "source_audit": {"source_release": "starhome_lz_ry",
                "source_file": "cltobj/stuffclt2.fcc", "source_line": source_materials[:match.start()].count("\n") + 1,
                "remake_policy": "workshop sale supplies missing material chain; stack cap 999"}}
        supplies.append(item)
        by_name[name] = item
    ordinary = {r["definition_id"] for r in read("data/gameplay/equipment_processing_rules_v1.json")["equipment"]}
    equipment = []
    for row in definitions.values():
        name = STARTERS.get(row["id"], row.get("source_class", ""))
        if row["id"].startswith("official_rocket_firegun_"): name = "FireGun" + row["id"].rsplit("_", 1)[1]
        chain = list(lineage(classes, name))
        body = "\n".join(code_only(classes[c]["body"]) for c in chain)
        if row["id"] not in ordinary or any("space" in c.lower() for c in chain) or name in ["tank14_FT", "gun14_FT", "engine14_FT", "Missile9_FT"]: continue
        if re.search(r"\bm_nCanForging\b|\bm_nEquipKind3\s*=\s*1\s*;", body): continue
        method = method_body(classes, name, "IsMaxCalcinedNum")
        channels = {}
        for kind, part in re.findall(r"case\s+(\d+)\s*:(.*?)(?=case\s+\d+\s*:|\Z)", method, re.S):
            kind = int(kind)
            limit = re.search(r"if\s*\(\s*m_n\w+\s*>=\s*(\d+)\s*\)\s*return\s+(\d+)", part)
            if kind not in ATTRIBUTES or not limit: continue
            assert limit[1] == limit[2]
            channels[str(kind)] = int(limit[1])
        if channels: equipment.append({"definition_id": row["id"], "source_class": name, "limits": channels})
    strings = dict(re.findall(r'^#define\s+(VEN_CALCINED_EQ_\d+)\s+"([^"\n]*)"', (SOURCE / "great/code_string.fcc").read_text(encoding="utf-8-sig"), re.M))
    material_source = (SOURCE / "ven/stuffclt2_ven.fcc").read_text(encoding="utf-8-sig")
    definitions, manifest, channels = [], [], []
    for kind, (attribute, label, step) in ATTRIBUTES.items():
        found = re.search(r"class (CalcinedChip_\w+):.*?\bm_nCalcinedType\s*=\s*" + str(kind) + r"\s*;", material_source, re.S)
        # Restrict to the nearest class preceding the exact type declaration.
        start = material_source.rfind("class ", 0, found.end())
        body = material_source[start:found.end()]
        classname = re.search(r"class (\w+):", body)[1]
        logical = re.search(r'src=\$\+"../([^"\n]+)"', body)[1]
        raw = ROOT.parent / "pve_forging_asset_review/fr/raw" / logical
        ale = indexed.load_decoder().AleFile(raw)
        assert len(ale.frames) == 1
        frame = ale.decode_frame(ale.frames[0])
        image = io.BytesIO(); frame.save(image, format="PNG", optimize=True)
        target = ROOT / "assets/items/equipment_forging" / (classname.removeprefix("CalcinedChip_").lower() + ".png")
        if check: assert target.read_bytes() == image.getvalue()
        else:
            target.parent.mkdir(parents=True, exist_ok=True); target.write_bytes(image.getvalue())
        audit = {"source_release": "starhome_lz_fr", "source_class": classname, "source_path": logical,
                 "url": "http://update.ftxjjy.com/gameser/fr_www/" + logical, "sha256": hashlib.sha256(raw.read_bytes()).hexdigest()}
        manifest.append({"file": target.name, **audit})
        definition_id = "equipment_forging_" + classname.removeprefix("CalcinedChip_").lower()
        definitions.append({"id": definition_id, "kind": "equipment_forging_material", "forging_type": kind,
                            "display_name": strings[re.search(r"m_sObjName=(\w+)", body)[1]],
                            "description": strings[re.search(r"m_sDesc=(\w+)", body)[1]],
                            "max_stack": 999, "workshop_unit_price": 20,
                            "presentation": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)}, "source_audit": audit})
        channels.append({"type": kind, "attribute": attribute, "label": label, "step": step,
                         "direct_bonus": kind in [5, 7], "expands_processing": kind != 7,
                         "material_id": definition_id, "requirements": [{"definition_id": by_name[MATERIALS[kind]]["id"], "quantity": 100}]})
    write("assets/items/equipment_forging/manifest.json", {"source_release": "starhome_lz_fr", "frames": manifest}, check)
    write("data/gameplay/equipment_forging_items_v1.json", {"schema_version": 1, "definitions": definitions + supplies}, check)
    write("data/gameplay/equipment_forging_rules_v1.json", {"schema_version": 1, "currency_cost": 100000,
          "chances": [0.25, 0.60, 0.95], "channels": channels,
          "source": "ven/SynthesizeNPC.fcc EquipCalcinedNPC; ven/SynthesizeWnd.fcc; inherited IsMaxCalcinedNum and Get*UL",
          "remake_policy": "Step sizes: health and ammunition 10, all others 1; failure reduces selected extension by one step to a minimum of zero. Every attempt clears ordinary processing as warned by original UI; other growth retained. Magazine clamps down only when capacity shrinks. No free resources or experience. Chips sold at original Worth=20; server increment distribution unavailable.",
          "pending_pve_scope": "stealth magazine, missile locking radius and radar detection depend on P4 target-scope audit; not enabled without actual combat consumers",
          "equipment": sorted(equipment, key=lambda r: r["definition_id"])}, check)
    print(f"Forging: {len(equipment)} ordinary equipment, {len(channels)} PVE channels")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
