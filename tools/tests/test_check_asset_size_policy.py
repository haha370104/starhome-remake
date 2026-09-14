"""Exercise the asset policy against real parent/submodule Git indexes."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_asset_size_policy as policy


class AssetSizePolicyTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git(self.root, "init")
        self.assets = self.root / "assets"
        self.assets.mkdir()
        self.git(self.assets, "init")
        (self.assets / "README.md").write_text("test assets\n", encoding="utf-8")
        self.git(self.assets, "add", "README.md")
        self.git(self.assets, "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                 "-c", "core.hooksPath=/dev/null", "commit", "-m", "fixture")
        head = self.git(self.assets, "rev-parse", "HEAD").strip()
        self.git(self.root, "update-index", "--add", "--cacheinfo", "160000", head, "assets")

    def git(self, root, *arguments):
        return subprocess.check_output(["git", "-C", str(root), *arguments], stderr=subprocess.PIPE).decode()

    def large_asset(self):
        path = self.assets / "large.png"
        with path.open("wb") as output:
            output.truncate(policy.MAX_REGULAR_GIT_BYTES)
        return path

    def test_untracked_large_asset_in_submodule_is_rejected(self):
        self.large_asset()
        self.assertEqual(len(policy.find_violations(self.root)), 1)
        self.assertIn("assets/large.png", policy.find_violations(self.root)[0])

    def test_submodule_attributes_allow_large_asset(self):
        self.large_asset()
        (self.assets / ".gitattributes").write_text("*.png filter=lfs -text\n", encoding="utf-8")
        self.assertEqual(policy.find_violations(self.root), [])

    def test_parent_attributes_cannot_mask_missing_submodule_policy(self):
        self.large_asset()
        (self.root / ".gitattributes").write_text("assets/** filter=lfs -text\n", encoding="utf-8")
        self.assertEqual(len(policy.find_violations(self.root)), 1)

    def test_uninitialized_submodule_fails_instead_of_passing_empty_scan(self):
        (self.assets / ".git").rename(self.assets / "saved-git")
        with self.assertRaisesRegex(RuntimeError, "not initialized"):
            policy.find_violations(self.root)

    def test_regular_directory_is_rejected(self):
        self.git(self.root, "update-index", "--force-remove", "assets")
        with self.assertRaisesRegex(RuntimeError, "mode 160000"):
            policy.find_violations(self.root)


if __name__ == "__main__":
    unittest.main()
