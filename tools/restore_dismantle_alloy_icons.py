"""Bind two name-only alloy definitions to their original Glory ALE and exact ACT colors."""
import hashlib
import re
import audit_monster_asset_sources as indexed
from build_equipment_processing_rules import ROOT, SOURCE, read, write


def main():
    original = (SOURCE / "cltobj/stuffclt2.fcc").read_text(encoding="utf-8-sig")
    definitions = read("data/gameplay/glory/glory_items_v1.json")["definitions"]
    raw = ROOT.parent / "starhome_lz_ry_full/raw"
    ale_path = "pic3/stuff/hejin.ale"
    ale = indexed.load_decoder().AleFile(raw / ale_path)
    assert len(ale.frames) == 1
    entries, manifest = [], []
    for name, semantic in [("银铜合金", "silver_copper"), ("金铜合金", "gold_copper")]:
        match = re.search(r"^class " + name + r":.*?(?=^class |\Z)", original, re.M | re.S)
        palette = re.search(r'linkpalette=new palette\(\$\+"../([^"\n]+)"', match[0])[1]
        pixels = indexed.apply_palette(indexed.decode_index_alpha(ale, ale.frames[0]), indexed.act_colors(raw / palette))
        target = ROOT / "assets/items/materials/alloys" / (semantic + ".png")
        target.parent.mkdir(parents=True, exist_ok=True)
        pixels.save(target, optimize=True)
        sources = [{"source_path": path, "sha256": hashlib.sha256((raw / path).read_bytes()).hexdigest()} for path in [ale_path, palette]]
        previous = next(r for r in definitions if r["display_name"] == name)
        assert previous["source_audit"]["status"] == "name_only"
        row = {**previous, "replaces_name_only": True, "source_class": name,
               "presentation": {"icon": "res://" + target.relative_to(ROOT).as_posix(), "native_size": list(pixels.size)},
               "source_audit": {"source_release": "starhome_lz_ry", "source_file": "cltobj/stuffclt2.fcc",
                                "source_line": original[:match.start()].count("\n") + 1, "sources": sources}}
        entries.append(row)
        manifest.append({"file": target.name, "source_release": "starhome_lz_ry", "source_class": name, "sources": sources})
    write("data/gameplay/equipment_dismantle_materials_v1.json", {"schema_version": 1, "definitions": entries}, False)
    write("assets/items/materials/alloys/manifest.json", {"source_release": "starhome_lz_ry", "frames": manifest}, False)
    print("Restored two original alloy icons with distinct palettes; stack limits unchanged")


if __name__ == "__main__":
    main()
