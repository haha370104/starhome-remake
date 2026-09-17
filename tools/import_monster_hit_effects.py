"""Import explicitly reviewed monster impacts; never search or fall back at runtime.

The input is the checked-in impact catalog. Original archives stay outside Git.
Use --check to compare every exported pixel and pivot against its source ALE.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

from audit_monster_asset_sources import animation_bounds, build_tres, load_decoder

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/gameplay/glory/monster_hit_effects_v1.json"


def export_effect(row: dict, decoder, check: bool) -> None:
    """Keep original RGBA pixels and per-frame origins in fixed-size atlas cells."""
    audit = row["source_audit"]
    release = audit["source_release"]
    if release not in ("starhome_lz_fr", "starhome_lz_ry"):
        raise ValueError(f"Unsupported source release: {release}")
    source_root = ROOT.parent / f"{release}_full/raw"
    source = (source_root / audit["source_logical_path"]).resolve()
    if not source.is_relative_to(source_root.resolve()):
        raise ValueError("Source escapes original archive")
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != audit["source_sha256"]:
        raise ValueError(f"Reviewed source changed: {source}")
    descriptor = row["impact"]
    resource = (ROOT / descriptor["resource"].removeprefix("res://")).resolve()
    if not resource.is_relative_to((ROOT / "assets/monsters").resolve()):
        raise ValueError("Impact output must be inside monster assets")
    ale = decoder.AleFile(source)
    left, top, right, bottom = animation_bounds(ale.frames)
    width, height = right - left, bottom - top
    if descriptor["frames"] != len(ale.frames) or descriptor["offset"] != [left, top]:
        raise ValueError(f"Frame count or pivot changed: {row['id']}")
    atlas = Image.new("RGBA", (width * len(ale.frames), height))
    for frame in ale.frames:
        atlas.paste(ale.decode_frame(frame),
                    (frame.index * width + frame.origin_x - left, frame.origin_y - top))
    target = resource.parent
    texture = target / "frames.png"
    tres = build_tres(texture, len(ale.frames), width, height).replace(
        '"loop": true', '"loop": false').replace('"speed": 10', '"speed": 15.1515151515152')
    metadata = {
        "export_format_version": 1,
        **audit,
        "frame_count": len(ale.frames),
        "frame_delay_ms": 66,
        "loop": False,
        "coordinate_bounds": [left, top, right, bottom],
        "runtime_resource": descriptor["resource"],
        "source_frames": [
            {"index": f.index, "size": [f.width, f.height], "origin": [f.origin_x, f.origin_y]}
            for f in ale.frames
        ],
    }
    if check:
        with Image.open(texture) as actual:
            if actual.size != atlas.size or actual.convert("RGBA").tobytes() != atlas.tobytes():
                raise ValueError(f"Export pixels differ from original: {row['id']}")
        if resource.read_text(encoding="utf-8") != tres:
            raise ValueError(f"Animation timing or atlas regions differ: {row['id']}")
        if json.loads((target / "import_metadata.json").read_text(encoding="utf-8")) != metadata:
            raise ValueError(f"Provenance differs: {row['id']}")
    else:
        target.mkdir(parents=True, exist_ok=True)
        atlas.save(texture)
        resource.write_text(tres, encoding="utf-8", newline="\n")
        (target / "import_metadata.json").write_text(
            json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    """Process only imported effects selected by the reviewed runtime catalog."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    decoder = load_decoder()
    definitions = json.loads(CATALOG.read_text(encoding="utf-8"))["definitions"]
    imported = [row for row in definitions if "impact" in row]
    for row in imported:
        export_effect(row, decoder, args.check)
    print(f"MONSTER_IMPACT_ASSETS_OK effects={len(imported)} mode={'check' if args.check else 'import'}")


if __name__ == "__main__":
    main()
