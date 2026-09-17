"""Compile the original ten-star vehicle equipment progression independently of joint upgrades."""
import argparse
import hashlib
import io
import re

import audit_monster_asset_sources as indexed
from build_extra_attribute_rules import source_classes
from build_equipment_processing_rules import ROOT, SOURCE, STARTERS, read, write

CACHE = ROOT.parent / "pve_strengthening_asset_review"
FAMILIES = {
    "bodywork": ("chassis", "max_health", [0, 30, 60, 90, 130, 170, 210, 270, 330, 400, 600], "Tank", "硅铁合金"),
    "EnergyGunBase": ("cannon", "base_attack", [0, 2, 4, 7, 10, 14, 18, 22, 27, 32, 55], "Gun", "硅铜合金"),
    "thruster": ("engine", "drive", [0, 2, 4, 6, 9, 12, 15, 20, 25, 30, 50], "Engine", "银钢合金"),
    "MissileBase": ("missile", "base_attack", [0, 1, 3, 5, 8, 11, 15, 19, 23, 28, 45], "Missile", "银铜合金"),
}


def lineage(classes, name):
    seen = set()
    while name in classes and name not in seen:
        seen.add(name)
        yield name
        name = classes[name]["parent"]


def code_only(body):
    """Remove comments while preserving quoted resource paths and expressions."""
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda m: m[0] if m[0].startswith('"') else " " * len(m[0]), body, flags=re.S)


def icon(classname, classes, check):
    body = classes[classname]["body"]
    paths = re.findall(r'\$\+"../([^"\n]+\.(?:ale|act))"', body)
    files = []
    for path in paths:
        choices = [(release, path) for release in ["ry", "fr", "jznp"]]
        if path.startswith("pic3/"): choices.append(("fr", path.replace("pic3/", "pic2/", 1)))
        found = next(((r, p, CACHE / r / "raw" / p) for r, p in choices if (CACHE / r / "raw" / p).exists()), None)
        assert found, (classname, path)
        files.append(found)
    decoder = indexed.load_decoder()
    ale = decoder.AleFile(files[0][2])
    assert len(ale.frames) == 1
    if len(files) > 1:
        palette = files[1][2].read_bytes()
        assert len(palette) in [768, 772], files[1][2]
        colors = [(*palette[offset:offset + 3], 255) for offset in range(0, 768, 3)]
        frame = indexed.apply_palette(indexed.decode_index_alpha(ale, ale.frames[0]), colors)
    else:
        frame = ale.decode_frame(ale.frames[0])
    target = ROOT / "assets/items/strengthening" / (classname.lower() + ".png")
    buffer = io.BytesIO()
    frame.save(buffer, format="PNG", optimize=True)
    if check: assert target.read_bytes() == buffer.getvalue(), target
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(buffer.getvalue())
    return {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)}, [
        {"url": f"http://update.ftxjjy.com/gameser/{release}_www/{path}", "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
        for release, path, file in files]


def build(check=False):
    classes = source_classes()
    source = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', source.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {r["id"]: r for path in paths if not path.endswith("equipment_strengthening_items_v1.json") for r in read(path)["definitions"]}
    originals = {r.get("source_class"): r for r in read("data/gameplay/glory/glory_items_v1.json")["definitions"]}
    by_name = {r["display_name"]: r["id"] for r in definitions.values()}
    words = "\n".join(path.read_text(encoding="utf-8-sig") for path in (SOURCE / "great").glob("*.fcc"))
    constants = dict(re.findall(r'#define\s+(\w+)\s+"([^"\n]+)"', words))
    equipment = []
    for row in definitions.values():
        original = originals.get(STARTERS[row["id"]], row) if row["id"] in STARTERS else row
        name = original.get("source_class", STARTERS.get(row["id"], ""))
        chain = list(lineage(classes, name))
        if any("space" in c.lower() for c in chain): continue
        base = next((c for c in chain if c in FAMILIES), None)
        if base is None: continue
        declaration = next((m for c in chain if (m := re.search(r"\bm_nStren_Lvl\s*=\s*(-?\d+)", code_only(classes[c]["body"])))), None)
        if declaration is None or int(declaration[1]) < 0: continue
        family, attribute, values, stone, alloy = FAMILIES[base]
        equipment.append({"definition_id": row["id"], "display_name": row["display_name"], "source_class": name,
                          "family": family, "attribute": attribute, "values": values,
                          "ordinary_material": "strengthening_" + stone.lower() + "_strenstone",
                          "ultimate_material": "strengthening_utmost_" + stone.lower() + "_strenstone",
                          "alloy_id": by_name[alloy]})
    materials = []
    for classname in [prefix + f[3] + "_StrenStone" for prefix in ["", "Utmost_"] for f in FAMILIES.values()] + ["Eff_EquipStrenStone"]:
        body = classes[classname]["body"]
        name = constants[re.search(r"m_sObjName\s*=\s*(\w+)", body)[1]]
        description = constants[re.search(r"m_sDesc\s*=\s*(\w+)", body)[1]]
        presentation, sources = icon(classname, classes, check)
        price = 100000 if classname.startswith("Utmost") else 50000 if classname.startswith("Eff_") else 20000
        materials.append({"id": "strengthening_" + classname.lower(), "kind": "equipment_strengthening_material", "display_name": name,
                          "description": description, "source_class": classname, "max_stack": 999,
                          "presentation": presentation, "workshop_unit_price": price,
                          "source_audit": {"source_file": "cltobj/stuffclt.fcc", "sources": sources, "acquisition": "remake_coin_offer"}})
    write("data/gameplay/equipment_strengthening_items_v1.json", {"schema_version": 1, "definitions": materials}, check)
    write("data/gameplay/equipment_strengthening_rules_v1.json", {"schema_version": 1, "maximum_level": 10,
          "currency": 100000, "alloy_quantity": 300, "ordinary_chances": [0.3, 0.6, 0.9, 1.0],
          "ultimate_chances": [0.12, 0.24, 0.36, 0.48, 0.60, 0.72, 0.84, 0.96, 1.0],
          "ordinary_failure_loss": 1, "ultimate_failure_loss": 2,
          "ultimate_additional_material": "strengthening_eff_equipstrenstone", "ultimate_additional_quantity": 2,
          "source": "ven/OterNPC_C.fcc:1537; equipclt.fcc/appendequipclt.fcc GetStrengthenVal; inherited m_nStren_Lvl exclusions",
          "equipment": sorted(equipment, key=lambda r: r["definition_id"])}, check)
    print(f"Equipment strengthening: {len(equipment)} profiles, {len(materials)} original material icons")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
