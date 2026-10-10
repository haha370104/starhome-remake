"""Restore the iron ingot icon with its original Glory ALE and ACT palette."""

import hashlib
import json
from pathlib import Path

from audit_monster_asset_sources import act_colors, apply_palette, decode_index_alpha, load_decoder


def main():
    root = Path(__file__).resolve().parents[1]
    definitions = json.loads((root / "data/gameplay/industrial_materials_v1.json").read_text(encoding="utf-8"))["definitions"]
    definition = next(entry for entry in definitions if entry["id"] == "iron")
    sources = [root / "../starhome_lz_ry_full/raw" / entry["source_path"] for entry in definition["source_audit"]["sources"]]
    for source, evidence in zip(sources, definition["source_audit"]["sources"]):
        if hashlib.sha256(source.read_bytes()).hexdigest() != evidence["sha256"]:
            raise RuntimeError(f"Source hash mismatch: {source}")
    sprite = load_decoder().AleFile(sources[0])
    if len(sprite.frames) != 1:
        raise RuntimeError("Expected a single-frame iron icon")
    image = apply_palette(decode_index_alpha(sprite, sprite.frames[0]), act_colors(sources[1]))
    if list(image.size) != definition["presentation"]["native_size"]:
        raise RuntimeError("Iron icon dimensions differ from the catalog")
    target = root / definition["presentation"]["icon"].removeprefix("res://")
    target.parent.mkdir(parents=True, exist_ok=True)
    image.save(target, optimize=True)
    print(f"Restored {target.relative_to(root)} ({image.width}x{image.height}) with original ACT colors")


if __name__ == "__main__":
    main()
