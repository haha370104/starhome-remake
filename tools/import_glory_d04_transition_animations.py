#!/usr/bin/env python3
"""从荣耀版 ``sportimg/as1-as8`` 恢复 D04 八方向传送器动画。"""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
GLORY_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
MAP_PATH = PROJECT_ROOT / "data" / "maps" / "d04_field_zone.json"
TARGET_ROOT = PROJECT_ROOT / "assets" / "maps" / "shared" / "directional_transitions"
TARGET_CATALOG = PROJECT_ROOT / "data" / "presentation" / "map_transition_marker_catalog.json"

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

DIRECTION_BY_STYLE = {
    1: "east",
    2: "south_east",
    3: "south",
    4: "south_west",
    5: "west",
    6: "north_west",
    7: "north",
    8: "north_east",
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


def _resource_text(texture_path: Path, width: int, height: int, frame_count: int) -> str:
    """为 ``texture_path`` 构造按 100 毫秒播放全部源帧的循环资源。"""
    relative = texture_path.relative_to(PROJECT_ROOT).as_posix()
    subresources: list[str] = []
    entries: list[str] = []
    for index in range(frame_count):
        subresources.extend([
            f'[sub_resource type="AtlasTexture" id="frame_{index}"]',
            'atlas = ExtResource("texture")',
            f"region = Rect2({index * width}, 0, {width}, {height})",
            "filter_clip = true",
            "",
        ])
        entries.append(f'{{"duration": 1.0, "texture": SubResource("frame_{index}")}}')
    return (
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]\n\n'
        f'[ext_resource type="Texture2D" path="res://{relative}" id="texture"]\n\n'
        + "\n".join(subresources)
        + '[resource]\nanimations = [{\n"frames": ['
        + ", ".join(entries)
        + '],\n"loop": true,\n"name": &"active",\n"speed": 10.0\n}]\n'
    )


def _export_direction(legacy_style: int) -> dict[str, Any]:
    """按 ``frames.json`` 导出一个方向的全部源帧并返回共享表现元数据。"""
    legacy_name = f"as{legacy_style}"
    direction = DIRECTION_BY_STYLE[legacy_style]
    raw_path = GLORY_RAW / "pic3" / "interface" / "sportimg" / f"{legacy_name}.ale"
    parsed_root = GLORY_PARSED / "pic3" / "interface" / "sportimg" / legacy_name
    frames = json.loads((parsed_root / "frames.json").read_text(encoding="utf-8"))
    source_frames: list[dict[str, Any]] = frames["frames"]
    if not source_frames:
        raise ValueError(f"{legacy_name} has no frames")
    minimum_origin_x = min(int(frame["origin_x"]) for frame in source_frames)
    minimum_origin_y = min(int(frame["origin_y"]) for frame in source_frames)
    maximum_right = max(int(frame["origin_x"]) + int(frame["width"]) for frame in source_frames)
    maximum_bottom = max(int(frame["origin_y"]) + int(frame["height"]) for frame in source_frames)
    width = maximum_right - minimum_origin_x
    height = maximum_bottom - minimum_origin_y
    atlas = Image.new("RGBA", (width * len(source_frames), height))
    opened_pages: dict[int, Image.Image] = {}
    try:
        for index, frame in enumerate(source_frames):
            page_index = int(frame["page"])
            if page_index not in opened_pages:
                opened_pages[page_index] = Image.open(parsed_root / frames["pages"][page_index]).convert("RGBA")
            page = opened_pages[page_index]
            crop = page.crop((
                int(frame["x"]),
                int(frame["y"]),
                int(frame["x"]) + width,
                int(frame["y"]) + height,
            ))
            atlas.alpha_composite(crop, (
                index * width + int(frame["origin_x"]) - minimum_origin_x,
                int(frame["origin_y"]) - minimum_origin_y,
            ))
            crop.close()
    finally:
        for page in opened_pages.values():
            page.close()
    target = TARGET_ROOT / direction
    target.mkdir(parents=True, exist_ok=True)
    texture_path = target / "frames.png"
    atlas.save(texture_path, optimize=True)
    atlas.close()
    _atomic_text(
        target / "animation_frames.tres",
        _resource_text(texture_path, width, height, len(source_frames)),
    )
    audit = {
        "source_release": "starhome_lz_ry",
        "source_logical_path": f"pic3/interface/sportimg/{legacy_name}.ale",
        "source_sha256": _sha256(raw_path),
        "source_frames_json": f"starhome_lz_ry_full_parsed/ale_sprites/pic3/interface/sportimg/{legacy_name}/frames.json",
        "extraction_policy": "all_frames_in_source_order",
        "legacy_playdelay_ms": 100,
        "direction": direction,
        "frame_count": len(source_frames),
    }
    _atomic_text(target / "import_metadata.json", json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
    return {
        "asset_id": f"maps/shared/directional_transitions/{direction}",
        "resource": f"res://assets/maps/shared/directional_transitions/{direction}/animation_frames.tres",
        "animation": "active",
        "offset": [minimum_origin_x, minimum_origin_y],
        "centered": False,
        "interaction_rect": [0, 0, width, height],
        "interaction_space": "asset_local_fixed_bounds",
        "frame_count": len(source_frames),
        "frame_duration_ms": 100,
        "loop": True,
    }


def _transition_presentation(direction: str) -> dict[str, Any]:
    """返回地图侧只含方向语义、不重复资源细节的公共组件声明。"""
    return {
        "kind": "directional_transition",
        "orientation": direction,
        "activation": "enabled_transition",
    }


def main() -> int:
    """导出八方向共享传送动画并把 D04 出口绑定到对应方向。"""
    global MAP_DATA
    MAP_DATA = json.loads(MAP_PATH.read_text(encoding="utf-8"))
    direction_assets = {style: _export_direction(style) for style in DIRECTION_BY_STYLE}
    marker_catalog = {
        "schema_version": 1,
        "markers": {
            DIRECTION_BY_STYLE[style]: direction_assets[style]
            for style in DIRECTION_BY_STYLE
        },
    }
    _atomic_text(TARGET_CATALOG, json.dumps(marker_catalog, ensure_ascii=False, indent=2) + "\n")
    for transition in MAP_DATA["transitions"]:
        transition_id = str(transition["transition_id"])
        transition["presentation"] = _transition_presentation(
            DIRECTION_BY_STYLE[STYLE_BY_TRANSITION[transition_id]],
        )
    _atomic_text(MAP_PATH, json.dumps(MAP_DATA, ensure_ascii=False, indent=2) + "\n")
    print(f"exported {len(MAP_DATA['transitions'])} D04 transition animations")
    return 0


MAP_DATA: dict[str, Any] = {}


if __name__ == "__main__":
    raise SystemExit(main())
