"""Compile seasonal fashion improvement; distinguish active eligibility from historical bonuses."""
import argparse
import hashlib
import io
import re

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, read, write
from build_extra_attribute_rules import source_classes
from build_equipment_strengthening_rules import lineage

CHANNELS = [("energy_cannon_attack", "能量炮攻击", 1), ("missile_attack", "导弹攻击", 1),
            ("rocket_attack", "火箭炮攻击", 1), ("max_health", "战车生命", 10),
            ("defense", "防御", 1), ("movement_speed", "速度", 0.5), ("self_repair", "自维修", 1)]


def build(check=False):
    classes = source_classes()
    definitions = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    profiles = [{"definition_id": row["id"], "source_class": row["source_class"],
                 "character_slot": "head" if "帽" in row["display_name"] else row["character_slot"]}
                for row in definitions if "Fashion_2009" in lineage(classes, row.get("source_class", ""))]
    assert len(profiles) == 49
    words = "\n".join(p.read_text(encoding="utf-8-sig") for p in (SOURCE / "great").glob("*.fcc"))
    constants = dict(re.findall(r'#define\s+(\w+)\s+"([^"\n]+)"', words))
    source_text = (SOURCE / "ven/stuffclt2_ven.fcc").read_text(encoding="utf-8-sig")
    materials, channels = [], []
    for i, (attribute, label, increment) in enumerate(CHANNELS):
        classname = "BionicFiber" + chr(ord("A") + i)
        body = source_text.split("class " + classname + ":", 1)[1].split("\n};", 1)[0]
        logical = re.search(r'src\s*=\$\+"../([^"\n]+)"', body)[1]
        variants = [(r, ROOT.parent / "pve_fashion_asset_review" / r / "raw" / logical) for r in ["ry", "fr", "jznp"]]
        release, source = next((r, p) for r, p in variants if p.is_file())
        assert len({hashlib.sha256(p.read_bytes()).hexdigest() for _, p in variants if p.is_file()}) == 1
        ale = indexed.load_decoder().AleFile(source)
        assert len(ale.frames) == 1
        frame = ale.decode_frame(ale.frames[0])
        buffer = io.BytesIO()
        frame.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/clothing_improvement" / (attribute + ".png")
        if check: assert target.read_bytes() == buffer.getvalue()
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(buffer.getvalue())
        material_id = "clothing_fiber_" + attribute
        materials.append({"id": material_id, "kind": "clothing_improvement_material",
                          "display_name": constants[re.search(r"m_sObjName\s*=\s*(\w+)", body)[1]],
                          "description": constants[re.search(r"m_sDesc\s*=\s*(\w+)", body)[1]],
                          "max_stack": 9999, "improvement_attribute": attribute, "workshop_unit_price": 20,
                          "presentation": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)},
                          "source_audit": {"source_class": classname, "source_release": "starhome_lz_" + release,
                                           "source_path": logical, "url": f"http://update.ftxjjy.com/gameser/{release}_www/{logical}",
                                           "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                           "acquisition": "remake workshop offer, original m_nWorth=20"}})
        channels.append({"attribute": attribute, "label": label, "increment": increment, "material_id": material_id})
    write("data/gameplay/clothing_improvement_items_v1.json", {"schema_version": 1, "definitions": materials}, check)
    write("data/gameplay/clothing_improvement_rules_v1.json", {"schema_version": 1, "maximum_level": 100,
          "guaranteed_quantities": [2 ** (n + 1) for n in range(20)], "channels": channels,
          "failure": "consume_material_keep_level", "equipment": sorted(profiles, key=lambda r: r["definition_id"]),
          "source": "ven/OterNPC_C.fcc:1809; ven/FormClass_ven.fcc:5683,5761; cltobj/clothcltclass.fcc:7167",
          "bonus_evidence": "cltobj/clothclt.fcc:871-900 historical commented descriptions; adopt flat values only",
          "remake_policy": "Failure consumes fibers and preserves level; no fee; seasonal fashions offered for 10000 coins; no commented ultimate effects"}, check)
    print(f"Clothing improvement: {len(profiles)} fashions, {len(materials)} fibers")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
