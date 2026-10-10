"""Import explicitly reviewed monster impacts; never search or fall back at runtime.

The input is the checked-in impact catalog. Original archives stay outside Git.
Use --check to compare every exported pixel and pivot against its source ALE.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import urllib.parse

from PIL import Image

from audit_monster_asset_sources import animation_bounds, build_tres, load_decoder
from recovery.cross_release_paths import CACHE

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "data/gameplay/glory/monster_hit_effects_v1.json"


def export_effect(row: dict, decoder, check: bool) -> None:
    """Keep original RGBA pixels and per-frame origins in fixed-size atlas cells."""
    audit = row["source_audit"]
    release = audit["source_release"]
    if release not in ("starhome_lz_fr", "starhome_lz_ry"):
        raise ValueError(f"Unsupported source release: {release}")
    source_logical = Path(audit["source_logical_path"])
    source_roots = [ROOT.parent / f"{release}_full/raw"]
    if release == "starhome_lz_fr":
        source_roots.append(CACHE / "free" / "raw")
    source = None
    source_root = None
    for candidate_root in source_roots:
        candidate = (candidate_root / source_logical).resolve()
        if candidate.is_relative_to(candidate_root.resolve()) and candidate.is_file():
            source = candidate
            source_root = candidate_root
            break
    if source is None or source_root is None:
        raise FileNotFoundError(f"Reviewed source is missing: {audit['source_logical_path']}")
    raw = source.read_bytes()
    if hashlib.sha256(raw).hexdigest() != audit["source_sha256"]:
        raise ValueError(f"Reviewed source changed: {source}")
    source_fetch = audit.get("source_fetch")
    if source_fetch:
        url_base = (
            "http://update.ftxjjy.com/gameser/fr_www/"
            if release == "starhome_lz_fr"
            else "http://update.ftxjjy.com/gameser/ry_www/"
        )
        expected_url = url_base + urllib.parse.quote(str(source_logical).replace("\\", "/"), safe="/")
        if source_fetch.get("url") != expected_url or int(source_fetch.get("http_status", 0)) != 200:
            raise ValueError(f"Official source fetch record is invalid: {row['id']}")
        if source_fetch.get("bytes") != len(raw):
            raise ValueError(f"Official source byte count changed: {row['id']}")
        if source_fetch.get("md5") != hashlib.md5(raw, usedforsecurity=False).hexdigest():
            raise ValueError(f"Official source MD5 changed: {row['id']}")
        if source_fetch.get("sha256") != hashlib.sha256(raw).hexdigest():
            raise ValueError(f"Official source SHA-256 changed: {row['id']}")
    descriptor = row["impact"]
    resource = (ROOT / descriptor["resource"].removeprefix("res://")).resolve()
    if not resource.is_relative_to((ROOT / "assets/monsters").resolve()):
        raise ValueError("Impact output must be inside monster assets")
    ale = decoder.AleFile(source)
    left, top, right, bottom = animation_bounds(ale.frames)
    width, height = right - left, bottom - top
    if descriptor["frames"] != len(ale.frames) or descriptor["offset"] != [left, top]:
        raise ValueError(f"Frame count or pivot changed: {row['id']}")
    if source_fetch and (
        source_fetch.get("decoded_frame_count") != len(ale.frames)
        or source_fetch.get("coordinate_bounds") != [left, top, right, bottom]
    ):
        raise ValueError(f"Official source decode record changed: {row['id']}")
    atlas = Image.new("RGBA", (width * len(ale.frames), height))
    for frame in ale.frames:
        atlas.paste(frame.image,
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
