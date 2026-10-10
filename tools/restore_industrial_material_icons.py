"""Restore scoped industrial material icons from hash-verified local Glory sources."""

import argparse
import hashlib
import io
import json
from pathlib import Path

from audit_monster_asset_sources import apply_palette, decode_index_alpha, load_decoder


ROOT = Path(__file__).resolve().parents[1]
RECOVERY_GROUP = "typical_industrial_materials_v1"
CATALOG_PATHS = ["data/gameplay/industrial_materials_v1.json", "data/gameplay/equipment_dismantle_materials_v1.json"]


def load_act_colors(path):
    """Read 256 RGB entries, including the original silver ACT's verified CRCRLF suffix."""
    payload = path.read_bytes()
    if len(payload) not in (768, 772) and not (len(payload) == 771 and payload[768:] == b"\r\r\n"):
        raise ValueError(f"Unexpected ACT size or suffix: {path}")
    return [(*payload[offset:offset + 3], 255) for offset in range(0, 768, 3)]


def restore(check=False):
    definitions = [entry for path in CATALOG_PATHS for entry in json.loads((ROOT / path).read_text(encoding="utf-8"))["definitions"]]
    materials = [entry for entry in definitions if entry.get("source_audit", {}).get("presentation_recovery") == RECOVERY_GROUP]
    if len(materials) != 35:
        raise ValueError("Expected exactly 35 scoped industrial materials")
    decoder = load_decoder()
    outputs = []
    for definition in materials:
        evidence = definition["source_audit"]
        sources = [ROOT / "../starhome_lz_ry_full/raw" / entry["source_path"] for entry in evidence["sources"]]
        for source, entry in zip(sources, evidence["sources"]):
            if hashlib.sha256(source.read_bytes()).hexdigest() != entry["sha256"]:
                raise ValueError(f"Source hash mismatch: {source}")
        sprite = decoder.AleFile(sources[0])
        if len(sprite.frames) != 1:
            raise ValueError(f"Expected a single-frame material icon: {definition['display_name']}")
        image = (apply_palette(decode_index_alpha(sprite, sprite.frames[0]), load_act_colors(sources[1]))
                 if len(sources) == 2 else sprite.frames[0].image)
        if list(image.size) != evidence["original_icon_size"] or image.getchannel("A").getbbox() is None:
            raise ValueError(f"Invalid material icon: {definition['display_name']}")
        presentation = definition["presentation"]
        if "icon" not in presentation:
            expected_reference = evidence["sources"][0]["source_path"].lower().removesuffix(".ale")
            if presentation.get("ale_reference", "").lower() != expected_reference:
                raise ValueError(f"Material ALE reference differs from original: {definition['display_name']}")
            continue
        if presentation["native_size"] != list(image.size):
            raise ValueError(f"Material native size mismatch: {definition['display_name']}")
        target = ROOT / presentation["icon"].removeprefix("res://")
        buffer = io.BytesIO()
        image.save(buffer, format="PNG", optimize=True)
        payload = buffer.getvalue()
        if check:
            if target.read_bytes() != payload:
                raise ValueError(f"Restored icon differs from original: {target}")
        else:
            outputs.append((target, payload))
    for target, payload in outputs:
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    print(f"INDUSTRIAL_MATERIAL_ICONS_OK materials={len(materials)} restored_pngs={sum('icon' in entry['presentation'] for entry in materials)} check={check}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    restore(parser.parse_args().check)
