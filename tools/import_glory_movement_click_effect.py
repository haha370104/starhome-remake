#!/usr/bin/env python3
"""Import the Glory right-click movement feedback into a Godot-ready atlas."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
SOURCE_LOGICAL_PATH = Path("pic3/other/goeffect.ale")
SOURCE_PATH = OUTPUTS_ROOT / "starhome_lz_ry_full" / "raw" / SOURCE_LOGICAL_PATH
PARSED_ROOT = (
    OUTPUTS_ROOT
    / "starhome_lz_ry_full_parsed"
    / "ale_sprites"
    / SOURCE_LOGICAL_PATH.with_suffix("")
)
TARGET_ROOT = PROJECT_ROOT / "assets" / "ui" / "world_feedback" / "movement_destination"


def _hash(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _resource_path(path: Path) -> str:
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


def _sprite_frames(texture_path: Path, frame_count: int, width: int, height: int) -> str:
    subresources: list[str] = []
    entries: list[str] = []
    for index in range(frame_count):
        subresources.extend(
            [
                f'[sub_resource type="AtlasTexture" id="frame_{index}"]',
                'atlas = ExtResource("texture")',
                f"region = Rect2({index * width}, 0, {width}, {height})",
                "filter_clip = true",
                "",
            ]
        )
        entries.append(f'{{"duration": 1.0, "texture": SubResource("frame_{index}")}}')
    return (
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]\n\n'
        f'[ext_resource type="Texture2D" path="{_resource_path(texture_path)}" id="texture"]\n\n'
        + "\n".join(subresources)
        + '[resource]\nanimations = [{\n"frames": ['
        + ", ".join(entries)
        + '],\n"loop": false,\n"name": &"play",\n"speed": 10.0\n}]\n'
    )


def main() -> None:
    frames_path = PARSED_ROOT / "frames.json"
    sheet_path = PARSED_ROOT / "sheet.png"
    for required in (SOURCE_PATH, frames_path, sheet_path):
        if not required.is_file():
            raise FileNotFoundError(required)

    parsed = json.loads(frames_path.read_text(encoding="utf-8"))
    frames = parsed["frames"]
    if int(parsed["frame_count"]) != 6 or len(frames) != 6:
        raise RuntimeError("Glory movement click effect must contain exactly six frames")

    visible = [frame for frame in frames if frame["width"] and frame["height"]]
    left = min(int(frame["origin_x"]) for frame in visible)
    top = min(int(frame["origin_y"]) for frame in visible)
    right = max(int(frame["origin_x"]) + int(frame["width"]) for frame in visible)
    bottom = max(int(frame["origin_y"]) + int(frame["height"]) for frame in visible)
    cell_width = right - left
    cell_height = bottom - top

    TARGET_ROOT.mkdir(parents=True, exist_ok=True)
    texture_path = TARGET_ROOT / "frames.png"
    atlas = Image.new("RGBA", (cell_width * len(frames), cell_height))
    with Image.open(sheet_path) as parsed_sheet:
        parsed_sheet = parsed_sheet.convert("RGBA")
        for frame in frames:
            crop = parsed_sheet.crop(
                (
                    int(frame["x"]),
                    int(frame["y"]),
                    int(frame["x"]) + int(frame["width"]),
                    int(frame["y"]) + int(frame["height"]),
                )
            )
            atlas.alpha_composite(
                crop,
                (
                    int(frame["index"]) * cell_width + int(frame["origin_x"]) - left,
                    int(frame["origin_y"]) - top,
                ),
            )
            crop.close()
    atlas.save(texture_path, optimize=True)
    atlas.close()

    resource_path = TARGET_ROOT / "animation_frames.tres"
    resource_path.write_text(
        _sprite_frames(texture_path, len(frames), cell_width, cell_height),
        encoding="utf-8",
        newline="\n",
    )
    metadata = {
        "export_format_version": 1,
        "source_version": "starhome_lz_ry",
        "source_logical_path": SOURCE_LOGICAL_PATH.as_posix(),
        "source_sha256": _hash(SOURCE_PATH),
        "parsed_frames_sha256": _hash(frames_path),
        "parsed_sheet_sha256": _hash(sheet_path),
        "source_evidence": [
            "荣耀版 globalfunclt.fcc GoEffect directly references pic3/other/goeffect.ale",
            "荣耀版 client.fcc OnWalk calls ShowGoEffect before Walkto",
        ],
        "frame_count": len(frames),
        "fps": 10.0,
        "loop": False,
        "normalized_cell": [cell_width, cell_height],
        "coordinate_bounds": [left, top, right, bottom],
        "sprite_offset": [(left + right) / 2.0, (top + bottom) / 2.0],
        "runtime_resource": _resource_path(resource_path),
    }
    (TARGET_ROOT / "import_metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )
    print(f"Imported Glory movement click effect to {TARGET_ROOT}")


if __name__ == "__main__":
    main()
