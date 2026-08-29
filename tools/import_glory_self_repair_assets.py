"""Import the Glory self-repair field and shadow under semantic runtime paths."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
PARSED_ROOT = ROOT.parent / "starhome_lz_ry_full_parsed" / "ale_sprites" / "pic3" / "other"
TARGET_ROOT = ROOT / "assets" / "equipment_world" / "shared" / "self_repair"
SOURCES = {
    "energy_field": PARSED_ROOT / "MinSpan1",
    "ground_shadow": PARSED_ROOT / "MinSpanShadow",
}


def sha256(path: Path) -> str:
    """Return a stable SHA-256 digest for one source artifact."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build_sprite_frames(texture_path: str, frame_count: int, width: int, height: int) -> str:
    """Build one looping SpriteFrames resource over a normalized horizontal atlas."""
    sections = [
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]\n',
        f'[ext_resource type="Texture2D" path="{texture_path}" id="tex_1"]\n',
    ]
    refs: list[str] = []
    for index in range(frame_count):
        sections.append(
            f'[sub_resource type="AtlasTexture" id="frame_{index}"]\n'
            'atlas = ExtResource("tex_1")\n'
            f'region = Rect2({index * width}, 0, {width}, {height})\n'
            'filter_clip = true\n'
        )
        refs.append(
            f'{{"duration": 1.0, "texture": SubResource("frame_{index}")}}'
        )
    sections.append(
        '[resource]\nanimations = [{\n'
        f'"frames": [{", ".join(refs)}],\n'
        '"loop": true,\n"name": &"repair",\n"speed": 20.0\n}]\n'
    )
    return "\n".join(sections)


def import_animation(semantic_name: str, source: Path) -> dict[str, object]:
    """Normalize ALE frame origins into one common atlas and write its Godot resource."""
    metadata_path = source / "frames.json"
    sheet_path = source / "sheet.png"
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
    frames = metadata["frames"]
    minimum_x = min(int(frame["origin_x"]) for frame in frames)
    minimum_y = min(int(frame["origin_y"]) for frame in frames)
    maximum_x = max(int(frame["origin_x"]) + int(frame["width"]) for frame in frames)
    maximum_y = max(int(frame["origin_y"]) + int(frame["height"]) for frame in frames)
    width = maximum_x - minimum_x
    height = maximum_y - minimum_y
    source_sheet = Image.open(sheet_path).convert("RGBA")
    atlas = Image.new("RGBA", (width * len(frames), height), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        crop = source_sheet.crop((
            int(frame["x"]),
            int(frame["y"]),
            int(frame["x"]) + int(frame["width"]),
            int(frame["y"]) + int(frame["height"]),
        ))
        atlas.alpha_composite(crop, (
            index * width + int(frame["origin_x"]) - minimum_x,
            int(frame["origin_y"]) - minimum_y,
        ))
    target = TARGET_ROOT / semantic_name
    target.mkdir(parents=True, exist_ok=True)
    atlas_path = target / "frames.png"
    atlas.save(atlas_path)
    resource_path = target / "animation_frames.tres"
    resource_path.write_text(build_sprite_frames(
        f"res://assets/equipment_world/shared/self_repair/{semantic_name}/frames.png",
        len(frames),
        width,
        height,
    ), encoding="utf-8")
    return {
        "semantic_name": semantic_name,
        "frame_count": len(frames),
        "anchor_offset": [minimum_x, minimum_y],
        "frame_size": [width, height],
        "resource": f"res://assets/equipment_world/shared/self_repair/{semantic_name}/animation_frames.tres",
        "source_release": "starhome_lz_ry",
        "source_logical_path": f"pic3/other/{source.name}.ale",
        "source_frames_sha256": sha256(metadata_path),
        "source_sheet_sha256": sha256(sheet_path),
    }


def main() -> int:
    """Import both layers and write an auditable semantic relationship manifest."""
    records = [import_animation(name, source) for name, source in SOURCES.items()]
    (TARGET_ROOT / "source_manifest.json").write_text(
        json.dumps({"schema_version": 1, "animations": records}, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Imported Glory self-repair animations: {len(records)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
