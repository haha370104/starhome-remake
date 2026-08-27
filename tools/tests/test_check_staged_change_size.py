#!/usr/bin/env python3
"""Black-box tests for the staged change size policy command."""

from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


CHECKER = Path(__file__).resolve().parents[1] / "check_staged_change_size.py"


class StagedChangeSizeTests(unittest.TestCase):
    """Exercise the checker against isolated repositories and real Git indexes."""

    def setUp(self) -> None:
        """Create a committed empty repository for each policy scenario."""

        self._temporary_directory = tempfile.TemporaryDirectory()
        self.repository = Path(self._temporary_directory.name)
        self._git("init", "--quiet")
        self._git("config", "user.email", "staged-size-test@example.invalid")
        self._git("config", "user.name", "Staged Size Test")
        self._git("commit", "--quiet", "--allow-empty", "-m", "initial")

    def tearDown(self) -> None:
        """Delete the isolated repository after a test completes."""

        self._temporary_directory.cleanup()

    def _git(self, *arguments: str) -> subprocess.CompletedProcess[str]:
        """Run Git with *arguments* in the test repository and return its result."""

        return subprocess.run(
            ["git", *arguments],
            cwd=self.repository,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

    def _check(self) -> subprocess.CompletedProcess[str]:
        """Run the staged-size checker in the test repository and return its result."""

        return subprocess.run(
            [sys.executable, str(CHECKER)],
            cwd=self.repository,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def _stage_text_file(self, relative_path: str, line_count: int) -> None:
        """Create [relative_path] with [line_count] text lines and stage it."""

        target = self.repository / relative_path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text("line\n" * line_count, encoding="utf-8")
        self._git("add", "--", relative_path)

    def test_no_staged_changes_succeeds(self) -> None:
        """Accept a clean index as a zero-sized staged change."""

        result = self._check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0/20 paths", result.stdout)

    def test_exact_limits_succeed(self) -> None:
        """Accept exactly 20 paths and exactly 2000 changed text lines."""

        for index in range(20):
            self._stage_text_file(f"text/file_{index:02d}.txt", 100)
        result = self._check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("20/20 paths", result.stdout)
        self.assertIn("2000/2000 text lines", result.stdout)

    def test_more_than_twenty_staged_paths_fails(self) -> None:
        """Reject an index containing 21 changed paths."""

        for index in range(21):
            self._stage_text_file(f"path_{index:02d}.txt", 1)
        result = self._check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("staged paths: 21 exceeds 20", result.stderr)

    def test_more_than_two_thousand_text_lines_fails(self) -> None:
        """Reject a text diff whose additions plus deletions exceed 2000."""

        self._stage_text_file("oversized.txt", 2001)
        result = self._check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("2001 exceeds 2000", result.stderr)

    def test_text_additions_and_deletions_are_summed(self) -> None:
        """Reject a replacement when added and deleted lines jointly exceed 2000."""

        target = self.repository / "replacement.txt"
        target.write_text("before\n" * 1001, encoding="utf-8")
        self._git("add", "--", target.name)
        self._git("commit", "--quiet", "-m", "add replacement fixture")
        target.write_text("after\n" * 1000, encoding="utf-8")
        self._git("add", "--", target.name)
        result = self._check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("2001 exceeds 2000", result.stderr)

    def test_binary_content_counts_only_as_a_path(self) -> None:
        """Accept a large staged binary while reporting no changed text lines."""

        target = self.repository / "large.bin"
        target.write_bytes(b"\x00binary\n" * 5000)
        self._git("add", "--", target.name)
        result = self._check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("0/2000 text lines", result.stdout)
        self.assertIn("1 binary paths", result.stdout)

    def test_unstaged_and_untracked_content_is_ignored(self) -> None:
        """Ensure only the index is measured after staged content diverges from disk."""

        self._stage_text_file("partially_staged.txt", 1)
        (self.repository / "partially_staged.txt").write_text(
            "unstaged\n" * 3000,
            encoding="utf-8",
        )
        (self.repository / "untracked.txt").write_text(
            "untracked\n" * 3000,
            encoding="utf-8",
        )
        result = self._check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("1/2000 text lines", result.stdout)

    def test_checker_does_not_modify_the_index(self) -> None:
        """Verify the staged tree hash is identical before and after inspection."""

        self._stage_text_file("stable_index.txt", 3)
        before = self._git("write-tree").stdout.strip()
        result = self._check()
        after = self._git("write-tree").stdout.strip()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(after, before)


if __name__ == "__main__":
    unittest.main()
