#!/usr/bin/env python3
"""Restore D04 transition views from same-release Glory directional markers.

The original D04 script references four-frame ``jt-*`` files that now return
404 from the official update host and are absent from every recovered package.
This importer therefore creates an explicit four-frame pulse from the closest
same-release ``lmt-jt-*`` marker and records that fallback in source audit data.
"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from PIL import Image, ImageEnhance


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
GLORY_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
MAP_PATH = PROJECT_ROOT / "data" / "maps" / "d04_field_zone.json"
TARGET_ROOT = PROJECT_ROOT / "assets" / "maps" / "exploration" / "d04_field_zone" / "transitions"

# Transition business ID -> legacy style retained only inside this import tool/audit.
STYLE_BY_TRANSITION = {
    "exit_to_c03_field": 4,
    "exit_to_c04_field": 5,
    "exit_to_c05_field": 6,
    "enter_city_via_northwest_gate": 8,
    "enter_city_via_southwest_gate": 2,
    "enter_city_via_southeast_gate": 4,
    "enter_city_via_northeast_gate": 6,
    "exit_to_d03_field": 3,
    "exit_to_d05_field": 7,
    "exit_to_e03_field": 2,
    "exit_to_e04_field": 1,
    "exit_to_e05_field": 8,
}


def _atomic_text(path: Path, content: str) -> None:
    """Atomically write UTF-8 ``content`` to ``path``."""
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def _sha256(path: Path) -> str:
    """Return the SHA-256 digest for ``path``."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _resource_text(texture_path: Path, width: int, height: int) -> str:
    """Build a four-frame looping SpriteFrames resource for ``texture_path``."""
    relative = texture_path.relative_to(PROJECT_ROOT).as_posix()
    subresources: list[str] = []
    entries: list[str] = []
    for index in range(4):
        subresources.extend([
            f'[sub_resource type="AtlasTexture" id="frame_{index}"]',
            'atlas = ExtResource("texture")',
            f"region = Rect2({index * width}, 0, {width}, {height})",
            "filter_clip = true",
            "",
        ])
        entries.append(f'{{"duration": 1.0, "texture": SubResource("frame_{index}")}}')
    return (
        '[gd_resource type="SpriteFrames" load_steps=6 format=3]\n\n'
        f'[ext_resource type="Texture2D" path="res://{relative}" id="texture"]\n\n'
        + "\n".join(subresources)
        + '[resource]\nanimations = [{\n"frames": ['
        + ", ".join(entries)
        + '],\n"loop": true,\n"name": &"active",\n"speed": 8.0\n}]\n'
    )


def _export_transition(transition_id: str, legacy_style: int) -> dict[str, Any]:
    """Export one business-named four-frame transition and return presentation metadata."""
    fallback_style = 7 if legacy_style == 8 else legacy_style
    legacy_name = f"lmt-jt-{fallback_style:02d}"
    raw_path = GLORY_RAW / "pic3" / "interface" / "sportimg" / f"{legacy_name}.ale"
    parsed_root = GLORY_PARSED / "pic3" / "interface" / "sportimg" / legacy_name
    frames = json.loads((parsed_root / "frames.json").read_text(encoding="utf-8"))
    frame = frames["frames"][0]
    with Image.open(parsed_root / "sheet.png") as sheet:
        base = sheet.convert("RGBA").crop((
            int(frame["x"]),
            int(frame["y"]),
            int(frame["x"]) + int(frame["width"]),
            int(frame["y"]) + int(frame["height"]),
        ))
    width, height = base.size
    atlas = Image.new("RGBA", (width * 4, height))
    for index, factor in enumerate((0.48, 0.72, 1.0, 0.72)):
        pulse = ImageEnhance.Brightness(base).enhance(factor)
        alpha = pulse.getchannel("A").point(lambda value, f=factor: round(value * (0.55 + 0.45 * f)))
        pulse.putalpha(alpha)
        atlas.alpha_composite(pulse, (index * width, 0))
        pulse.close()
    base.close()
    target = TARGET_ROOT / transition_id
    target.mkdir(parents=True, exist_ok=True)
    texture_path = target / "frames.png"
    atlas.save(texture_path, optimize=True)
    atlas.close()
    _atomic_text(target / "animation_frames.tres", _resource_text(texture_path, width, height))
    audit = {
        "source_release": "starhome_lz_ry",
        "source_logical_path": f"pic3/interface/sportimg/{legacy_name}.ale",
        "source_sha256": _sha256(raw_path),
        "missing_original_reference": f"map/mapimg/ani/CHN_2005_06_28_19_32_06_50/jt-{legacy_style:02d}..ale",
        "missing_original_http_status": 404,
        "fallback_policy": "same_release_directional_marker_four_frame_pulse",
        "frame_count": 4,
    }
    _atomic_text(target / "import_metadata.json", json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    anchor = next(item["source_anchor"] for item in MAP_DATA["transitions"] if item["transition_id"] == transition_id)
    asset_id = f"maps/exploration/d04_field_zone/transitions/{transition_id}"
    return {
        "asset_id": asset_id,
        "kind": "animated_sprite",
        "resource": f"res://assets/maps/exploration/d04_field_zone/transitions/{transition_id}/animation_frames.tres",
        "animation": "active",
        "anchor": anchor,
        "offset": [int(frame["origin_x"]), int(frame["origin_y"])],
        "centered": False,
        "interaction_rect": [0, 0, width, height],
        "interaction_space": "asset_local_fixed_bounds",
        "sort_baseline": anchor[1],
        "frame_count": 4,
        "frame_duration_ms": 125,
        "loop": True,
        "activation": "enabled_transition",
    }


def main() -> int:
    """Generate D04 transition resources and attach them to the map definition."""
    global MAP_DATA
    MAP_DATA = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    for transition in MAP_DATA["transitions"]:
        transition_id = str(transition["transition_id"])
        transition["presentation"] = _export_transition(
            transition_id,
            STYLE_BY_TRANSITION[transition_id],
        )
    _atomic_text(MAP_PATH, json.dumps(MAP_DATA, ensure_ascii=False, indent=2) + "\n")
    print(f"exported {len(MAP_DATA['transitions'])} D04 transition animations")
    return 0


MAP_DATA: dict[str, Any] = {}


if __name__ == "__main__":
    raise SystemExit(main())
