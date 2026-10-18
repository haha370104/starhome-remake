"""Exercise reachability, exact-byte reuse, recovery and deterministic repacking."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'tools'))
from asset_pipeline.runtime_usage import CATALOGS, INDEXES, RuntimeUsage
from asset_pipeline.compact import compact


class RuntimeCompactionTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'game'
        self.archive = Path(self.temp.name) / 'archive'
        self.write('project.godot', '')
        self.write('scripts/main.gd', 'const CONFIG = "res://data/world.json"\n')
        self.write('data/world.json', json.dumps({'texture': 'res://content/map/b.png',
            'effect': 'pic3/used.ale', 'source_animation': 'pic3/used.ale',
            'source_audit': {'texture': 'res://assets/offline.png'},
            'runtime': 'res://assets/runtime.png', 'other': 'res://content/map/a.png'}))
        self.write('assets/runtime.png', b'runtime')
        self.write('assets/runtime.png.import', 'import settings')
        self.write('assets/offline.png', b'offline')
        for index, name in enumerate(CATALOGS):
            self.write('data/content/' + name, json.dumps({'schema_version': 1, 'packs': [] if index else [
                {'pack_id': 'test', 'path': 'res://assets/content_packs/test.zip'}]}))
        sprites = [{'logical_id': 'pic3/' + identity,
                    'frames_path': f'res://content/{identity}/frames.json',
                    'page_paths': [f'res://content/{identity}/page.png']} for identity in ['used', 'unused']]
        for index, name in enumerate(INDEXES):
            self.write('data/content/' + name, json.dumps({'sprites': sprites if index == 0 else []}))
        path = self.root / 'assets/content_packs/test.zip'
        path.parent.mkdir(parents=True)
        with zipfile.ZipFile(path, 'w') as pack:
            for member, payload in [('content/map/a.png', b'identical'), ('content/map/b.png', b'identical'),
                                    ('content/unused/page.png', b'unused'), ('content/used/page.png', b'used'),
                                    ('content/used/frames.json', b'{"frames":[]}'),
                                    ('content/unused/frames.json', b'{"frames":[]}')]:
                pack.writestr(member, payload)

    def write(self, name, payload):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload if isinstance(payload, bytes) else payload.encode())

    def test_runtime_graph_excludes_source_and_unused_index_rows(self):
        usage = RuntimeUsage(self.root).trace()
        self.addCleanup(usage.close)
        self.assertEqual(usage.used_sprites, {'pic3/used'})
        self.assertIn('assets/runtime.png.import', usage.used)
        self.assertNotIn('assets/offline.png', usage.used)
        self.assertNotIn('content/unused/frames.json', usage.used)
        self.assertFalse(usage.missing)

    def test_repack_preserves_bytes_references_and_external_recovery(self):
        before = (self.root/'assets/content_packs/test.zip').read_bytes()
        report = compact(self.root, self.archive, apply=True)
        self.assertEqual((self.archive/'assets/content_packs/test.zip').read_bytes(), before)
        self.assertEqual((self.archive/'assets/offline.png').read_bytes(), b'offline')
        self.assertFalse((self.root/'assets/offline.png').exists())
        config = json.loads((self.root/'data/world.json').read_text())
        self.assertEqual(config['texture'], config['other'])
        with zipfile.ZipFile(self.root/'assets/content_packs/test.zip') as pack:
            self.assertEqual(pack.read(config['texture'].removeprefix('res://')), b'identical')
            self.assertNotIn('content/map/b.png', pack.namelist())
            self.assertNotIn('content/unused/page.png', pack.namelist())
        self.assertEqual(report['runtime_sprites'], 1)
        after = compact(self.root, self.archive)
        self.assertEqual(after['removed_members'], [])
        self.assertEqual(after['removed_loose'], [])
        self.assertEqual(after['aliases'], {})

    def test_refuse_archive_inside_game(self):
        with self.assertRaisesRegex(ValueError, 'outside'):
            compact(self.root, self.root/'backup', apply=True)

    def test_missing_runtime_file_stops_before_any_deletion(self):
        self.write('data/world.json', '{"texture":"res://assets/missing.png"}')
        with self.assertRaisesRegex(ValueError, 'Unresolved'):
            compact(self.root, self.archive, apply=True)
        self.assertTrue((self.root/'assets/offline.png').exists())


if __name__ == '__main__':
    unittest.main()
