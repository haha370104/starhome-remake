#!/usr/bin/env python3
"""Migrate and audit the four first-slice monsters against the Glory archive.

The Glory client no longer ships the old free-version ``pic``/``pic2`` sprite
paths. Its runtime NPC catalog maps the same business monsters to indexed
``pic3`` ALE files plus ACT palettes. ``--migrate`` rebuilds the checked-in
Godot atlases from those canonical files; the default mode is a read-only
provenance and reference audit.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import struct
import sys
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
GLORY_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
MONSTER_ROOT = PROJECT_ROOT / "assets" / "monsters"
CATALOG_PATH = PROJECT_ROOT / "data" / "monster_animations.json"
DECODER_ROOT = PROJECT_ROOT.parent.parent / "work"

ALE = {
    "adult_attack": "pic3/npc/CHN_2005_06_28_18_48_40_915.ale",
    "adult_idle": "pic3/npc/CHN_2005_06_28_18_49_29_923.ale",
    "adult_move": "pic3/npc/CHN_2005_06_28_18_49_17_921.ale",
    "adult_shadow_attack": "pic3/npc/Shadow/CHN_2005_06_28_18_48_46_916.ale",
    "adult_shadow_idle": "pic3/npc/Shadow/CHN_2005_06_28_18_49_35_924.ale",
    "adult_shadow_move": "pic3/npc/Shadow/CHN_2005_06_28_18_49_23_922.ale",
    "adult_death": "pic3/npc/OnDie/CHN_2005_06_28_18_48_34_914.ale",
    "adult_projectile_standard": "pic3/npc/bullet/CHN_2005_06_28_18_48_59_918.ale",
    "adult_projectile_bloody": "pic3/npc/bullet/CHN_2005_06_28_18_49_05_919.ale",
    "larva_attack": "pic3/npc/CHN_2005_06_28_18_39_13_821.ale",
    "larva_idle": "pic3/npc/CHN_2005_06_28_18_39_47_827.ale",
    "larva_move": "pic3/npc/CHN_2005_06_28_18_39_30_824.ale",
    "larva_shadow": "pic3/npc/Shadow/CHN_2005_06_28_18_39_36_825.ale",
    "larva_death": "pic3/npc/OnDie/CHN_2005_06_28_18_39_07_820.ale",
    "larva_projectile": "pic3/npc/bullet/CHN_2005_06_28_18_39_19_822.ale",
    "orb_body": "pic3/npc/CHN_2005_06_28_18_48_04_909.ale",
    "orb_shadow": "pic3/npc/Shadow/CHN_2005_06_28_18_48_10_910.ale",
    "orb_death": "pic3/npc/OnDie/CHN_2005_06_28_18_47_46_906.ale",
    "orb_projectile": "pic3/npc/bullet/CHN_2005_06_28_18_47_52_907.ale",
    "gel_move": "pic3/npc/CHN_2005_06_28_18_50_00_928.ale",
    "gel_idle": "pic3/npc/CHN_2005_06_28_18_50_06_929.ale",
    "gel_death": "pic3/npc/OnDie/CHN_2005_06_28_18_49_41_925.ale",
    "gel_projectile": "pic3/npc/bullet/CHN_2005_06_28_18_49_47_926.ale",
}

PALETTES = {
    "adult_standard": "pic3/npc/act/NpcChengChong1.act",
    "adult_toxic": "pic3/npc/act/NpcChengChong2.act",
    "adult_bloody": "pic3/npc/act/NpcChengChong3.act",
    "larva_standard": "pic3/npc/act/NpcYouChong1.act",
    "larva_toxic": "pic3/npc/act/NpcYouChong2.act",
    "larva_bloody": "pic3/npc/act/NpcYouChong3.act",
    "orb_standard": "pic3/npc/act/NpcLightBall1.act",
    "orb_cold": "pic3/npc/act/NpcLightBall2.act",
    "orb_malignant": "pic3/npc/act/NpcLightBall3.act",
    "gel_standard": "pic3/npc/act/NpcSlm1.act",
    "gel_cold": "pic3/npc/act/NpcSlm2.act",
    "gel_malignant": "pic3/npc/act/NpcSlm3.act",
}

# target directory -> (ALE key, optional external ACT key)
ASSETS: dict[str, tuple[str, str | None]] = {
    "om_adult/indexed_base/attack": ("adult_attack", None),
    "om_adult/indexed_base/idle": ("adult_idle", None),
    "om_adult/indexed_base/move": ("adult_move", None),
    "om_adult/indexed_base/shadows/attack": ("adult_shadow_attack", None),
    "om_adult/indexed_base/shadows/idle": ("adult_shadow_idle", None),
    "om_adult/indexed_base/shadows/move": ("adult_shadow_move", None),
    "om_adult/shared/effects/death": ("adult_death", None),
    "om_adult/shared/effects/projectile_bloody": ("adult_projectile_bloody", None),
    "om_adult/shared/effects/projectile_standard": ("adult_projectile_standard", None),
    "om_adult/shared/shadows/attack": ("adult_shadow_attack", None),
    "om_adult/shared/shadows/idle": ("adult_shadow_idle", None),
    "om_adult/shared/shadows/move": ("adult_shadow_move", None),
    "om_adult/variants/standard/attack": ("adult_attack", "adult_standard"),
    "om_adult/variants/standard/idle": ("adult_idle", "adult_standard"),
    "om_adult/variants/standard/move": ("adult_move", "adult_standard"),
    "om_adult/variants/toxic/attack": ("adult_attack", "adult_toxic"),
    "om_adult/variants/toxic/idle": ("adult_idle", "adult_toxic"),
    "om_adult/variants/toxic/move": ("adult_move", "adult_toxic"),
    "om_larva/indexed_base/attack": ("larva_attack", None),
    "om_larva/indexed_base/idle": ("larva_idle", None),
    "om_larva/indexed_base/move": ("larva_move", None),
    "om_larva/indexed_base/shadows/primary": ("larva_shadow", None),
    "om_larva/shared/effects/death": ("larva_death", None),
    "om_larva/shared/effects/projectile": ("larva_projectile", None),
    "om_larva/shared/shadow": ("larva_shadow", None),
    "om_larva/variants/standard/attack": ("larva_attack", "larva_standard"),
    "om_larva/variants/standard/idle": ("larva_idle", "larva_standard"),
    "om_larva/variants/standard/move": ("larva_move", "larva_standard"),
    "om_larva/variants/toxic/attack": ("larva_attack", "larva_toxic"),
    "om_larva/variants/toxic/idle": ("larva_idle", "larva_toxic"),
    "om_larva/variants/toxic/move": ("larva_move", "larva_toxic"),
    "photosensitive_orb/shared/effects/death": ("orb_death", None),
    "photosensitive_orb/shared/effects/projectile": ("orb_projectile", None),
    "photosensitive_orb/shared/shadow": ("orb_shadow", None),
    "photosensitive_orb/variants/standard/move_attack": ("orb_body", "orb_standard"),
    "photosensitive_orb/variants/standard/idle": ("orb_body", "orb_standard"),
    "photosensitive_orb/variants/cold/move_attack": ("orb_body", "orb_cold"),
    "photosensitive_orb/variants/cold/idle": ("orb_body", "orb_cold"),
    "photosensitive_orb/variants/malignant/move_attack": ("orb_body", "orb_malignant"),
    "photosensitive_orb/variants/malignant/idle": ("orb_body", "orb_malignant"),
    "toxic_gel/indexed_base/idle": ("gel_idle", None),
    "toxic_gel/indexed_base/move": ("gel_move", None),
    "toxic_gel/shared/effects/death": ("gel_death", None),
    "toxic_gel/shared/effects/projectile": ("gel_projectile", None),
    "toxic_gel/variants/standard/idle": ("gel_idle", "gel_standard"),
    "toxic_gel/variants/standard/move": ("gel_move", "gel_standard"),
    "toxic_gel/variants/cold/idle": ("gel_idle", "gel_cold"),
    "toxic_gel/variants/cold/move": ("gel_move", "gel_cold"),
    "toxic_gel/variants/malignant/idle": ("gel_idle", "gel_malignant"),
    "toxic_gel/variants/malignant/move": ("gel_move", "gel_malignant"),
}

REMOVED = {
    "om_adult/shared/effects/impact_explosion": "not referenced by the runtime catalog; no Glory business mapping",
    "om_adult/shared/effects/impact_small": "not referenced by the runtime catalog; no Glory business mapping",
    "om_larva/indexed_base/shadows/alternate": "not referenced; Glory catalog uses the primary shadow",
    "om_larva/shared/effects/impact": "not referenced by the runtime catalog; no Glory business mapping",
    "photosensitive_orb/shared/effects/energy_pulse_blue": "not referenced; duplicates a body animation under a misleading role",
    "photosensitive_orb/shared/effects/energy_pulse_dark": "not referenced; duplicates the shadow under a misleading role",
    "photosensitive_orb/shared/effects/energy_pulse_orange": "not referenced and absent from the Glory package",
    "photosensitive_orb/shared/effects/energy_pulse_yellow": "not referenced and absent from the Glory package",
    "photosensitive_orb/shared/effects/impact": "not referenced by the runtime catalog; no Glory business mapping",
    "photosensitive_orb/variants/unidentified/idle": "free-version-only unidentified fourth variant",
    "photosensitive_orb/variants/unidentified/move_attack": "free-version-only unidentified fourth variant",
    "toxic_gel/shared/effects/impact": "not referenced by the runtime catalog; no Glory business mapping",
}

PALETTE_OUTPUTS = {
    "om_adult/palettes/standard.png": "adult_standard",
    "om_adult/palettes/toxic.png": "adult_toxic",
    "om_adult/palettes/bloody.png": "adult_bloody",
    "om_larva/palettes/standard.png": "larva_standard",
    "om_larva/palettes/toxic.png": "larva_toxic",
    "om_larva/palettes/bloody.png": "larva_bloody",
    "photosensitive_orb/palettes/standard.png": "orb_standard",
    "photosensitive_orb/palettes/cold.png": "orb_cold",
    "photosensitive_orb/palettes/malignant.png": "orb_malignant",
    "toxic_gel/palettes/standard.png": "gel_standard",
    "toxic_gel/palettes/cold.png": "gel_cold",
    "toxic_gel/palettes/malignant.png": "gel_malignant",
}


def atomic_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def atomic_json(path: Path, value: Any) -> None:
    atomic_text(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def file_hash(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_decoder():
    if not (DECODER_ROOT / "ale_sprite.py").is_file():
        raise RuntimeError(f"canonical ALE decoder not found: {DECODER_ROOT / 'ale_sprite.py'}")
    sys.path.insert(0, str(DECODER_ROOT))
    return importlib.import_module("ale_sprite")


def decode_index_alpha(ale, frame) -> Image.Image:
    data = ale.data
    position = frame.offset + 24 + frame.meta_length
    record_end = frame.offset + frame.size
    row_count = struct.unpack_from("<H", data, position)[0]
    position += 2
    pixels = bytearray(frame.width * frame.height * 2)
    rows_done = 0
    row_bias = 0

    def put(x: int, y: int, index: int, alpha: int) -> None:
        if 0 <= x < frame.width and 0 <= y < frame.height:
            offset = (y * frame.width + x) * 2
            pixels[offset] = index
            pixels[offset + 1] = alpha

    while rows_done < row_count:
        command_count = struct.unpack_from("<H", data, position)[0]
        position += 2
        if command_count & 0xC000:
            row_bias += (-command_count) & 0xFFFF
            continue
        payload_length = struct.unpack_from("<H", data, position)[0]
        position += 2
        row_end = position + payload_length
        x = 0
        y = row_bias + rows_done
        for _ in range(command_count):
            x += data[position]
            tag = data[position + 1]
            position += 2
            if tag < 0x80:
                for _ in range(tag):
                    put(x, y, data[position], 255)
                    position += 1
                    x += 1
                continue
            while True:
                mode = tag & 0x60
                amount = tag & 0x1F
                if mode == 0x20:
                    x += amount
                    break
                if mode not in (0x40, 0x60):
                    break
                put(x, y, data[position], amount * 8)
                position += 1
                x += 1
                if mode == 0x40:
                    break
                tag = data[position]
                position += 1
        position = row_end
        rows_done += 1
    return Image.frombytes("LA", (frame.width, frame.height), bytes(pixels))


def act_colors(path: Path) -> list[tuple[int, int, int, int]]:
    payload = path.read_bytes()
    if len(payload) != 256 * 3:
        raise RuntimeError(f"unexpected ACT size: {path} ({len(payload)})")
    return [(*payload[offset : offset + 3], 255) for offset in range(0, len(payload), 3)]


def apply_palette(indexed: Image.Image, colors: list[tuple[int, int, int, int]]) -> Image.Image:
    source = indexed.getdata()
    output = Image.new("RGBA", indexed.size)
    output.putdata([(colors[index][0], colors[index][1], colors[index][2], alpha) for index, alpha in source])
    return output


def animation_bounds(frames) -> tuple[int, int, int, int]:
    visible = [frame for frame in frames if frame.width and frame.height]
    left = min(frame.origin_x for frame in visible)
    top = min(frame.origin_y for frame in visible)
    right = max(frame.origin_x + frame.width for frame in visible)
    bottom = max(frame.origin_y + frame.height for frame in visible)
    return left, top, right, bottom


def res_path(path: Path) -> str:
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


def build_tres(texture: Path, frame_count: int, width: int, height: int) -> str:
    subs: list[str] = []
    entries: list[str] = []
    for index in range(frame_count):
        x = index * width
        subs.extend(
            [
                f'[sub_resource type="AtlasTexture" id="frame_{index}"]',
                'atlas = ExtResource("tex_1")',
                f"region = Rect2({x}, 0, {width}, {height})",
                "filter_clip = true",
                "",
            ]
        )
        entries.append(f'{{"duration": 1.0, "texture": SubResource("frame_{index}")}}')
    return (
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]\n\n'
        f'[ext_resource type="Texture2D" path={json.dumps(res_path(texture))} id="tex_1"]\n\n'
        + "\n".join(subs)
        + '[resource]\nanimations = [{\n"frames": ['
        + ", ".join(entries)
        + '],\n"loop": true,\n"name": &"raw",\n"speed": 10\n}]\n'
    )


def build_preview(resource: Path, pivot_x: int, pivot_y: int) -> str:
    return (
        '[gd_scene load_steps=2 format=3]\n\n'
        f'[ext_resource type="SpriteFrames" path={json.dumps(res_path(resource))} id="1_frames"]\n\n'
        '[node name="MonsterAnimationPreview" type="AnimatedSprite2D"]\n'
        'sprite_frames = ExtResource("1_frames")\n'
        'animation = &"raw"\n'
        'autoplay = "raw"\n'
        'centered = false\n'
        f'offset = Vector2({-pivot_x}, {-pivot_y})\n'
        'texture_filter = 1\n'
    )


def verify_parsed_geometry(source_logical: str, ale) -> str:
    relative = Path(source_logical)
    parsed_dir = GLORY_PARSED / relative.with_suffix("")
    manifest_path = parsed_dir / "frames.json"
    if not manifest_path.is_file():
        raise RuntimeError(f"missing Glory parsed frames: {manifest_path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest["frame_count"] != ale.frame_count:
        raise RuntimeError(f"frame count differs from parsed export: {source_logical}")
    for expected, actual in zip(manifest["frames"], ale.frames, strict=True):
        geometry = [actual.width, actual.height, actual.origin_x, actual.origin_y]
        parsed = [expected["width"], expected["height"], expected["origin_x"], expected["origin_y"]]
        if geometry != parsed:
            raise RuntimeError(f"frame geometry differs from parsed export: {source_logical}")
    return relative.with_suffix("").as_posix()


def export_asset(target_relative: str, ale_key: str, palette_key: str | None, decoder) -> dict[str, Any]:
    source_logical = ALE[ale_key]
    source = GLORY_RAW / Path(source_logical)
    if not source.is_file():
        raise RuntimeError(f"missing Glory ALE: {source}")
    ale = decoder.AleFile(source)
    if palette_key and ale.version != 1:
        raise RuntimeError(f"external monster palette requires ALE v1: {source}")
    parsed_logical = verify_parsed_geometry(source_logical, ale)
    left, top, right, bottom = animation_bounds(ale.frames)
    cell_width = max(1, right - left)
    cell_height = max(1, bottom - top)
    if cell_width * ale.frame_count > 8192:
        raise RuntimeError(f"single-row monster atlas exceeds 8192 px: {target_relative}")

    target = MONSTER_ROOT / Path(target_relative)
    target.mkdir(parents=True, exist_ok=True)
    rgba_atlas = Image.new("RGBA", (cell_width * ale.frame_count, cell_height))
    indexed_atlas = Image.new("LA", rgba_atlas.size) if ale.version == 1 else None
    external_palette = None
    palette_logical = None
    palette_source = None
    if palette_key:
        palette_logical = PALETTES[palette_key]
        palette_source = GLORY_RAW / Path(palette_logical)
        external_palette = act_colors(palette_source)

    frame_rows: list[dict[str, Any]] = []
    for frame in ale.frames:
        cell_x = frame.index * cell_width
        paste = (cell_x + frame.origin_x - left, frame.origin_y - top)
        indexed = decode_index_alpha(ale, frame) if ale.version == 1 else None
        rendered = apply_palette(indexed, external_palette) if external_palette else ale.decode_frame(frame)
        if indexed_atlas is not None and indexed is not None:
            indexed_atlas.paste(indexed, paste)
        rgba_atlas.alpha_composite(rendered, paste)
        if indexed is not None:
            indexed.close()
        rendered.close()
        frame_rows.append(
            {
                "index": frame.index,
                "page": 0,
                "atlas_rect": [cell_x, 0, cell_width, cell_height],
                "source_size": [frame.width, frame.height],
                "source_origin": [frame.origin_x, frame.origin_y],
                "source_position_in_cell": [frame.origin_x - left, frame.origin_y - top],
                "record_offset": frame.offset,
                "record_size": frame.size,
            }
        )

    rgba_path = target / "frames.png"
    indexed_path = target / "indexed_frames.png"
    embedded_path = target / "embedded_palette.png"
    rgba_atlas.save(rgba_path, optimize=True)
    if indexed_atlas is not None:
        indexed_atlas.save(indexed_path, optimize=True)
    elif indexed_path.exists():
        indexed_path.unlink()
    if ale.palette is not None:
        embedded = Image.new("RGBA", (256, 1))
        embedded.putdata(ale.palette)
        embedded.save(embedded_path, optimize=True)
        embedded.close()
    elif embedded_path.exists():
        embedded_path.unlink()
    rgba_atlas.close()
    if indexed_atlas is not None:
        indexed_atlas.close()

    tres_path = target / "animation_frames.tres"
    preview_path = target / "preview.tscn"
    atomic_text(tres_path, build_tres(rgba_path, ale.frame_count, cell_width, cell_height))
    atomic_text(preview_path, build_preview(tres_path, -left, -top))
    source_md5 = file_hash(source, "md5")
    metadata: dict[str, Any] = {
        "export_format_version": 2,
        "source_version": "starhome_lz_ry",
        "source": str(source.resolve()),
        "source_logical_path": source_logical,
        "source_parsed_logical_path": parsed_logical,
        "source_md5": source_md5,
        "source_sha256": file_hash(source, "sha256"),
        "source_evidence": [
            "荣耀版 loadfile/npcinfo_xc/npcinfo_xc.tab.cab runtime animation catalog",
            "荣耀版 npcclt1/npcclt1.fcc.cab class and palette mapping",
            "Glory raw ALE geometry verified against Glory parsed frames.json",
        ],
        "container": ale.container,
        "ale_version": ale.version,
        "frame_count": ale.frame_count,
        "animation_semantics": "business_role_from_target_directory",
        "default_preview_fps": 10.0,
        "normalized_cell": {
            "width": cell_width,
            "height": cell_height,
            "entity_pivot": [-left, -top],
            "coordinate_bounds": [left, top, right, bottom],
        },
        "rgba_atlases": [res_path(rgba_path)],
        "indexed_atlases": [res_path(indexed_path)] if indexed_atlas is not None else [],
        "embedded_palette": res_path(embedded_path) if ale.palette is not None else None,
        "godot_sprite_frames": res_path(tres_path),
        "godot_scene": res_path(preview_path),
        "frames": frame_rows,
    }
    if palette_source and palette_logical:
        metadata.update(
            {
                "palette_source": str(palette_source.resolve()),
                "palette_source_logical_path": palette_logical,
                "palette_md5": file_hash(palette_source, "md5"),
                "rendering": "Glory ALE index/alpha rendered through Glory ACT palette",
            }
        )
    else:
        metadata["rendering"] = "Glory ALE embedded palette"
    atomic_json(target / "import_metadata.json", metadata)
    return {
        "asset_directory": target_relative,
        "source_logical_path": source_logical,
        "source_md5": source_md5,
        "palette_source_logical_path": palette_logical,
        "frames": ale.frame_count,
        "cell": [cell_width, cell_height],
    }


def remove_obsolete() -> list[dict[str, str]]:
    import shutil

    removed: list[dict[str, str]] = []
    root = MONSTER_ROOT.resolve()
    for relative, reason in REMOVED.items():
        target = (MONSTER_ROOT / Path(relative)).resolve()
        if root not in target.parents:
            raise RuntimeError(f"unsafe removal target: {target}")
        if target.is_dir():
            shutil.rmtree(target)
        removed.append({"asset_directory": relative, "reason": reason})
    return removed


def migrate() -> None:
    decoder = load_decoder()
    rows = []
    for number, (relative, (ale_key, palette_key)) in enumerate(ASSETS.items(), 1):
        rows.append(export_asset(relative, ale_key, palette_key, decoder))
        print(f"MIGRATE {number:02d}/{len(ASSETS)} {relative}", flush=True)
    removed = remove_obsolete()

    palette_rows = []
    for relative, palette_key in PALETTE_OUTPUTS.items():
        source_logical = PALETTES[palette_key]
        source = GLORY_RAW / Path(source_logical)
        colors = act_colors(source)
        image = Image.new("RGBA", (256, 1))
        image.putdata(colors)
        target = MONSTER_ROOT / Path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target, optimize=True)
        image.close()
        palette_rows.append(
            {
                "asset": relative,
                "source_logical_path": source_logical,
                "source_md5": file_hash(source, "md5"),
            }
        )

    atomic_json(
        MONSTER_ROOT / "source_manifest.json",
        {
            "schema_version": 1,
            "source_version": "starhome_lz_ry",
            "source_roots": {
                "raw": str(GLORY_RAW.resolve()),
                "parsed": str(GLORY_PARSED.resolve()),
            },
            "evidence": [
                "starhome_lz_ry_full_parsed/ftc_resources/expanded/loadfile/npcinfo_xc/npcinfo_xc.tab.cab",
                "starhome_lz_ry_full_parsed/ftc_resources/expanded/npcclt1/npcclt1.fcc.cab",
            ],
            "animations": rows,
            "palettes": palette_rows,
            "removed_non_glory_formal_assets": removed,
        },
    )


def audit() -> dict[str, Any]:
    errors: list[str] = []
    metadata_files = sorted(MONSTER_ROOT.rglob("import_metadata.json"))
    for path in metadata_files:
        metadata = json.loads(path.read_text(encoding="utf-8"))
        label = path.relative_to(PROJECT_ROOT).as_posix()
        if metadata.get("source_version") != "starhome_lz_ry":
            errors.append(f"{label}: source_version is not starhome_lz_ry")
            continue
        source = Path(str(metadata.get("source", "")))
        try:
            source.resolve().relative_to(GLORY_RAW.resolve())
        except (ValueError, OSError):
            errors.append(f"{label}: source is outside Glory raw root")
            continue
        if not source.is_file():
            errors.append(f"{label}: source does not exist")
        elif file_hash(source, "md5") != metadata.get("source_md5"):
            errors.append(f"{label}: source MD5 changed")
        parsed = GLORY_PARSED / Path(str(metadata.get("source_parsed_logical_path", "")))
        if not (parsed / "frames.json").is_file():
            errors.append(f"{label}: parsed Glory frames missing")
        for field in ("rgba_atlases", "indexed_atlases"):
            for resource in metadata.get(field, []):
                local = PROJECT_ROOT / resource.removeprefix("res://")
                if not local.is_file():
                    errors.append(f"{label}: missing {field} resource {resource}")
        rgba_resources = metadata.get("rgba_atlases", [])
        if len(rgba_resources) != 1:
            errors.append(f"{label}: expected exactly one normalized RGBA atlas")
        else:
            rgba_path = PROJECT_ROOT / rgba_resources[0].removeprefix("res://")
            if rgba_path.is_file():
                with Image.open(rgba_path) as image:
                    cell = metadata["normalized_cell"]
                    expected_size = (cell["width"] * metadata["frame_count"], cell["height"])
                    if image.size != expected_size:
                        errors.append(
                            f"{label}: atlas size {image.size} differs from {expected_size}"
                        )
        tres = PROJECT_ROOT / str(metadata["godot_sprite_frames"]).removeprefix("res://")
        if not tres.is_file():
            errors.append(f"{label}: SpriteFrames missing")
        else:
            text = tres.read_text(encoding="utf-8")
            if text.count('[sub_resource type="AtlasTexture"') != metadata["frame_count"]:
                errors.append(f"{label}: SpriteFrames region count differs from metadata")

    searched = [
        path
        for path in MONSTER_ROOT.rglob("*")
        if path.is_file() and path.suffix.casefold() in {".json", ".tres", ".tscn", ".import"}
    ] + [CATALOG_PATH]
    forbidden = ("starhome_lz_fr", "免费版")
    for path in searched:
        if not path.is_file():
            errors.append(f"missing audit input: {path}")
            continue
        text = path.read_text(encoding="utf-8")
        for token in forbidden:
            if token.casefold() in text.casefold():
                errors.append(f"{path.relative_to(PROJECT_ROOT).as_posix()}: forbidden source token {token}")

    actual_groups = {
        path.parent.relative_to(MONSTER_ROOT).as_posix() for path in metadata_files
    }
    expected_groups = set(ASSETS)
    for missing in sorted(expected_groups - actual_groups):
        errors.append(f"expected migrated asset missing: {missing}")
    for unknown in sorted(actual_groups - expected_groups):
        errors.append(f"unexpected unaudited monster asset: {unknown}")

    return {
        "source_version": "starhome_lz_ry",
        "animation_groups": len(metadata_files),
        "expected_animation_groups": len(ASSETS),
        "removed_groups": len(REMOVED),
        "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrate", action="store_true", help="rebuild checked-in monster assets")
    args = parser.parse_args()
    if args.migrate:
        migrate()
    result = audit()
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 1 if result["errors"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
