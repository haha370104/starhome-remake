"""Extract ground ammunition capacities and original per-round NPC refill prices."""
import argparse
import re
from build_equipment_processing_rules import ROOT, SOURCE, STARTERS, read, write


def build(check=False):
    source = (ROOT / "scripts/domain/items/item_catalog.gd").read_text(encoding="utf-8")
    paths = re.findall(r'"res://([^"]+)"', source.split("const GAMEPLAY_PATHS := [")[1].split("]")[0])
    definitions = {row["id"]: row for path in paths for row in read(path)["definitions"]}
    originals = {row.get("source_class"): row for row in read("data/gameplay/glory/glory_items_v1.json")["definitions"]}
    rockets = (SOURCE / "cltobj/fireguncltclass.fcc").read_text(encoding="utf-8-sig")
    rows = []
    for row in definitions.values():
        original = originals.get(STARTERS[row["id"]], row) if row["id"] in STARTERS else row
        lineage = original.get("source_audit", {}).get("inheritance", "")
        if "space" in lineage.lower():
            continue
        legacy = dict(original.get("stats", {}).get("legacy_properties", {}))
        classname = original.get("source_class", STARTERS.get(row["id"], ""))
        if row["id"].startswith("official_rocket_firegun_"):
            classname = "FireGun" + row["id"].rsplit("_", 1)[1]
        if classname.startswith("FireGun") and not legacy.get("m_nBulletCount"):
            match = re.search(r"^class " + classname + r":.*?(?=^class |\Z)", rockets, re.M | re.S)
            if match:
                legacy.update(dict(re.findall(r"\b(m_n\w+)\s*=\s*(\d+)\s*;", re.sub(r"//[^\n]*", "", match[0]))))
        capacity = int(legacy.get("m_nBulletCount", 0))
        price = int(legacy.get("m_nAddBulletWorth", 0))
        if capacity <= 0 or price <= 0:
            continue
        rows.append({"definition_id": row["id"], "display_name": row["display_name"], "capacity": capacity,
                     "unit_price": price, "source_class": classname, "source_status": "client_fields"})
    write("data/gameplay/equipment_ammunition_rules_v1.json", {"schema_version": 1,
          "policy": {"initial_ammunition": "new equipment and old saves without magazine state start full once",
                     "refill": "configured maintenance maps; missing rounds times original m_nAddBulletWorth",
                     "consumption": "one round per accepted secondary shot; no consumption on rejection"},
          "equipment": sorted(rows, key=lambda row: row["definition_id"])}, check)
    print(f"Ammunition: {len(rows)} original ground capacities and refill prices")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    build(parser.parse_args().check)
