"""Portable decoder tests; optional local original corpus comparison is separate."""
import struct
import io
import tempfile
import unittest
from pathlib import Path

from tools.recovery.maps.pkh_unpack import decode
from tools.recovery.paths import source_path
from tools.recovery.sprites.ale_sprite import AleFile, AexFile, build_sheets
from PIL import Image
from tools.recovery.index.parse_starhome_files_dir import restore_path, decode64_be


def packed(codes, size):
    value = sum(code << (9 * index) for index, code in enumerate(codes))
    return struct.pack('<I', size) + value.to_bytes((9 * len(codes) + 7) // 8, 'little')


class RecoveryTests(unittest.TestCase):
    def test_pkh_dictionary_clear_and_forward_reference(self):
        self.assertEqual(decode(packed([256, 65, 258, 256, 66, 257], 4)), b'AAAB')

    def test_pkh_corruption_and_size_limits(self):
        for value in [b'', packed([256, 258, 257], 1), packed([65, 257], 0),
                      packed([65, 257], 2), packed([65], 1), struct.pack('<I', 100_000_000)]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                decode(value)

    def test_source_paths_cannot_escape(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / 'good.ale').write_bytes(b'abc')
            self.assertEqual(source_path(root, 'good.ale'), root.resolve() / 'good.ale')
            for invalid in ['../other', '..\\other', '/tmp/a', 'C:/a', 'C:a', 'a:stream', '//host/a']:
                with self.subTest(path=invalid), self.assertRaises(ValueError):
                    source_path(root, invalid)

    def test_ale_rgb565_origin_and_sheet_roundtrip(self):
        # One opaque RGB565 red pixel at the original negative origin.
        pixels = struct.pack('<HHHBBH', 1, 1, 4, 0, 1, 0xf800)
        frame = struct.pack('<IIIIii', 24 + len(pixels), 0, 1, 1, -2, 3) + pixels
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.ale'
            path.write_bytes(b'ALE\0' + struct.pack('<HIH', 3, len(frame), 1) + frame)
            sprite = AleFile(path)
            self.assertEqual(sprite.frames[0].image.getpixel((0, 0)), (255, 0, 0, 255))
            self.assertEqual((sprite.frames[0].origin_x, sprite.frames[0].origin_y), (-2, 3))
            metadata = build_sheets(sprite, Path(folder) / 'out', 16)
            self.assertEqual(metadata['frames'][0]['origin_x'], -2)
            path.write_bytes(path.read_bytes()[:-1])
            with self.assertRaises(ValueError): AleFile(path)

    def test_original_index_prefix(self):
        self.assertEqual(restore_path(b'+3new.ale', b'pic/old.ale'), b'picnew.ale')
        self.assertEqual(decode64_be(b'10'), 64)
        with self.assertRaises(ValueError): restore_path(b'+z', b'x')

    def test_sparse_marker_does_not_consume_data_row(self):
        pixels = struct.pack('<HHHHBBH', 1, 0xffff, 1, 4, 0, 1, 0xf800)
        frame = struct.pack('<IIIIii', 24 + len(pixels), 0, 1, 2, 0, 0) + pixels
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.ale'
            path.write_bytes(b'RLE09\0' + struct.pack('<HHIH', 10, 3, len(frame), 1) + frame)
            sprite = AleFile(path)
            self.assertEqual(sprite.frames[0].image.getpixel((0, 1)), (255, 0, 0, 255))
            self.assertEqual(sprite.frames[0].image.getpixel((0, 0))[3], 0)

    def test_aex_one_color_key(self):
        image = Image.new('RGB', (2, 1), 'red')
        image.putpixel((1, 0), (0, 255, 0))
        output = io.BytesIO()
        image.save(output, format='PNG')
        payload = output.getvalue()
        data = b'AEX\0' + b'00000000' + struct.pack('<5I', 1, 1, len(payload), 0, 0)
        data += struct.pack('<6i', 2, 1, 0, 0, 0, 0) + payload
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'source.ale'
            path.write_bytes(data)
            sprite = AexFile(path)
            self.assertEqual(sprite.frames[0].image.getpixel((0, 0))[3], 0)
            self.assertEqual(sprite.frames[0].image.getpixel((1, 0)), (0, 255, 0, 255))


if __name__ == '__main__': unittest.main()
