"""Build auditable ordinary vehicle socket rules, without changing any player save."""
import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "data/gameplay/vehicle_socket_rules_v1.json"


def read(relative):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def build():
    originals = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    by_class = {row.get("source_class"): row for row in originals}
    starters = read("data/gameplay/stage3/starter_loadout_v1.json")["definitions"]
    aliases = {"recruit_tank": "tank1", "beginner_engine": "engine1",
               "recruit_energy_cannon": "gun1", "starter_missile": "Missile1"}
    profiles = []
    for row in originals + starters:
        source = by_class[aliases[row["id"]]] if row["id"] in aliases else row
        props = source.get("stats", {}).get("legacy_properties", {})
        location = int(source.get("equipment_location", -1))
        if props.get("m_nExFillister") != "1" or not 0 <= location <= 18:
            continue
        maximum = int(props.get("m_nNumFillister", "8"))
        expansion = props.get("m_nIsExFillisterAdd") == "1"
        lineage = source.get("source_audit", {}).get("inheritance", "").split(" > ")
        special = "ProcessArmmor10" in lineage or int(props.get("m_nNewSubGunKind", "0")) in [1, 2, 3, 4, 12, 13, 14, 15]
        profiles.append({"definition_id": row["id"], "display_name": row["display_name"],
                         "base_capacity": 8 if expansion else maximum,
                         "maximum_capacity": maximum, "expansion": expansion,
                         "high_solvent_only": "ProcessArmmor10" in lineage,
                         "high_solvent_guaranteed": special,
                         "source_class": source.get("source_class"),
                         "source_file": source.get("source_audit", {}).get("source_file"),
                         "source_line": source.get("source_audit", {}).get("source_line")})
    profiles.sort(key=lambda row: row["definition_id"])
    assert profiles and all(1 <= p["base_capacity"] <= p["maximum_capacity"] <= 12 for p in profiles)
    assert len({p["definition_id"] for p in profiles}) == len(profiles)
    flawed = ["a7bccd7c1408", "794588abb6cf", "d690c44b6030", "a095c982b884", "c0cad9b715fb", "7dd51398ea4c"]
    kinds = ["firepower", "health", "defense", "guidance", "critical", "rocket"]
    values = [[3, 30, 1, 2, 0.01, 3], [5, 50, 3, 4, 0.025, 6]]
    crystals = [{"definition_id": "item:material:" + flawed[i] if grade == 0 else "bright_" + kind + "_crystal",
                 "effect": kind, "value": values[grade][i], "grade": grade + 1,
                 "source_code": 1000 * (grade + 1) + i + 1}
                for grade in range(2) for i, kind in enumerate(kinds)]
    rules = {"schema_version": 1,
             "source_policy": {"release": "starhome_lz_ry", "eligibility": "explicit m_nExFillister=1, ordinary vehicle locations 0..18; legacy UI class whitelist unified in remake",
                               "solvents": "ven/OterNPC_C.fcc:1295-1358", "crystals": "cltobj/stuffclt.fcc:584-705",
                               "removal": "cltobj/stuffclt.fcc:908", "expansion": "great/yl_great.fcc:394",
                               "selection": "remake: strongest four per effect across working loadout; critical chance additive, multiplier 1.5",
                               "expansion_settlement": "remake: 8 chips unlock each extra socket, solvent opens it; no random expansion failure",
                               "hammer": "remake: optional precise hammer prevents new crack; normal fourth removal destroys crystal"},
             "maximum_effective_per_kind": 4, "critical_multiplier": 1.5,
             "maximum_cracks": 3, "expansion_cost": {"definition_id": "vehicle_armed_chip", "quantity": 8},
             "hammer_id": "vehicle_precise_hammer",
             "solvents": [
                 {"definition_id": "vehicle_density_solvent_i", "chances": [0.5], "repeat_last": True, "failure": "destroy_equipment"},
                 {"definition_id": "item:material:78f2a523a761", "chances": [0.5, 0.2, 0.1, 0.01], "repeat_last": False, "failure": "close_last_socket"},
                 {"definition_id": "high_grade_density_solvent", "chances": [0.8, 0.6, 0.4, 0.2], "repeat_last": False, "failure": "none"}],
             "crystals": crystals, "equipment": profiles}
    # One record per line keeps the source-derived catalog reviewable.
    return "{\n" + ",\n".join('  ' + json.dumps(key) + ': ' + (
        '[\n' + ',\n'.join('    ' + json.dumps(row, ensure_ascii=False) for row in value) + '\n  ]'
        if isinstance(value, list) else json.dumps(value, ensure_ascii=False)) for key, value in rules.items()) + "\n}\n"


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    output = build()
    if args.check:
        assert TARGET.read_text(encoding="utf-8") == output, "Socket rules differ; regenerate them"
    else:
        TARGET.write_text(output, encoding="utf-8")
    print("Vehicle socket rules verified" if args.check else "Vehicle socket rules generated")
