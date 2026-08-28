"""将荣耀版人物服装 ALE 解析结果规范化为 Godot 八方向图集。"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image


REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
PARSED_ROOT = REPOSITORY_ROOT.parent / "starhome_lz_ry_full_parsed" / "ale_sprites"
OUTPUT_ROOT = REPOSITORY_ROOT / "assets" / "equipment" / "clothing" / "male_sleeveless_shirt"
SOURCES = {
    "move": PARSED_ROOT / "pic3" / "clothing" / "body" / "man" / "mancloth01a",
    "stand": PARSED_ROOT / "pic3" / "clothing" / "stand" / "man" / "mancloth01a",
}


def sha256(path: Path) -> str:
    """计算源文件或生成文件的 SHA-256。"""

    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def normalize_action(action: str, source_dir: Path) -> dict[str, object]:
    """按 ALE origin 统一画布并生成一个动作的八方向图集。"""

    manifest_path = source_dir / "frames.json"
    sheet_path = source_dir / "sheet.png"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    frames = sorted(manifest["frames"], key=lambda frame: int(frame["index"]))
    visible = [frame for frame in frames if int(frame["width"]) > 0 and int(frame["height"]) > 0]
    left = min(int(frame["origin_x"]) for frame in visible)
    top = min(int(frame["origin_y"]) for frame in visible)
    right = max(int(frame["origin_x"]) + int(frame["width"]) for frame in visible)
    bottom = max(int(frame["origin_y"]) + int(frame["height"]) for frame in visible)
    cell_width = right - left
    cell_height = bottom - top
    columns = 8
    rows = (len(frames) + columns - 1) // columns
    source = Image.open(sheet_path).convert("RGBA")
    atlas = Image.new("RGBA", (columns * cell_width, rows * cell_height), (0, 0, 0, 0))
    for frame in frames:
        index = int(frame["index"])
        crop = source.crop(
            (
                int(frame["x"]),
                int(frame["y"]),
                int(frame["x"]) + int(frame["width"]),
                int(frame["y"]) + int(frame["height"]),
            )
        )
        destination = (
            index % columns * cell_width + int(frame["origin_x"]) - left,
            index // columns * cell_height + int(frame["origin_y"]) - top,
        )
        atlas.alpha_composite(crop, destination)
    output_path = OUTPUT_ROOT / f"{action}_atlas.png"
    atlas.save(output_path)
    return {
        "texture": f"res://assets/equipment/clothing/male_sleeveless_shirt/{action}_atlas.png",
        "frame_count": len(frames),
        "columns": columns,
        "cell": [cell_width, cell_height],
        "offset": [left, top],
        "source_frames": str(manifest_path.relative_to(REPOSITORY_ROOT.parent)).replace("\\", "/"),
        "source_sheet_sha256": sha256(sheet_path),
        "output_sha256": sha256(output_path),
    }


def main() -> None:
    """生成服装图集及可审计来源清单。"""

    OUTPUT_ROOT.mkdir(parents=True, exist_ok=True)
    actions = {action: normalize_action(action, source) for action, source in SOURCES.items()}
    source_manifest = {
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "business_asset": "male_sleeveless_shirt",
        "actions": actions,
    }
    (OUTPUT_ROOT / "source_manifest.json").write_text(
        json.dumps(source_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
