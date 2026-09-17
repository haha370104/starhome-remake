"""Compile original electrical-wave armor refinement and its exact material sprites."""
import argparse
import hashlib
import io
import re

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, read, write
from build_extra_attribute_rules import source_classes
from build_equipment_strengthening_rules import lineage, code_only, CACHE

MATERIALS = [("ComsShipArmor", "chip", 0, 10000), ("FrontArmorStone", "front_stone", 5, 50000),
             ("BackArmorStone", "back_stone", 6, 50000), ("LeftArmorStone", "left_stone", 7, 50000),
             ("RightArmorStone", "right_stone", 8, 50000)]


def build(check=False):
    classes = source_classes()
    definitions = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    by_class = {row.get("source_class"): row for row in definitions}
    words = "\n".join(p.read_text(encoding="utf-8-sig") for p in (SOURCE / "great").glob("*.fcc"))
    constants = dict(re.findall(r'#define\s+(\w+)\s+"([^"\n]+)"', words))
    profiles = []
    for row in definitions:
        name = row.get("source_class", "")
        body = "\n".join(code_only(classes[c]["body"]) for c in lineage(classes, name))
        def number(field):
            found = re.search(r"\b" + field + r"\s*=\s*(-?\d+)", body)
            return int(found[1]) if found else None
        if number("m_nExArmorUpgrade") != 1:
            continue
        level, location = number("m_nArmorLevel"), number("m_nLocation")
        assert level in range(1, 9) and location in range(5, 9), name
        next_class = ["Front", "Back", "Left", "Right"][location - 5] + f"Armor0{level + 1}"
        profiles.append({"definition_id": row["id"], "level": level, "location": location,
                         "next_definition_id": by_class[next_class]["id"] if level < 8 else "",
                         "gift_bound": name.startswith("T"), "source_class": name})
    materials = []
    for classname, semantic, location, price in MATERIALS:
        body = classes[classname]["body"]
        logical = re.search(r'src\s*=\$\+"../([^"]+)"', body)[1]
        variants = [(r, CACHE / r / "raw" / logical) for r in ["ry", "fr", "jznp"]]
        release, source = next((r, p) for r, p in variants if p.is_file())
        hashes = {hashlib.sha256(p.read_bytes()).hexdigest() for _, p in variants if p.is_file()}
        assert len(hashes) == 1, (classname, "cross-release decision required")
        ale = indexed.load_decoder().AleFile(source)
        assert len(ale.frames) == 1
        frame = ale.decode_frame(ale.frames[0])
        buffer = io.BytesIO()
        frame.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/armor_refinement" / (semantic + ".png")
        if check: assert target.read_bytes() == buffer.getvalue(), target
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(buffer.getvalue())
        materials.append({"id": "armor_refinement_" + semantic, "kind": "armor_refinement_material",
                          "display_name": constants[re.search(r"m_sObjName\s*=\s*(\w+)", body)[1]],
                          "description": constants[re.search(r"m_sDesc\s*=\s*(\w+)", body)[1]],
                          "max_stack": 999, "refinement_location": location, "workshop_unit_price": price,
                          "presentation": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)},
                          "source_audit": {"source_class": classname, "source_file": classes[classname]["file"],
                                           "url": f"http://update.ftxjjy.com/gameser/{release}_www/{logical}",
                                           "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                                           "acquisition": "remake_coin_offer"}})
    write("data/gameplay/armor_refinement_items_v1.json", {"schema_version": 1, "definitions": materials}, check)
    write("data/gameplay/armor_refinement_rules_v1.json", {"schema_version": 1, "maximum_level": 8,
          "currency": 0, "chip_chances": [(30 + (n - 1) ** 2) / 100 for n in range(1, 10)] + [1.0],
          "stone_chances": [0.1, 0.3, 0.6, 1.0], "failure": "destroy_equipment",
          "source": "ven/OterNPC_C.fcc:1373; ven/FormClass_ven.fcc:3686; great/yl_great.fcc:258",
          "transition_policy": "remake: same-side next original definition; preserve identity, binding, wear loss and sockets; append closed slots",
          "equipment": sorted(profiles, key=lambda r: r["definition_id"])}, check)
    print(f"Armor refinement: {len(profiles)} profiles, {len(materials)} original icons")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
