#!/usr/bin/env python3
"""Recovered StarHome ALE/RLE0/AEX sprite decoder.

Reconstructed from the original Glory client gfx.dll and validated against
representative ALE v1/v3, RLE09 and AEX samples.

Public API expected by starhome-remake tooling:
    AleFile(path)
    AexFile(path)
    build_sheets(sprite, output_dir, max_sheet_size=8192)
"""
from __future__ import annotations

import argparse
import io
import json
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from PIL import Image


def _u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def _u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def _i32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<i", data, offset)[0]


@dataclass
class Frame:
    index: int
    width: int
    height: int
    origin_x: int
    origin_y: int
    image: Image.Image
    metadata: str = ""
    source_x: int = 0
    source_y: int = 0
    # Original container coordinates are retained for indexed-palette importers.
    offset: int = 0
    size: int = 0
    meta_length: int = 0


class AleFile:
    """Decode ALE\0 and RLE09\0 containers."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self.frames: list[Frame] = []
        self.palette_bgra: bytes | None = None
        self.wrapper = ""
        self.version = 0
        self.declared_data_size = 0
        self._parse()

    def _parse(self) -> None:
        data = self.data
        if data.startswith(b"ALE\0"):
            self.wrapper = "ALE"
            if len(data) < 12:
                raise ValueError("truncated ALE header")
            self.version = _u16(data, 4)
            self.declared_data_size = _u32(data, 6)
            frame_count = _u16(data, 10)
            offset = 12
        elif data.startswith(b"RLE09\0"):
            self.wrapper = "RLE0"
            if len(data) < 16:
                raise ValueError("truncated RLE0 header")
            # Offset +6 is the wrapper header size (0x000a in observed files).
            self.version = _u16(data, 8)
            self.declared_data_size = _u32(data, 10)
            frame_count = _u16(data, 14)
            offset = 16
        else:
            raise ValueError(f"unsupported ALE signature: {data[:8]!r}")

        if self.version not in (1, 3):
            raise ValueError(f"unsupported ALE version: {self.version}")

        if self.version == 1:
            if offset + 1024 > len(data):
                raise ValueError("truncated ALE v1 palette")
            self.palette_bgra = data[offset : offset + 1024]
            offset += 1024

        frame_headers: list[tuple[int, int, int, int, int, int, int]] = []
        for index in range(frame_count):
            if offset + 24 > len(data):
                raise ValueError(f"truncated frame header {index}")
            block_size = _u32(data, offset)
            metadata_len = _u32(data, offset + 4)
            width = _u32(data, offset + 8)
            height = _u32(data, offset + 12)
            origin_x = _i32(data, offset + 16)
            origin_y = _i32(data, offset + 20)
            if block_size < 24 or offset + block_size > len(data):
                raise ValueError(
                    f"invalid frame block {index}: offset={offset} size={block_size}"
                )
            if metadata_len > block_size - 24:
                raise ValueError(f"invalid frame metadata length {index}: {metadata_len}")
            frame_headers.append(
                (offset, block_size, metadata_len, width, height, origin_x, origin_y)
            )
            offset += block_size

        for index, header in enumerate(frame_headers):
            frame_offset, _, metadata_len, width, height, origin_x, origin_y = header
            metadata_bytes = data[frame_offset + 24 : frame_offset + 24 + metadata_len]
            metadata = metadata_bytes.rstrip(b"\0").decode("gb18030", errors="replace")
            image = self._decode_frame(frame_offset)
            self.frames.append(
                Frame(
                    index,
                    width,
                    height,
                    origin_x,
                    origin_y,
                    image,
                    metadata,
                    offset=frame_offset,
                    size=header[1],
                    meta_length=metadata_len,
                )
            )

    def _palette_rgba(self, index: int, alpha: Optional[int] = None) -> tuple[int, int, int, int]:
        assert self.palette_bgra is not None
        start = index * 4
        blue, green, red, stored_alpha = self.palette_bgra[start : start + 4]
        return red, green, blue, stored_alpha if alpha is None else alpha

    @staticmethod
    def _rgb565(value: int, alpha: int = 255) -> tuple[int, int, int, int]:
        red5 = (value >> 11) & 0x1F
        green6 = (value >> 5) & 0x3F
        blue5 = value & 0x1F
        red = (red5 << 3) | (red5 >> 2)
        green = (green6 << 2) | (green6 >> 4)
        blue = (blue5 << 3) | (blue5 >> 2)
        return red, green, blue, alpha

    def _decode_frame(self, frame_offset: int) -> Image.Image:
        data = self.data
        block_size = _u32(data, frame_offset)
        metadata_len = _u32(data, frame_offset + 4)
        width = _u32(data, frame_offset + 8)
        height = _u32(data, frame_offset + 12)
        stream = frame_offset + 24 + metadata_len
        block_end = frame_offset + block_size

        # A handful of historical resources are intentionally empty placeholders.
        if width == 0 or height == 0:
            return Image.new("RGBA", (1, 1), (0, 0, 0, 0))
        if stream + 2 > block_end:
            raise ValueError("truncated frame RLE header")

        image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        pixels = image.load()
        line_records = _u16(data, stream)
        stream += 2
        row_offset = 0

        def read_color(pos: int, alpha: Optional[int] = None):
            if self.version == 1:
                if pos >= block_end:
                    raise ValueError("truncated palette pixel")
                return self._palette_rgba(data[pos], alpha), pos + 1
            if pos + 2 > block_end:
                raise ValueError("truncated RGB565 pixel")
            value = _u16(data, pos)
            return self._rgb565(value, 255 if alpha is None else alpha), pos + 2

        for line_index in range(line_records):
            if stream + 2 > block_end:
                raise ValueError(f"truncated line header {line_index}")
            token_count = _u16(data, stream)
            stream += 2

            # The original decoder treats values with either high bit pair set as
            # sparse-row records: negate the signed 16-bit value and add it to the
            # running row displacement. The loop record itself still advances y.
            if token_count & 0xC000:
                row_offset += (-token_count) & 0xFFFF
                continue

            if stream + 2 > block_end:
                raise ValueError(f"truncated line byte count {line_index}")
            encoded_bytes = _u16(data, stream)
            stream += 2
            line_end = stream + encoded_bytes
            if line_end > block_end:
                raise ValueError(f"line {line_index} exceeds frame block")

            y = line_index + row_offset
            x = 0

            for _ in range(token_count):
                if stream + 2 > line_end:
                    raise ValueError(f"truncated RLE token on line {line_index}")
                transparent_skip = data[stream]
                control = data[stream + 1]
                stream += 2
                x += transparent_skip

                if control < 0x80:
                    # 0x00 is an empty run; 0x01..0x7f are fully opaque pixels.
                    for _pixel in range(control):
                        color, stream = read_color(stream)
                        if 0 <= x < width and 0 <= y < height:
                            pixels[x, y] = color
                        x += 1
                    continue

                group = control & 0x60
                if group == 0x20:  # 101xxxxx: additional transparent skip
                    x += control & 0x1F
                    continue

                if group == 0x40:  # 110aaaaa: one final translucent pixel
                    alpha = (control & 0x1F) << 3
                    color, stream = read_color(stream, alpha)
                    if 0 <= x < width and 0 <= y < height:
                        pixels[x, y] = color
                    x += 1
                    continue

                if group == 0x60:  # 111aaaaa: translucent chain, more controls inline
                    chained = control
                    while True:
                        alpha = (chained & 0x1F) << 3
                        color, stream = read_color(stream, alpha)
                        if 0 <= x < width and 0 <= y < height:
                            pixels[x, y] = color
                        x += 1
                        if stream >= line_end:
                            break
                        chained = data[stream]
                        stream += 1
                        chained_group = chained & 0x60
                        if chained_group == 0x60:
                            continue
                        if chained_group == 0x40:
                            alpha = (chained & 0x1F) << 3
                            color, stream = read_color(stream, alpha)
                            if 0 <= x < width and 0 <= y < height:
                                pixels[x, y] = color
                            x += 1
                        elif chained_group == 0x20:
                            x += chained & 0x1F
                        # 100xxxxx is a no-op/terminator in the original routine.
                        break
                    continue

                # 100xxxxx: the original routine performs no pixel operation.

            if stream != line_end:
                raise ValueError(
                    f"line {line_index} RLE length mismatch: {stream} != {line_end}"
                )

        return image


class AexFile:
    """Decode AEX\0 wrappers containing encrypted standard image atlases."""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.data = self.path.read_bytes()
        self.frames: list[Frame] = []
        self.version = 0
        self.key = b""
        self.blob_sizes = (0, 0, 0)
        self._parse()

    @staticmethod
    def _decrypt(payload: bytes, key: bytes) -> bytes:
        if key == b"00000000":
            return payload
        out = bytearray(payload)
        for index in range(len(out)):
            out[index] = (out[index] - key[index & 7]) & 0xFF
        return bytes(out)

    def _parse(self) -> None:
        data = self.data
        if not data.startswith(b"AEX\0") or len(data) < 32:
            raise ValueError("invalid or truncated AEX header")
        self.key = data[4:12]
        frame_count, self.version, size1, size2, size3 = struct.unpack_from("<5I", data, 12)
        self.blob_sizes = (size1, size2, size3)
        if self.version not in (1, 3):
            raise ValueError(f"unsupported AEX version: {self.version}")

        table_end = 32 + frame_count * 24
        expected_size = table_end + size1 + size2 + size3
        if expected_size != len(data):
            raise ValueError(f"AEX size mismatch: header={expected_size}, file={len(data)}")

        descriptors = [
            struct.unpack_from("<6i", data, 32 + index * 24)
            for index in range(frame_count)
        ]

        # gfx.dll reads the payload blocks in this on-disk order:
        #   auxiliary(size3) -> primary(size1) -> alpha(size2)
        # Most files have size3 == 0, which made the more intuitive
        # size1/size2/size3 ordering appear to work until encountering the
        # map AEX variants that carry a 12-byte auxiliary descriptor.
        offset = table_end
        raw3 = data[offset : offset + size3]
        offset += size3
        raw1 = data[offset : offset + size1]
        offset += size1
        raw2 = data[offset : offset + size2]
        offset += size2

        auxiliary = self._decrypt(raw3, self.key) if raw3 else b""
        primary_blob = self._decrypt(raw1, self.key) if raw1 else b""
        alpha_blob = self._decrypt(raw2, self.key) if raw2 else b""
        self.auxiliary = auxiliary

        if not primary_blob:
            raise ValueError("AEX primary atlas is empty")
        primary_source = Image.open(io.BytesIO(primary_blob))
        primary_source.load()
        primary = primary_source.convert("RGBA")

        alpha = None
        if alpha_blob:
            alpha_source = Image.open(io.BytesIO(alpha_blob))
            alpha_source.load()
            # gfx.dll takes the low byte of the secondary pixel. Observed v3
            # alpha atlases are grayscale, so any RGB channel is equivalent.
            alpha = alpha_source.convert("RGB").getchannel("B")

        # blob3 is preserved in metadata via blob_sizes. No observed Glory sample
        # in the recovered corpus subset requires it for pixel composition.
        for index, (width, height, source_x, source_y, origin_x, origin_y) in enumerate(descriptors):
            if width < 0 or height < 0 or source_x < 0 or source_y < 0:
                raise ValueError(f"invalid AEX frame rectangle {index}")
            if source_x + width > primary.width or source_y + height > primary.height:
                raise ValueError(f"AEX frame {index} exceeds primary atlas")
            frame_image = primary.crop(
                (source_x, source_y, source_x + width, source_y + height)
            )
            if self.version == 3 and alpha is not None:
                if source_x + width > alpha.width or source_y + height > alpha.height:
                    raise ValueError(f"AEX frame {index} exceeds alpha atlas")
                frame_alpha = alpha.crop(
                    (source_x, source_y, source_x + width, source_y + height)
                )
                frame_image.putalpha(frame_alpha)
            # Version 1 uses the standard image decoder's own transparency.
            # GIF transparency is retained by Pillow; BMP/JPEG remain opaque.
            self.frames.append(
                Frame(
                    index=index,
                    width=width,
                    height=height,
                    origin_x=origin_x,
                    origin_y=origin_y,
                    image=frame_image,
                    source_x=source_x,
                    source_y=source_y,
                )
            )

        primary.close()
        if alpha is not None:
            alpha.close()


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


def main() -> int:
    parser = argparse.ArgumentParser(description="Decode one StarHome ALE/RLE0/AEX sprite")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--max-sheet-size", type=int, default=8192)
    args = parser.parse_args()
    magic = args.input.read_bytes()[:4]
    sprite = AexFile(args.input) if magic == b"AEX\0" else AleFile(args.input)
    manifest = build_sheets(sprite, args.output, args.max_sheet_size)
    print(json.dumps({
        "source": str(args.input),
        "container": manifest["container"],
        "version": manifest["version"],
        "frames": manifest["frame_count"],
        "pages": len(manifest["pages"]),
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
