#!/usr/bin/env python3
"""Reject oversized staged changes without modifying the Git index.

The check intentionally reads only ``git diff --cached``. Unstaged and untracked
work is outside this policy. A staged change may touch at most 20 paths, and the
sum of added plus deleted lines across text files may not exceed 2000. Git's
binary ``numstat`` entries use ``-`` counts and therefore contribute only to the
path limit.
"""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


MAX_STAGED_PATHS = 20
MAX_STAGED_TEXT_LINES = 2000


@dataclass(frozen=True)
class StagedChangeSize:
    """Summarize the path and text-line footprint currently stored in the index."""

    path_count: int
    text_line_count: int
    binary_path_count: int


def _run_git(repository: Path, arguments: list[str]) -> bytes:
    """Run a read-only Git command in *repository* and return its raw stdout."""

    process = subprocess.run(
        ["git", *arguments],
        cwd=repository,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if process.returncode != 0:
        detail = process.stderr.decode("utf-8", errors="replace").strip()
        raise RuntimeError(detail or "Git command failed")
    return process.stdout


def inspect_staged_change(repository: Path) -> StagedChangeSize:
    """Inspect only staged changes in *repository* and return their size summary.

    ``--no-renames`` makes both sides of a rename count as touched paths. This is
    conservative and keeps path counting independent of Git's rename heuristic.
    """

    names_output = _run_git(
        repository,
        ["diff", "--cached", "--name-only", "-z", "--no-renames"],
    )
    staged_paths = [entry for entry in names_output.split(b"\0") if entry]

    numstat_output = _run_git(
        repository,
        ["diff", "--cached", "--numstat", "-z", "--no-renames"],
    )
    text_line_count = 0
    binary_path_count = 0
    for record in (entry for entry in numstat_output.split(b"\0") if entry):
        fields = record.split(b"\t", 2)
        if len(fields) != 3:
            raise RuntimeError("Unexpected `git diff --cached --numstat -z` output")
        added, deleted, _path = fields
        if added == b"-" or deleted == b"-":
            binary_path_count += 1
            continue
        try:
            text_line_count += int(added) + int(deleted)
        except ValueError as error:
            raise RuntimeError("Git returned a non-numeric text numstat") from error

    return StagedChangeSize(
        path_count=len(staged_paths),
        text_line_count=text_line_count,
        binary_path_count=binary_path_count,
    )


def validate_staged_change(summary: StagedChangeSize) -> list[str]:
    """Return policy violations found in *summary* without changing repository state."""

    failures: list[str] = []
    if summary.path_count > MAX_STAGED_PATHS:
        failures.append(
            f"staged paths: {summary.path_count} exceeds {MAX_STAGED_PATHS}"
        )
    if summary.text_line_count > MAX_STAGED_TEXT_LINES:
        failures.append(
            "staged text additions + deletions: "
            f"{summary.text_line_count} exceeds {MAX_STAGED_TEXT_LINES}"
        )
    return failures


def main() -> int:
    """Check the current repository's index and return a shell-friendly status code."""

    try:
        repository = Path(
            _run_git(Path.cwd(), ["rev-parse", "--show-toplevel"])
            .decode("utf-8", errors="surrogateescape")
            .strip()
        )
        summary = inspect_staged_change(repository)
    except (OSError, RuntimeError) as error:
        print(f"Staged change size check could not run: {error}", file=sys.stderr)
        return 2

    failures = validate_staged_change(summary)
    if failures:
        print("Staged change size check failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    print(
        "Staged change size check passed: "
        f"{summary.path_count}/{MAX_STAGED_PATHS} paths, "
        f"{summary.text_line_count}/{MAX_STAGED_TEXT_LINES} text lines, "
        f"{summary.binary_path_count} binary paths"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
