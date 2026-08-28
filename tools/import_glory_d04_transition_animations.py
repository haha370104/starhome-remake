#!/usr/bin/env python3
"""从荣耀版 ``sportimg/as1-as8`` 恢复共享动画并同步正式地图关联。"""

from __future__ import annotations

import hashlib
import json
import os
import re
from pathlib import Path
from typing import Any

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
GLORY_RAW = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw"
GLORY_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
MAP_PATHS = (
    PROJECT_ROOT / "data" / "maps" / "yian_harbor_hall_floor_1.json",
    PROJECT_ROOT / "data" / "maps" / "yian_harbor_city.json",
    PROJECT_ROOT / "data" / "maps" / "d04_field_zone.json",
    PROJECT_ROOT / "data" / "maps" / "g08_field_zone.json",
)
GLORY_MAPS_PARSED = OUTPUTS_ROOT / "starhome_lz_ry_maps_parsed"
FREE_FIELD_MARKER_FALLBACK = (
    OUTPUTS_ROOT
    / "starhome_lz_ry_full_parsed"
    / "official_lazy_cache"
    / "free_version_transition_fallback"
    / "raw"
)
TARGET_ROOT = PROJECT_ROOT / "assets" / "maps" / "shared" / "directional_transitions"
TARGET_CATALOG = PROJECT_ROOT / "data" / "presentation" / "map_transition_marker_catalog.json"

DIRECTION_BY_STYLE = {
    1: "east",
    2: "north_east",
    3: "north",
    4: "north_west",
    5: "west",
    6: "south_west",
    7: "south",
    8: "south_east",
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
    field_marker_fallback = FREE_FIELD_MARKER_FALLBACK / f"source_style_{legacy_style:02d}.ale"
    if not field_marker_fallback.is_file():
        raise FileNotFoundError(f"missing field marker fallback evidence: {field_marker_fallback}")
    fallback_hash = _sha256(field_marker_fallback)
    if fallback_hash != audit["source_sha256"]:
        raise ValueError(
            f"field jt-{legacy_style:02d} marker differs from Glory as{legacy_style} marker"
        )
    audit["source_equivalence"] = {
        "field_marker_logical_path": (
            "map/mapimg/ani/CHN_2005_06_28_19_32_06_50/"
            f"jt-{legacy_style:02d}..ale"
        ),
        "fallback_release": "starhome_lz_fr",
        "fallback_url": (
            "http://update.ftxjjy.com/gameser/fr_www/map/mapimg/ani/"
            "CHN_2005_06_28_19_32_06_50/"
            f"jt-{legacy_style:02d}..ale"
        ),
        "fallback_sha256": fallback_hash,
        "byte_identical_to_glory_directional_marker": True,
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


def _source_transition_for(runtime_transition: dict[str, Any]) -> dict[str, Any]:
    """按审计输出和源码行号取得原地图明确声明的传送素材关联。"""
    audit = runtime_transition.get("source_audit", {})
    source_output = str(audit.get("source_output", ""))
    source_line = int(audit.get("source_line", 0))
    if not source_output or source_line <= 0:
        raise ValueError(
            f"{runtime_transition.get('transition_id')} lacks source_output/source_line audit"
        )
    source_path = GLORY_MAPS_PARSED / source_output
    if source_path.name.lower() != "transitions.json":
        source_path = source_path / "transitions.json"
    source_data = json.loads(source_path.read_text(encoding="utf-8"))
    candidates = [
        item for item in source_data.get("enabled", [])
        if int(item.get("source_line", 0)) == source_line
        and list(item.get("icon_anchor", [])) == list(runtime_transition.get("source_anchor", []))
    ]
    if "choice_index" in audit:
        candidates = [
            item for item in candidates
            if int(item.get("choice_index", 0)) == int(audit["choice_index"])
        ]
    if len(candidates) != 1:
        raise ValueError(
            f"{runtime_transition.get('transition_id')} expected one source line {source_line}, "
            f"found {len(candidates)}"
        )
    return candidates[0]


def _bind_map_transitions(map_path: Path) -> int:
    """依据源 ``icon_ale`` 为一张正式地图写入业务化八方向表现声明。"""
    map_data = json.loads(map_path.read_text(encoding="utf-8"))
    bound_count = 0
    for transition in map_data.get("transitions", []):
        source_transition = _source_transition_for(transition)
        source_icon = str(source_transition.get("icon_ale", ""))
        house_match = re.search(r"(?:^|/)as([1-8])\.ale$", source_icon, re.IGNORECASE)
        field_match = re.search(r"(?:^|/)jt-0?([1-8])\.+ale$", source_icon, re.IGNORECASE)
        if house_match is None and field_match is None:
            raise ValueError(
                f"{map_data.get('map_id')}/{transition.get('transition_id')} has unsupported "
                f"source icon {source_icon!r}"
            )
        if list(source_transition.get("icon_anchor", [])) != list(transition.get("source_anchor", [])):
            raise ValueError(
                f"{map_data.get('map_id')}/{transition.get('transition_id')} anchor drifted from source"
            )
        style = int((house_match or field_match).group(1))
        transition["presentation"] = _transition_presentation(DIRECTION_BY_STYLE[style])
        transition["source_audit"]["source_icon_ale"] = source_icon
        transition["source_audit"]["source_marker_family"] = (
            "house_directional_marker" if house_match is not None else "field_directional_marker"
        )
        transition["source_audit"]["source_marker_style"] = style
        bound_count += 1
    _atomic_text(map_path, json.dumps(map_data, ensure_ascii=False, indent=2) + "\n")
    return bound_count


def main() -> int:
    """导出八方向动画，并按源地图的 ``icon_ale`` 同步所有正式地图。"""
    direction_assets = {style: _export_direction(style) for style in DIRECTION_BY_STYLE}
    marker_catalog = {
        "schema_version": 1,
        "markers": {
            DIRECTION_BY_STYLE[style]: direction_assets[style]
            for style in DIRECTION_BY_STYLE
        },
    }
    _atomic_text(TARGET_CATALOG, json.dumps(marker_catalog, ensure_ascii=False, indent=2) + "\n")
    bound_count = sum(_bind_map_transitions(map_path) for map_path in MAP_PATHS)
    print(f"exported 8 shared transition animations and source-bound {bound_count} markers")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
