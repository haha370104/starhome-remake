"""从荣耀版解析结果导入人物、背包和战车面板所需的最小素材集。"""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = PROJECT_ROOT.parent / "starhome_lz_ry_full_parsed" / "ale_sprites"
RAW_ROOT = PROJECT_ROOT.parent / "starhome_lz_ry_full" / "raw"
OUTPUT_ROOT = PROJECT_ROOT / "assets" / "ui" / "windows"

SINGLE_FRAME_ASSETS = {
    "character/background.png": "pic3/interface/HumanEquipBk",
    "character/body_male.png": "pic3/interface/char/manindlg",
    "character/body_female.png": "pic3/interface/char/womanindlg",
    "inventory/background.png": "pic3/interface/BagBk",
    "vehicle/background.png": "pic3/interface/EquipWndBk",
    "vehicle/preview/chassis.png": "pic3/equip/dlg/tank1",
    "vehicle/preview/engine.png": "pic3/equip/dlg/engine1",
    "vehicle/preview/primary_weapon.png": "pic3/equip/dlg/gun1",
    "inventory/items/recruit_tank.png": "pic3/equip/bag/tank1",
    "inventory/items/beginner_engine.png": "pic3/equip/bag/engine1",
    "inventory/items/recruit_energy_cannon.png": "pic3/equip/bag/gun1",
    "inventory/items/male_sleeveless_shirt.png": "pic3/clothing/bag/man/mancloth01a",
    "character/equipment/male_sleeveless_shirt.png": "pic3/clothing/dlg/man/mancloth01a",
}

MULTI_FRAME_ASSETS = {
    "common/close": "pic3/interface/form/closebuttom",
    "inventory/arrange": "pic3/interface/Bag_Arrange",
}


def sha256(path: Path) -> str:
    """计算文件 SHA-256；path 为待审计文件，返回十六进制摘要。"""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_metadata(source_dir: Path) -> dict:
    """读取 ALE 帧元数据；source_dir 为解析目录，返回已解码字典。"""
    return json.loads((source_dir / "frames.json").read_text(encoding="utf-8"))


def copy_single(relative_output: str, source_relative: str) -> dict:
    """导入单帧素材；两个参数分别为业务输出名和荣耀解析路径，返回来源审计项。"""
    source_dir = SOURCE_ROOT / source_relative
    metadata = load_metadata(source_dir)
    if int(metadata.get("frame_count", 0)) != 1:
        raise ValueError(f"Expected a single frame: {source_relative}")
    destination = OUTPUT_ROOT / relative_output
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_dir / "sheet.png", destination)
    frame = metadata["frames"][0]
    return {
        "path": f"res://assets/ui/windows/{relative_output}",
        "source": str(metadata["source"]).replace("\\", "/"),
        "source_sheet_sha256": sha256(source_dir / "sheet.png"),
        "origin": [int(frame["origin_x"]), int(frame["origin_y"])],
        "size": [int(frame["width"]), int(frame["height"])],
    }


def extract_states(output_prefix: str, source_relative: str) -> dict:
    """将多帧控件拆成业务状态图；参数为输出前缀和荣耀解析路径，返回来源审计项。"""
    source_dir = SOURCE_ROOT / source_relative
    metadata = load_metadata(source_dir)
    sheet = Image.open(source_dir / "sheet.png").convert("RGBA")
    state_names = ("normal", "hover", "pressed")
    states: dict[str, dict] = {}
    output_dir = OUTPUT_ROOT / output_prefix
    output_dir.mkdir(parents=True, exist_ok=True)
    for index, state_name in enumerate(state_names):
        if index >= len(metadata["frames"]):
            break
        frame = metadata["frames"][index]
        image = sheet.crop((
            int(frame["x"]),
            int(frame["y"]),
            int(frame["x"]) + int(frame["width"]),
            int(frame["y"]) + int(frame["height"]),
        ))
        output_path = output_dir / f"{state_name}.png"
        image.save(output_path)
        states[state_name] = {
            "path": f"res://assets/ui/windows/{output_prefix}/{state_name}.png",
            "origin": [int(frame["origin_x"]), int(frame["origin_y"])],
            "size": [int(frame["width"]), int(frame["height"])],
        }
    return {
        "states": states,
        "source": str(metadata["source"]).replace("\\", "/"),
        "source_sheet_sha256": sha256(source_dir / "sheet.png"),
    }


def compose_autofind_dialog(source_path: Path, output_path: Path, size: tuple[int, int]) -> None:
    """按旧引擎 #autofind 九分格导引线拼出指定尺寸的窗体背景。

    source_path 是带蓝色分隔线的源 PNG，output_path 是语义化输出，size 是目标像素尺寸。
    """
    source = Image.open(source_path).convert("RGBA")
    x_ranges = ((2, 135), (149, 279))
    y_ranges = ((2, 59), (69, 125))
    target_width, target_height = size
    fixed_source_width = sum(end - start for start, end in x_ranges)
    left_width = round(target_width * (x_ranges[0][1] - x_ranges[0][0]) / fixed_source_width)
    column_widths = (left_width, target_width - left_width)
    top_height = y_ranges[0][1] - y_ranges[0][0]
    bottom_height = y_ranges[1][1] - y_ranges[1][0]
    middle_height = target_height - top_height - bottom_height
    row_heights = (top_height, middle_height, bottom_height)
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    destination_y = 0
    source_rows = (y_ranges[0], (58, 59), y_ranges[1])
    for row_index, source_y in enumerate(source_rows):
        destination_x = 0
        for column_index, source_x in enumerate(x_ranges):
            tile = source.crop((source_x[0], source_y[0], source_x[1], source_y[1]))
            tile = tile.resize(
                (column_widths[column_index], row_heights[row_index]),
                Image.Resampling.NEAREST,
            )
            output.alpha_composite(tile, (destination_x, destination_y))
            destination_x += column_widths[column_index]
        destination_y += row_heights[row_index]
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output.save(output_path)


def main() -> None:
    """执行幂等导入并写入业务清单；无入参，完成时不返回业务值。"""
    manifest: dict[str, object] = {
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "assets": {},
    }
    for output_name, source_name in SINGLE_FRAME_ASSETS.items():
        manifest["assets"][output_name] = copy_single(output_name, source_name)
    for output_name, source_name in MULTI_FRAME_ASSETS.items():
        manifest["assets"][output_name] = extract_states(output_name, source_name)

    source_background = RAW_ROOT / "pic3" / "interface" / "char" / "manbackground.jpg"
    portrait_background = OUTPUT_ROOT / "character" / "portrait_background.jpg"
    portrait_background.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_background, portrait_background)
    manifest["assets"]["character/portrait_background.jpg"] = {
        "path": "res://assets/ui/windows/character/portrait_background.jpg",
        "source": str(source_background).replace("\\", "/"),
        "source_sha256": sha256(source_background),
    }

    source_skill_background = RAW_ROOT / "pic3" / "interface" / "form" / "minform九分格.png"
    skill_background = OUTPUT_ROOT / "skills" / "background.png"
    compose_autofind_dialog(source_skill_background, skill_background, (240, 375))
    manifest["assets"]["skills/background.png"] = {
        "path": "res://assets/ui/windows/skills/background.png",
        "source": str(source_skill_background).replace("\\", "/"),
        "source_sha256": sha256(source_skill_background),
        "target_size": [240, 375],
    }

    manifest_path = OUTPUT_ROOT / "source_manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Imported {len(manifest['assets'])} panel asset groups")


if __name__ == "__main__":
    main()
