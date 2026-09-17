"""Verify installed bytes, all frame pivots, explicit approval coverage and arrow equivalence."""
import hashlib
import json
import sys
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from import_remaining_recovered_assets import source_files, SELECTIONS, PACK


class RecoveryPackTest(unittest.TestCase):
    def test_every_selected_source_is_preserved(self):
        selections = json.loads(SELECTIONS.read_text('utf-8'))['selections']
        self.assertEqual(len(selections), 173)
        with zipfile.ZipFile(PACK) as archive:
            self.assertEqual(len(archive.namelist()), len(set(archive.namelist())))
            for row in selections:
                raw, parsed = source_files(row['source_version'], row['source_logical_path'])
                self.assertEqual(hashlib.sha256(raw.read_bytes()).hexdigest(), row['source_sha256'])
                source = json.loads((parsed/'frames.json').read_text('utf-8'))
                root = 'assets/recovered/' + row['asset_path']
                installed = json.loads(archive.read(root+'/frames.json'))
                self.assertEqual(installed['frames'], source['frames'], row['source_reference'])
                self.assertEqual(installed['frame_count'], len(source['frames']))
                for before, after in zip(source['pages'], installed['pages'], strict=True):
                    self.assertEqual((parsed/before).read_bytes(), archive.read(root+'/'+after))

    def test_no_candidate_was_left_out_or_existing_glory_replaced(self):
        report = json.loads((ROOT.parent/'cross_release_asset_review/audit.json').read_text('utf-8'))
        for row in report['records']:
            if not row['glory_now_available'] and row['comparison'] != 'neither_found':
                self.assertIsNotNone(row['runtime_recovery'], row['reference'])
        recovered = json.loads((ROOT/'data/content/recovered_sprite_runtime_index_v1.json').read_text('utf-8'))['sprites']
        glory = json.loads((ROOT/'data/content/glory_sprite_runtime_index_v1.json').read_text('utf-8'))['sprites']
        self.assertEqual(len(recovered), 188)
        self.assertFalse({r['logical_id'] for r in recovered} & {r['logical_id'] for r in glory})

    def test_arrows_equal_existing_shared_markers(self):
        selections = json.loads(SELECTIONS.read_text('utf-8'))['selections']
        arrows = [r for r in selections if '/directional_transitions/' in r['asset_path']]
        self.assertEqual(len(arrows), 8)
        for row in arrows:
            direction = row['asset_path'].rsplit('/', 1)[-1]
            marker = json.loads((ROOT/f'assets/maps/shared/directional_transitions/{direction}/import_metadata.json').read_text('utf-8'))
            self.assertEqual(row['source_sha256'], marker['source_sha256'])


if __name__ == '__main__':
    unittest.main()
