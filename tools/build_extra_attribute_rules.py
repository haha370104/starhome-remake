"""Build original fluorite and brilliant-stone rules, preserving exact eligibility and palettes."""
import argparse
import hashlib
import io
import re
from pathlib import Path

import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, STARTERS, read, write

CACHE = ROOT.parent / "pve_advanced_asset_review/fr/raw"
ATTRIBUTES = {1: ("base_attack", 1, 30), 2: ("double_damage_chance", 0.0025, 20),
              3: ("max_health", 15, 30), 4: ("armor", 1, 20), 5: ("movement_speed", 1, 30),
              6: ("base_attack", 1, 30), 7: ("ammunition_capacity", 10, 20)}
CLASSES = {"AttackFluorite": 1, "DeadlinessFluorite": 2, "LifeFluorite": 3, "RecoveryFluorite": 4,
           "RateFluorite": 5, "SpiritFluorite": 6, "BombFluorite": 7,
           "AttackStone": 1, "DeadlinessStone": 2, "LifeStone": 3, "RecoveryStone": 4, "RateStone": 5}


def source_classes():
    """Read original class bodies and their inheritance for methods absent from item JSON."""
    result = {}
    for path in sorted((SOURCE / "cltobj").glob("*.fcc")):
        text = path.read_text(encoding="utf-8-sig")
        mask = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/', lambda m: " " * len(m[0]), text, flags=re.S)
        matches = list(re.finditer(r"(?m)^[ \t]*class\s+([^\s:({]+)\s*:\s*([^\s{]+)", mask))
        for match in matches:
            start = mask.find("{", match.end())
            if start < 0: continue
            depth, end = 1, start + 1
            while end < len(mask) and depth:
                depth += (mask[end] == "{") - (mask[end] == "}")
                end += 1
            result.setdefault(match[1], {"parent": match[2].rstrip(";"), "body": text[match.end():end],
                                        "file": path.relative_to(SOURCE).as_posix()})
    return result


def inherited(classes, name, pattern):
    """Find the closest declaration without silently borrowing an unrelated equipment family."""
    visited = set()
    while name in classes and name not in visited:
        visited.add(name)
        match = re.search(pattern, classes[name]["body"], re.S)
        if match:
            return match
        name = classes[name]["parent"]
    return None


def skill_allowed(classes, name, method, skill):
    """Evaluate the simple original skill-gate methods; reject unknown expressions explicitly."""
    found = inherited(classes, name, r"int\s+" + method + r"\s*\(\s*\)\s*(?://[^\n]*)?\s*\{(.*?)\n\s*\}")
    if not found:
        return False
    body = found[1]
    conditional = re.search(r"if\s*\(m_nSkillLevel\s*(==|>=|<=|>|<)\s*(\d+)\)", body)
    if conditional:
        limit = int(conditional[2])
        result = {"==": skill == limit, ">=": skill >= limit, "<=": skill <= limit,
                  ">": skill > limit, "<": skill < limit}[conditional[1]]
        first = re.search(r"return\s+([01])", body)
        assert first, (name, method)
        return bool(int(first[1])) if result else not bool(int(first[1]))
    exact = re.fullmatch(r"\s*return\s+([01]);\s*", body)
    assert exact, (name, method, body)
    return bool(int(exact[1]))


def export_icon(classname, classes, check=False):
    """Decode original ALE pixels and, for fluorite, its exact external ACT palette."""
    body = classes[classname]["body"]
    path = re.search(r'src\s*=\$\+"../([^"\n]+)"', body)[1]
    decoder = indexed.load_decoder()
    ale = decoder.AleFile(CACHE / path)
    assert len(ale.frames) == 1, classname
    palette = re.search(r'linkpalette\s*=new palette\(\$\+"../([^"\n]+)"', body)
    sources = [path]
    if palette:
        sources.append(palette[1])
        raw = (CACHE / palette[1]).read_bytes()
        assert len(raw) == 768 and ale.version == 1
        colors = [(*raw[offset:offset + 3], 255) for offset in range(0, 768, 3)]
        frame = indexed.apply_palette(indexed.decode_index_alpha(ale, ale.frames[0]), colors)
    else:
        frame = ale.decode_frame(ale.frames[0])
    target = ROOT / "assets/items/extra_attributes" / (classname.lower() + ".png")
    buffer = io.BytesIO()
    frame.save(buffer, format="PNG", optimize=True)
    if check:
        assert target.read_bytes() == buffer.getvalue(), target
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(buffer.getvalue())
    return {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(frame.size)}, [
        {"url": "http://update.ftxjjy.com/gameser/fr_www/" + source,
         "sha256": hashlib.sha256((CACHE / source).read_bytes()).hexdigest()} for source in sources]


