#!/usr/bin/env python3
"""Render every external Glory NPC ACT palette into a mountable sprite pack."""

from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path
from typing import Any

from PIL import Image

import audit_monster_asset_sources as monster_decoder


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
RAW_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
MONSTER_CATALOG = PROJECT_ROOT / "data" / "gameplay" / "glory" / "glory_monsters_v1.json"
SPRITE_INDEX = PROJECT_ROOT / "data" / "content" / "glory_sprite_runtime_index_v1.json"
PACK_PATH = PROJECT_ROOT / "assets" / "content_packs" / "glory_monster_palettes_v1.zip"
PACK_CATALOG = PROJECT_ROOT / "data" / "content" / "glory_monster_palette_content_pack_v1.json"
RUNTIME_INDEX = PROJECT_ROOT / "data" / "content" / "glory_monster_palette_runtime_index_v1.json"
CONTENT_VERSION = "glory-monster-palettes-v1"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fixed_info(path: str) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0))
    info.compress_type = zipfile.ZIP_STORED
    info.external_attr = 0o100644 << 16
    return info


def act_index() -> dict[str, list[Path]]:
    result: dict[str, list[Path]] = {}
    for path in RAW_ROOT.rglob("*.act"):
        result.setdefault(path.name.lower(), []).append(path)
    for paths in result.values():
        paths.sort(key=lambda path: ("/pic3/npc/act/" not in path.as_posix().lower(), path.as_posix().lower()))
    return result


def source_index() -> tuple[dict[str, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    rows = read_json(SPRITE_INDEX)["sprites"]
    by_id = {row["logical_id"]: row for row in rows}
    by_name: dict[str, list[dict[str, Any]]] = {}
    for row in rows:
        by_name.setdefault(Path(row["logical_id"]).name.lower(), []).append(row)
    return by_id, by_name


def resolve_source(reference: str, by_id: dict[str, dict[str, Any]], by_name: dict[str, list[dict[str, Any]]]) -> dict[str, Any]:
    normalized = reference.strip().replace("\\", "/").lower()
    while normalized.startswith("../"):
        normalized = normalized[3:]
    if normalized.endswith(".ale"):
        normalized = normalized[:-4]
    if normalized in by_id:
        return by_id[normalized]
    candidates = by_name.get(Path(normalized).name.lower(), [])
    preferred = [row for row in candidates if row["logical_id"].startswith("pic3/npc/")]
    if preferred:
        return sorted(preferred, key=lambda row: row["logical_id"])[0]
    if len(candidates) == 1:
        return candidates[0]
    raise RuntimeError(f"cannot uniquely resolve monster ALE: {reference}")


def render_variant(
    actor_id: str,
    action: str,
    source_row: dict[str, Any],
    palette_path: Path,
    decoder: Any,
) -> tuple[bytes, bytes, dict[str, Any]]:
    logical_id = source_row["logical_id"]
    ale_path = RAW_ROOT / (logical_id + ".ale")
    ale = decoder.AleFile(ale_path)
    if ale.version != 1:
        raise RuntimeError(f"external ACT used by non-indexed ALE: {ale_path}")
    metadata = read_json(OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites" / logical_id / "frames.json")
    pages = metadata.get("pages", [])
    if len(pages) != 1:
        raise RuntimeError(f"palette variant expects one decoded page: {logical_id}")
    source_page = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites" / logical_id / pages[0]
    with Image.open(source_page) as opened:
        atlas = Image.new("RGBA", opened.size)
    colors = monster_decoder.act_colors(palette_path)
    if len(ale.frames) != len(metadata.get("frames", [])):
        raise RuntimeError(f"frame count mismatch: {logical_id}")
    for frame, frame_row in zip(ale.frames, metadata["frames"], strict=True):
        if frame.width == 0 or frame.height == 0:
            continue
        indexed = monster_decoder.decode_index_alpha(ale, frame)
        rendered = monster_decoder.apply_palette(indexed, colors)
        atlas.alpha_composite(rendered, (int(frame_row["x"]), int(frame_row["y"])))
        indexed.close()
        rendered.close()
    import io

    output = io.BytesIO()
    atlas.save(output, format="PNG", optimize=True)
    atlas.close()
    clean_metadata = dict(metadata)
    clean_metadata["source"] = f"starhome_lz_ry/raw/{logical_id}.ale"
    clean_metadata["source_release"] = "starhome_lz_ry"
    clean_metadata["external_palette"] = palette_path.relative_to(RAW_ROOT).as_posix()
    clean_metadata["rendering"] = "ALE indexed pixels rendered through client-declared ACT palette"
    clean_metadata["pages"] = ["sheet.png"]
    frames_bytes = (json.dumps(clean_metadata, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
    runtime_id = f"monster_palettes/{actor_id}/{action}"
    row = {
        "logical_id": runtime_id,
        "frames_path": f"res://content/glory/{runtime_id}/frames.json",
        "page_paths": [f"res://content/glory/{runtime_id}/sheet.png"],
        "frame_count": len(metadata["frames"]),
        "cell_size": [int(metadata.get("cell_width", 0)), int(metadata.get("cell_height", 0))],
        "classification": ["monster_palettes", actor_id],
        "source_release": "starhome_lz_ry",
    }
    return frames_bytes, output.getvalue(), row


def main() -> int:
    monsters = read_json(MONSTER_CATALOG)["definitions"]
    by_id, by_name = source_index()
    palettes = act_index()
    decoder = monster_decoder.load_decoder()
    PACK_PATH.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, Any]] = []
    source_variants = 0
    with zipfile.ZipFile(PACK_PATH, "w", allowZip64=True) as archive:
        for monster in monsters:
            presentation = monster["presentation"]
            palette_name = Path(presentation.get("palette", "")).name.lower()
            if not palette_name:
                continue
            palette_candidates = palettes.get(palette_name, [])
            if not palette_candidates:
                raise RuntimeError(f"missing ACT palette: {presentation['palette']}")
            actor_id = monster["combat_actor_id"]
            for action, reference in presentation["source_actions"].items():
                source_row = resolve_source(reference, by_id, by_name)
                frames_bytes, page_bytes, row = render_variant(
                    actor_id, action, source_row, palette_candidates[0], decoder
                )
                root = f"content/glory/{row['logical_id']}"
                archive.writestr(fixed_info(root + "/frames.json"), frames_bytes)
                archive.writestr(fixed_info(root + "/sheet.png"), page_bytes)
                rows.append(row)
                source_variants += 1
    RUNTIME_INDEX.parent.mkdir(parents=True, exist_ok=True)
    RUNTIME_INDEX.write_text(json.dumps({
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "summary": {"palette_monsters": source_variants // 3, "sprites": len(rows)},
        "sprites": rows,
    }, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")
    PACK_CATALOG.write_text(json.dumps({
        "schema_version": 1,
        "content_version": CONTENT_VERSION,
        "packs": [{
            "pack_id": PACK_PATH.stem,
            "path": "res://assets/content_packs/" + PACK_PATH.name,
            "size_bytes": PACK_PATH.stat().st_size,
            "sha256": sha256(PACK_PATH),
            "content_groups": ["monster_palette_variants"],
        }],
        "summary": {"palette_monsters": source_variants // 3, "sprites": len(rows)},
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"GLORY_MONSTER_PALETTES_BUILT {source_variants // 3} monsters, {len(rows)} animations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
