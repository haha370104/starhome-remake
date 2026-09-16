"""Resolve Glory default equipment-style projectile overrides into an auditable table."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "starhome_lz_ry_fcc_source"


def quoted(value):
    """Read filename literals from the original FCC property expression."""
    return re.findall(r'"([^"]*)"', value)


def main():
    """Compile default-style bindings using the existing Glory sprite index."""
    items = json.loads((ROOT / "data/gameplay/glory/glory_items_v1.json").read_text(encoding="utf-8-sig"))["definitions"]
    rockets = json.loads((ROOT / "data/gameplay/official_rocket_items_v1.json").read_text(encoding="utf-8-sig"))["definitions"]
    source = (SOURCE / "cltobj/fireguncltclass.fcc").read_text(encoding="utf-8-sig")
    for item in rockets:
        number = item["id"].rsplit("_", 1)[1]
        body = re.search(r'class\s+FireGun_?' + number + r'\s*:[^{]+\{(.*?)(?=\nclass|\Z)', source, re.S | re.I).group(1)
        item["stats"]["legacy_properties"]["m_sbulletfile"] = re.search(r'm_sbulletfile\s*=\s*("[^"]+")', body).group(1)
        item["source_class"] = "FireGun" + number
    sprites = json.loads((ROOT / "data/content/glory_sprite_runtime_index_v1.json").read_text(encoding="utf-8-sig"))["sprites"]
    available = {row["logical_id"].lower(): row for row in sprites}
    rows, missing = {}, []
    for item in items + rockets:
        mode = {"energy_cannon": "energy_cannon", "missile_weapon": "missile", "rocket_weapon": "rocket_launcher"}.get(item["kind"])
        if not mode:
            continue
        legacy = item["stats"].get("legacy_properties", {})
        variants = quoted(legacy.get("m_szBulletFileChange", ""))
        declared = quoted(legacy.get("m_sbulletfile", ""))
        selected = (variants or declared or [""])[0]
        reference = "pic3/bullet/" + selected.lower().removesuffix(".ale")
        if reference not in available:
            missing.append({"definition_id": item["id"], "source_reference": reference})
            continue
        rows[item["id"]] = {"mode": mode, "projectile": {"ale_reference": reference, "frames": available[reference]["frame_count"], "fps": 10.0},
            "source_class": item["source_class"], "source_declared_projectile": declared[0] if declared else "",
            "source_style_override": variants[0] if variants else "", "source_file": item["source_audit"]["source_file"]}
    document = {"schema_version": 1, "source_release": "starhome_lz_ry", "equipment_style_index": 0,
        "evidence": "cltobj/equipclt.fcc::ChangeEquipStyle overrides m_sbulletfile with m_szBulletFileChange[0]; bullet.fcc::laserbullet resolves pic3/bullet/",
        "weapons": rows, "unavailable_source_assets": missing}
    target = ROOT / "data/presentation/weapon_visual_bindings_v1.json"
    target.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"WEAPON_VISUAL_BINDINGS available={len(rows)} unavailable={len(missing)}")


if __name__ == "__main__":
    main()
