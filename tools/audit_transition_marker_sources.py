#!/usr/bin/env python3
"""审计正式地图传送点的源素材关联、屏幕方向与 jt/as 字节等价证据。"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
CATALOG_PATH = PROJECT_ROOT / "data/presentation/map_transition_marker_catalog.json"
MAP_PATHS = (
    PROJECT_ROOT / "data/maps/yian_harbor_hall_floor_1.json",
    PROJECT_ROOT / "data/maps/yian_harbor_city.json",
    PROJECT_ROOT / "data/maps/d04_field_zone.json",
    PROJECT_ROOT / "data/maps/g08_field_zone.json",
)
FALLBACK_RAW = (
    OUTPUTS_ROOT
    / "starhome_lz_ry_full_parsed"
    / "official_lazy_cache"
    / "free_version_transition_fallback"
    / "raw"
)
STYLE_DIRECTIONS = {
    1: "east",
    2: "north_east",
    3: "north",
    4: "north_west",
    5: "west",
    6: "south_west",
    7: "south",
    8: "south_east",
}


def _read_json(path: Path) -> dict[str, Any]:
    """读取一个 UTF-8 JSON 对象。"""
    return json.loads(path.read_text(encoding="utf-8"))


def _sha256(path: Path) -> str:
    """计算文件的小写 SHA-256。"""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _style_from_source_icon(source_icon: str) -> tuple[int, str] | None:
    """从源 ALE 路径解析样式编号及业务化标记家族。"""
    house = re.search(r"(?:^|/)as([1-8])\.ale$", source_icon, re.IGNORECASE)
    if house is not None:
        return int(house.group(1)), "house_directional_marker"
    field = re.search(r"(?:^|/)jt-0?([1-8])\.+ale$", source_icon, re.IGNORECASE)
    if field is not None:
        return int(field.group(1)), "field_directional_marker"
    return None


def main() -> int:
    """校验八方向目录、23 条地图关联和跨版本 jt/as 等价证据。"""
    errors: list[str] = []
    catalog = _read_json(CATALOG_PATH).get("markers", {})
    for style, direction in STYLE_DIRECTIONS.items():
        metadata_path = (
            PROJECT_ROOT
            / "assets/maps/shared/directional_transitions"
            / direction
            / "import_metadata.json"
        )
        fallback_path = FALLBACK_RAW / f"source_style_{style:02d}.ale"
        if not metadata_path.is_file() or not fallback_path.is_file():
            errors.append(f"style {style} 缺少导入元数据或 jt 回退证据")
            continue
        metadata = _read_json(metadata_path)
        equivalence = metadata.get("source_equivalence", {})
        if metadata.get("direction") != direction:
            errors.append(f"style {style} 屏幕方向应为 {direction}")
        if metadata.get("source_logical_path") != f"pic3/interface/sportimg/as{style}.ale":
            errors.append(f"style {style} 荣耀 as 溯源错误")
        fallback_hash = _sha256(fallback_path)
        if (
            equivalence.get("fallback_sha256") != fallback_hash
            or metadata.get("source_sha256") != fallback_hash
            or equivalence.get("byte_identical_to_glory_directional_marker") is not True
        ):
            errors.append(f"style {style} 的免费版 jt 与荣耀版 as 不再字节等价")
        resource = str(catalog.get(direction, {}).get("resource", ""))
        expected_resource = (
            f"res://assets/maps/shared/directional_transitions/{direction}/animation_frames.tres"
        )
        if resource != expected_resource:
            errors.append(f"style {style} 公共资源路径与屏幕方向不一致")

    transition_count = 0
    for map_path in MAP_PATHS:
        map_data = _read_json(map_path)
        for transition in map_data.get("transitions", []):
            transition_count += 1
            audit = transition.get("source_audit", {})
            source_icon = str(audit.get("source_icon_ale", ""))
            parsed = _style_from_source_icon(source_icon)
            label = f"{map_data.get('map_id')}/{transition.get('transition_id')}"
            if parsed is None:
                errors.append(f"{label} 缺少可识别的源传送素材")
                continue
            style, family = parsed
            if int(audit.get("source_marker_style", 0)) != style:
                errors.append(f"{label} 的源样式编号与 icon_ale 不一致")
            if str(audit.get("source_marker_family", "")) != family:
                errors.append(f"{label} 的源标记家族与 icon_ale 不一致")
            orientation = str(transition.get("presentation", {}).get("orientation", ""))
            if orientation != STYLE_DIRECTIONS[style]:
                errors.append(f"{label} 未忠实采用源 style {style} 的屏幕方向")

    if transition_count != 23:
        errors.append(f"正式地图传送点数量预期 23，实际 {transition_count}")
    if errors:
        for error in errors:
            print(error)
        return 1
    print("Transition marker source audit passed: 23 source-bound markers, 8 jt/as byte matches")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
