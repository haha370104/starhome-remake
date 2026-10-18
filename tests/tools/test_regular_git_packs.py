"""Prove independently mountable ZIP splitting preserves order and payloads."""
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from asset_pipeline.regular_git import split_pack


class RegularGitPacksTest(unittest.TestCase):
    def test_split_preserves_bytes_names_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'maps.zip'
            expected = [(f'content/map_{i}/floor.png', bytes([i]) * 1500) for i in range(5)]
            with zipfile.ZipFile(source, 'w') as archive:
                for name, payload in expected:
                    archive.writestr(name, payload)
            parts, count = split_pack(source, root / 'parts', 5000)
            self.assertEqual(count, 5)
            self.assertGreater(len(parts), 1)
            actual = []
            for part in parts:
                self.assertLessEqual(part.stat().st_size, 5000)
                with zipfile.ZipFile(part) as archive:
                    actual.extend((name, archive.read(name)) for name in archive.namelist())
            self.assertEqual(actual, expected)

    def test_oversized_member_rejected_without_slicing(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'map.zip'
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('content/floor.png', b'x' * 5000)
            with self.assertRaisesRegex(ValueError, 'One member exceeds'):
                split_pack(source, root / 'parts', 2000)
            self.assertFalse(list((root / 'parts').glob('*.zip')))

    def test_existing_outputs_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'map.zip'
            with zipfile.ZipFile(source, 'w') as archive:
                archive.writestr('content/floor.png', b'x')
            split_pack(source, root / 'parts', 2000)
            with self.assertRaises(FileExistsError):
                split_pack(source, root / 'parts', 2000)


if __name__ == '__main__':
    unittest.main()
