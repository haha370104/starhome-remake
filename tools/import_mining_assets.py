#!/usr/bin/env python3
"""Bake the first mining slice from canonical Glory ALE + ACT sources."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
sys.path.insert(0, str(PROJECT_ROOT / "tools"))

from audit_monster_asset_sources import (  # noqa: E402
    animation_bounds,
    apply_palette,
    decode_index_alpha,
    load_decoder,
)


MINERALS = {
    "iron_ore": "pic3/mine/chn_2005_06_28_18_54_07_968.act",
    "silicon_ore": "pic3/mine/chn_2005_06_28_18_51_44_945.act",
    "graphite_ore": "pic3/mine/chn_2005_06_28_18_53_35_963.act",
}
WORLD_ALE = "pic3/mine/chn_2005_06_28_18_53_17_960.ale"
ITEM_ALE = "pic3/mine/chn_2005_06_28_18_51_50_946.ale"


def load_act_colors(path: Path) -> list[tuple[int, int, int, int]]:
    """Accept both raw 768-byte ACT and Adobe's 4-byte metadata trailer."""
    payload = path.read_bytes()
    if len(payload) not in (256 * 3, 256 * 3 + 4):
        raise RuntimeError(f"unexpected ACT size: {path} ({len(payload)})")
    palette = payload[: 256 * 3]
    return [(*palette[offset : offset + 3], 255) for offset in range(0, len(palette), 3)]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def render_atlas(decoder, ale_path: Path, palette_path: Path) -> tuple[Image.Image, dict]:
    ale = decoder.AleFile(ale_path)
    if ale.version != 1:
        raise RuntimeError(f"external ACT palette requires indexed ALE v1: {ale_path}")
    colors = load_act_colors(palette_path)
    left, top, right, bottom = animation_bounds(ale.frames)
    width = max(1, right - left)
    height = max(1, bottom - top)
    atlas = Image.new("RGBA", (width * ale.frame_count, height))
    for frame in ale.frames:
        indexed = decode_index_alpha(ale, frame)
        rendered = apply_palette(indexed, colors)
        atlas.alpha_composite(
            rendered,
            (frame.index * width + frame.origin_x - left, frame.origin_y - top),
        )
        indexed.close()
        rendered.close()
    return atlas, {
        "frame_count": ale.frame_count,
        "cell_size": [width, height],
        "origin": [left, top],
    }


def main() -> int:
    decoder = load_decoder()
    world_source = GLORY_RAW / WORLD_ALE
    item_source = GLORY_RAW / ITEM_ALE
    if not world_source.is_file() or not item_source.is_file():
        raise RuntimeError("canonical Glory mining ALE files are missing")
    manifest = {
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "world_ale": WORLD_ALE,
        "world_ale_sha256": sha256(world_source),
        "item_ale": ITEM_ALE,
        "item_ale_sha256": sha256(item_source),
        "definitions": {},
    }
    for mineral_id, palette_logical in MINERALS.items():
        palette_source = GLORY_RAW / palette_logical
        if not palette_source.is_file():
            raise RuntimeError(f"canonical Glory ACT file is missing: {palette_source}")
        world, geometry = render_atlas(decoder, world_source, palette_source)
        item, item_geometry = render_atlas(decoder, item_source, palette_source)
        world_target = PROJECT_ROOT / "assets" / "minerals" / mineral_id / "world_frames.png"
        item_target = PROJECT_ROOT / "assets" / "items" / "materials" / mineral_id / "inventory_icon.png"
        world_target.parent.mkdir(parents=True, exist_ok=True)
        item_target.parent.mkdir(parents=True, exist_ok=True)
        world.save(world_target, optimize=True)
        item.save(item_target, optimize=True)
        world.close()
        item.close()
        manifest["definitions"][mineral_id] = {
            "palette": palette_logical,
            "palette_sha256": sha256(palette_source),
            "world_texture": "res://" + world_target.relative_to(PROJECT_ROOT).as_posix(),
            **geometry,
            "inventory_texture": "res://" + item_target.relative_to(PROJECT_ROOT).as_posix(),
            "inventory_size": item_geometry["cell_size"],
        }
    manifest_path = PROJECT_ROOT / "assets" / "minerals" / "mining_asset_manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"MINING_ASSETS_IMPORTED {len(MINERALS)} minerals")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