def build(check=False):
    classes = source_classes()
    source = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', source.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {r["id"]: r for path in paths if not path.endswith("extra_attribute_items_v1.json") for r in read(path)["definitions"]}
    originals = {r.get("source_class"): r for r in read("data/gameplay/glory/glory_items_v1.json")["definitions"]}
    by_name = {r["display_name"]: r for r in definitions.values()}
    for row in definitions.values():
        if row["id"].startswith("low_grade_"): by_name[row["display_name"]] = row
    words = "\n".join(path.read_text(encoding="utf-8-sig") for path in (SOURCE / "great").glob("*.fcc"))
    constants = dict(re.findall(r'#define\s+(\w+)\s+"([^"\n]+)"', words))
    npc = (SOURCE / "ven/OterNPC_C.fcc").read_text(encoding="utf-8-sig")
    formulas = {}
    for family, npc_name in [("fluorite", "EquipUpgradeNPC"), ("brilliant", "EquipProcessNPC")]:
        body = re.search(r"class " + npc_name + r":.*?(?=\nclass |\Z)", npc, re.S)[0]
        for match in re.finditer(r'\((\d),((?:"[^"\n]+"[,]?)+)\)', body):
            costs = []
            currency = 0
            for term in re.findall(r'"([^"\n]+)"', match[2]):
                name, amount = term.split("×")
                if name == "星际币": currency = int(amount)
                else: costs.append({"definition_id": by_name[name]["id"], "quantity": int(amount)})
            formulas[f"{family}:{match[1]}"] = {"currency": currency, "materials": costs}
    profiles = []
    for row in definitions.values():
        original = originals.get(STARTERS[row["id"]], row) if row["id"] in STARTERS else row
        classname = original.get("source_class", STARTERS.get(row["id"], ""))
        if row["id"].startswith("official_rocket_firegun_"): classname = "FireGun" + row["id"].rsplit("_", 1)[1]
        if classname not in classes or "space" in original.get("source_audit", {}).get("inheritance", "").lower(): continue
        skill = int(row.get("stats", {}).get("required_skill_level", 0))
        legacy = original.get("stats", {}).get("legacy_properties", {})
        eligible = []
        for family, flag, mask, method in [("fluorite", "m_nIsFluoriteEquip", "m_szFlouriteType", "CanProcess"),
                                           ("brilliant", "m_nIsStoneEquip", "m_szStoneType", "EquipLevLimit")]:
            field = inherited(classes, classname, flag + r"\s*=\s*([01])")
            allowed = int(legacy.get(flag, field[1] if field else "0"))
            types = inherited(classes, classname, mask + r"\s*=\s*\(([^)]+)\)")
            if not allowed or not types or not skill_allowed(classes, classname, method, skill): continue
            eligible += [f"{family}:{index + 1}" for index, value in enumerate(types[1].split(",")) if value.strip() == "1"]
        if eligible:
            profiles.append({"definition_id": row["id"], "display_name": row["display_name"], "source_class": classname, "channels": eligible})
    items, channels = [], []
    for classname, kind in CLASSES.items():
        family = "fluorite" if classname.endswith("Fluorite") else "brilliant"
        id = "extra_" + classname.lower()
        body = classes[classname]["body"]
        name = constants[re.search(r"m_sObjName\s*=\s*(\w+)", body)[1]]
        description = constants[re.search(r"m_sDesc\s*=\s*(\w+)", body)[1]]
        presentation, sources = export_icon(classname, classes, check)
        items.append({"id": id, "kind": "extra_attribute_material", "display_name": name, "description": description,
                      "max_stack": 999, "source_class": classname, "presentation": presentation,
                      "workshop_unit_price": 20000 if family == "fluorite" else 50000,
                      "source_audit": {"source_release": "starhome_lz_fr", "source_file": "cltobj/stuffclt2.fcc",
                                       "sources": sources, "other_releases": {"ry": "404", "jznp": "404"}, "acquisition": "remake_coin_offer"}})
        attribute, points, maximum = ATTRIBUTES[kind]
        key = f"{family}:{kind}"
        channels.append({"id": key, "material_id": id, "attribute": attribute, "points": points, "maximum": maximum, **formulas[key]})
    write("data/gameplay/extra_attribute_items_v1.json", {"schema_version": 1, "definitions": items}, check)
    write("data/gameplay/extra_attribute_rules_v1.json", {"schema_version": 1,
          "success_bands": [{"minimum_level": 0, "chance": 1.0, "failure_loss": 0}, {"minimum_level": 10, "chance": 0.8, "failure_loss": 0},
                            {"minimum_level": 20, "chance": 0.7, "failure_loss": 1}],
          "source": "ven/OterNPC_C.fcc:464,584; FormClass_ven.fcc:1124,1478; original inherited CanProcess/EquipLevLimit and item descriptions",
          "channels": channels, "equipment": sorted(profiles, key=lambda r: r["definition_id"])}, check)
    print(f"Extra attributes: {len(profiles)} eligible equipment, {len(channels)} channels, {len(items)} original material icons")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
