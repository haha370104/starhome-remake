"""Restore world/inventory icons for every configured biological drop and crawler fragment."""
from pathlib import Path
import json

from audit_monster_asset_sources import load_decoder, decode_index_alpha, apply_palette, file_hash

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT.parent / "starhome_lz_ry_full/raw"
ROWS = [
    ("gel", "类胶", "gluey", "rubber"),
    ("energy_catalyst", "能量催化剂", "CHN_2005_06_28_18_34_48_776", "activator"),
    ("biosilicon", "生物硅", "CHN_2005_06_28_18_35_21_781", "silicon"),
    ("quadruped_shell", "四足甲的壳", "CHN_2005_06_28_18_35_28_782", "shell"),
]


def act_colors(path):
    """Read RGB entries; optional Adobe ACT count/transparency trailer is not RGB data."""
    payload = path.read_bytes()
    assert len(payload) in (768, 772), path
    return [(*payload[i:i + 3], 255) for i in range(0, 768, 3)]


def main():
    decoder = load_decoder()
    runtime = json.loads((ROOT / ".godot/content-audit-runtime.json").read_text("utf-8"))
    ids = {item["display_name"]: item_id for item_id, item in runtime["items"].items()}
    path = ROOT / "data/presentation/ground_loot_v1.json"
    presentation = json.loads(path.read_text("utf-8"))
    evidence = []
    specs = [(f"{grade}_grade_{key}", f"{cn}{name}", f"pic3/stuff/{stem}.ale", f"pic3/act/{palette}{color}.act")
             for key, name, stem, palette in ROWS
             for grade, cn, color in [("middle", "中级", "blue"), ("high", "高级", "red")]]
    specs.append(("attachment_upgrade_fragment", "接合器升级碎片", "pic3/stuff/NewJointDebris.ale", ""))
    for key, name, source, palette in specs:
        ale = decoder.AleFile(RAW / source)
        assert len(ale.frames) == 1, source
        frame = ale.frames[0]
        image = (apply_palette(decode_index_alpha(ale, frame), act_colors(RAW / palette))
                 if palette else ale.decode_frame(frame))
        target = ROOT / f"assets/items/materials/{key}/icon.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
        resource = "res://" + target.relative_to(ROOT).as_posix()
        presentation["definitions"][ids[name]] = {
            "display_name": name,
            "world": {"texture": resource, "native_size": list(image.size), "origin": [frame.origin_x, frame.origin_y]},
            "inventory": {"icon": resource, "native_size": list(image.size)},
        }
        evidence.append({"item_definition_id": ids[name], "resource": resource,
                         "source_release": "starhome_lz_ry", "source_logical_path": source,
                         "source_sha256": file_hash(RAW / source, "sha256"), "source_palette": palette,
                         "source_palette_sha256": file_hash(RAW / palette, "sha256") if palette else None,
                         "source_code": "cltobj/stuffclt2.fcc" if palette else "ven/stuffclt2_ven.fcc"})
    path.write_text(json.dumps(presentation, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (ROOT / "assets/items/materials/drop_material_manifest.json").write_text(
        json.dumps({"definitions": evidence}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"DROP_MATERIAL_IMPORT_OK icons={len(evidence)}")


if __name__ == "__main__":
    main()
