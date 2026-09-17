"""Compile exact original memory-module eligibility for growth already supported by the remake."""
import argparse
import hashlib
import io
import re

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, STARTERS, read, write
from build_extra_attribute_rules import source_classes, inherited
from build_equipment_strengthening_rules import lineage, code_only

MODULES = [(1, "UpgradeModule", "processing"), (3, "FluoriteModule", "fluorite"),
           (4, "StoneModule", "brilliant"), (5, "StrenStoneModule", "strengthening"), (6, "RimeModule", "sockets")]


def method_body(classes, name, method):
    """Read a whole inherited method, including nested blocks rather than the first closing brace."""
    for classname in lineage(classes, name):
        body = code_only(classes[classname]["body"])
        found = re.search(r"\b" + method + r"\s*\([^)]*\)\s*\{", body)
        if not found: continue
        start, end, depth = found.end(), found.end(), 1
        while depth and end < len(body):
            depth += (body[end] == "{") - (body[end] == "}")
            end += 1
        assert depth == 0
        return body[start:end - 1]
    return ""


def build(check=False):
    classes = source_classes()
    text = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', text.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {r["id"]: r for p in paths if not p.endswith("equipment_memory_items_v1.json") for r in read(p)["definitions"]}
    processing = {r["definition_id"] for r in read("data/gameplay/equipment_processing_rules_v1.json")["equipment"]}
    stars = {r["definition_id"] for r in read("data/gameplay/equipment_strengthening_rules_v1.json")["equipment"]}
    sockets = {r["definition_id"] for r in read("data/gameplay/vehicle_socket_rules_v1.json")["equipment"]}
    extras = {r["definition_id"]: r["channels"] for r in read("data/gameplay/extra_attribute_rules_v1.json")["equipment"]}
    profiles = []
    for row in definitions.values():
        name = STARTERS.get(row["id"], row.get("source_class", ""))
        if row["id"].startswith("official_rocket_firegun_"): name = "FireGun" + row["id"].rsplit("_", 1)[1]
        chain = list(lineage(classes, name))
        body = "\n".join(code_only(classes[c]["body"]) for c in chain)
        if any("space" in c.lower() for c in chain) or re.search(r"\bm_nCantXi\b", body): continue
        method = method_body(classes, name, "IsCanAbsorb")
        if not method: continue
        def number(field, default):
            found = re.search(r"\b" + field + r"\s*=\s*(-?\d+)", body)
            return int(found[1]) if found else default
        if number("m_nEquipKind3", 0) == 1: continue
        kind, level = number("m_nEquipKind2", -1) + 1, number("m_nSkillLevel", 0)
        if kind not in [1, 2, 3, 6, 7, 9, 10, 11] or level <= 0: continue
        supported = []
        for module_type, _, family in MODULES:
            branch = re.search(r"case\s+" + str(module_type) + r"\s*:(.*?)(?=case\s+\d+\s*:|\Z)", method, re.S)
            if not branch or not re.search(r"nTemp\s*=\s*1", code_only(branch[1])): continue
            enabled = row["id"] in {"processing": processing, "strengthening": stars, "sockets": sockets}.get(family, set())
            if family in ["fluorite", "brilliant"]:
                enabled = any(c.startswith(family + ":") for c in extras.get(row["id"], []))
            if enabled: supported.append(module_type)
        extract = [t for t in supported if number("m_nCanXQType", 0) in [0, t]]
        transfer = [t for t in supported if number("m_nCanZYType", 0) in [0, t]]
        if extract or transfer: profiles.append({"definition_id": row["id"], "kind": kind, "level": level,
                                                "extract_types": extract, "transfer_types": transfer, "source_class": name})
    materials, sources = [], []
    free = (ROOT.parent / "starhome_lz_fr_fcc_source/cltobj/stuffclt.fcc").read_text(encoding="utf-8-sig")
    for module_type, name, semantic in [*MODULES, (0, "DcStableJ", "stabilizer")]:
        body = classes[name]["body"]
        free_body = free.split("class " + name + ":", 1)[1].split("\n}", 1)[0]
        logical = re.search(r'src\s*=\$\+"../([^"\n]+)"', free_body)[1]
        raw = ROOT.parent / "pve_module_asset_review/fr/raw" / logical
        ale = indexed.load_decoder().AleFile(raw)
        assert len(ale.frames) == 1
        frame = ale.decode_frame(ale.frames[0])
        buffer = io.BytesIO()
        frame.save(buffer, format="PNG", optimize=True)
        target = ROOT / "assets/items/equipment_memory" / (semantic + ".png")
        if check: assert target.read_bytes() == buffer.getvalue()
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(buffer.getvalue())
        audit = {"source_release": "starhome_lz_fr", "source_class": name, "source_path": logical,
                 "url": "http://update.ftxjjy.com/gameser/fr_www/" + logical, "sha256": hashlib.sha256(raw.read_bytes()).hexdigest()}
        sources.append({"file": target.name, **audit})
        materials.append({"id": "equipment_memory_" + semantic, "kind": "equipment_memory_module" if module_type else "equipment_memory_stabilizer",
                          "module_type": module_type, "display_name": re.search(r'm_s(?:ModuleName|ObjName)\s*=\s*"([^"\n]+)"', body)[1],
                          "description": re.search(r'm_sDesc\s*=\s*"([^"\n]+)"', body)[1], "max_stack": 1 if module_type else 999,
                          "workshop_unit_price": 20, "presentation": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)}, "source_audit": audit})
    write("assets/items/equipment_memory/manifest.json", {"source_release": "starhome_lz_fr", "frames": sources}, check)
    write("data/gameplay/equipment_memory_items_v1.json", {"schema_version": 1, "definitions": materials}, check)
    write("data/gameplay/equipment_memory_rules_v1.json", {"schema_version": 1, "chance": 0.8, "stabilized_chance": 1.0,
          "source": "ven/OterNPC_C.fcc:2173; ven/FormClass_ven.fcc:8480,9013; inherited IsCanAbsorb/GetEquipAttr",
          "remake_policy": "Successful extraction moves only selected growth; failure consumes empty module. Transfer requires empty matching growth, consumes loaded module on success or failure; target unchanged on failure. Other growth remains. Reject over-cap transfer; no skill-level restriction evidenced. Stabilizer consumes one; no extra fee.",
          "deferred_types": {"2": "energy stone scope pending", "7": "forging maximums not part of implemented ordinary processing"},
          "equipment": sorted(profiles, key=lambda r: r["definition_id"])}, check)
    print(f"Equipment memory: {len(profiles)} eligible equipment, {len(materials)} materials")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
