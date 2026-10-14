"""Pack decoded sprites without changing logical source names."""
from __future__ import annotations
import json
from pathlib import Path
from PIL import Image
from .ale_sprite import AleFile, AexFile

def _new_page(size: int) -> Image.Image:
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def build_sheets(sprite: AleFile | AexFile, output_dir: str | Path, max_sheet_size: int = 8192) -> dict:
    """Pack decoded frames into PNG pages and write frames.json."""
    output = Path(output_dir)
    output.mkdir(parents=True, exist_ok=True)
    if max_sheet_size < 1:
        raise ValueError("max_sheet_size must be positive")
    if not sprite.frames:
        raise ValueError("sprite contains no frames")

    pages: list[Image.Image] = []
    rows: list[dict] = []
    page = _new_page(max_sheet_size)
    pages.append(page)
    page_index = 0
    cursor_x = 0
    cursor_y = 0
    shelf_height = 0

    for frame in sprite.frames:
        # Preserve empty timing frames as a transparent pixel while recording
        # their original dimensions separately.
        packed_width = max(1, frame.width)
        packed_height = max(1, frame.height)
        if packed_width > max_sheet_size or packed_height > max_sheet_size:
            raise ValueError(
                f"frame {frame.index} ({packed_width}x{packed_height}) exceeds sheet limit {max_sheet_size}"
            )
        if cursor_x + packed_width > max_sheet_size:
            cursor_x = 0
            cursor_y += shelf_height
            shelf_height = 0
        if cursor_y + packed_height > max_sheet_size:
            page = _new_page(max_sheet_size)
            pages.append(page)
            page_index += 1
            cursor_x = 0
            cursor_y = 0
            shelf_height = 0

        if frame.width > 0 and frame.height > 0:
            page.alpha_composite(frame.image, (cursor_x, cursor_y))

        row = {
            "index": frame.index,
            "page": page_index,
            "x": cursor_x,
            "y": cursor_y,
            "width": frame.width,
            "height": frame.height,
            "origin_x": frame.origin_x,
            "origin_y": frame.origin_y,
        }
        if frame.metadata:
            row["metadata"] = frame.metadata
        if isinstance(sprite, AexFile):
            row["source_x"] = frame.source_x
            row["source_y"] = frame.source_y
        rows.append(row)

        cursor_x += packed_width
        shelf_height = max(shelf_height, packed_height)

    # Crop each atlas page to used bounds so 8192 is only a packing ceiling.
    page_names: list[str] = []
    page_rows: dict[int, list[dict]] = {}
    for row in rows:
        page_rows.setdefault(int(row["page"]), []).append(row)
    for index, image in enumerate(pages):
        used = page_rows.get(index, [])
        max_x = max((int(row["x"]) + max(1, int(row["width"])) for row in used), default=1)
        max_y = max((int(row["y"]) + max(1, int(row["height"])) for row in used), default=1)
        cropped = image.crop((0, 0, max_x, max_y))
        name = "sheet.png" if len(pages) == 1 else f"sheet_{index:03d}.png"
        cropped.save(output / name, compress_level=3)
        cropped.close()
        image.close()
        page_names.append(name)

    manifest = {
        "format": "starhome_ale_sprites_v1",
        "source": str(sprite.path),
        "container": "AEX" if isinstance(sprite, AexFile) else sprite.wrapper,
        "version": int(sprite.version),
        "frame_count": len(rows),
        "cell_width": max((frame.width for frame in sprite.frames), default=0),
        "cell_height": max((frame.height for frame in sprite.frames), default=0),
        "pages": page_names,
        "frames": rows,
    }
    if isinstance(sprite, AexFile):
        manifest["aex_blob_sizes"] = list(sprite.blob_sizes)
        manifest["aex_key"] = sprite.key.decode("latin1")
    elif sprite.palette_bgra is not None:
        manifest["palette_bgra_hex"] = sprite.palette_bgra.hex()

    (output / "frames.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest


