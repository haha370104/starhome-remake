"""Exercise the materialized content-tree policy."""
from pathlib import Path
import json
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_asset_size_policy as policy


class ContentMaterializationPolicyTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.manifest = self.root / policy.MANIFEST_RELATIVE
        self.content = self.root / "assets"
        self.content.mkdir()

    def write_manifest(self, *, status="verified_and_removed", entries=None):
        entries = entries or [{"path": "assets/example/asset.bin", "bytes": 3, "sha256": ""}]
        document = {
            "schema_version": 1,
            "namespace": policy.EXPECTED_NAMESPACE,
            "archives": [{"archive": "build/example.zip", "status": status, "entries": entries}],
        }
        self.manifest.parent.mkdir(parents=True, exist_ok=True)
        self.manifest.write_text(json.dumps(document), encoding="utf-8")

    def test_complete_materialization_passes(self):
        path = self.root / "assets/example/asset.bin"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"ok")
        self.write_manifest()
        self.assertEqual(policy.find_violations(self.root), [])

    def test_missing_file_is_rejected(self):
        self.write_manifest()
        self.assertEqual(len(policy.find_violations(self.root)), 1)
        self.assertIn("materialized file is missing", policy.find_violations(self.root)[0])

    def test_unverified_archive_is_rejected(self):
        path = self.root / "assets/example/asset.bin"
        path.parent.mkdir(parents=True)
        path.write_bytes(b"ok")
        self.write_manifest(status="extracting")
        self.assertIn("not verified_and_removed", policy.find_violations(self.root)[0])

    def test_missing_content_tree_is_rejected(self):
        self.content.rmdir()
        self.write_manifest()
        self.assertIn("assets/ is missing", policy.find_violations(self.root)[0])


if __name__ == "__main__":
    unittest.main()
