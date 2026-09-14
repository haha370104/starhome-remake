#!/usr/bin/env python3
"""Reject large project assets that bypass the repository's Git LFS policy."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


MAX_REGULAR_GIT_BYTES = 5 * 1024 * 1024


def run_git(repository: Path, arguments: list[str]) -> str:
    """Run a read-only Git command in *repository* and return decoded stdout."""
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
    return process.stdout.decode("utf-8", errors="surrogateescape")


def asset_repository(repository: Path) -> Path:
    """Resolve the initialized asset submodule without falling back to its parent."""
    entry = run_git(repository, ["ls-files", "--stage", "--", "assets"]).strip()
    if not entry.startswith("160000 "):
        raise RuntimeError("assets must be tracked as a Git submodule (mode 160000)")
    assets = repository / "assets"
    if not (assets / ".git").exists():
        raise RuntimeError("assets is not initialized; run git submodule update --init --recursive")
    actual = Path(run_git(assets, ["rev-parse", "--show-toplevel"]).strip()).resolve()
    if actual != assets.resolve():
        raise RuntimeError("assets does not resolve to its own Git repository")
    return assets


def project_asset_paths(repository: Path) -> list[Path]:
    """Return tracked and unignored untracked files in the asset repository."""
    output = run_git(
        repository,
        ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    )
    return [repository / value for value in output.split("\0") if value]


def uses_lfs(repository: Path, path: Path) -> bool:
    """Return whether *path* is covered by a Git attribute using the LFS filter."""
    relative = path.relative_to(repository).as_posix()
    output = run_git(repository, ["check-attr", "filter", "--", relative])
    return output.rstrip().endswith(": lfs")


def find_violations(repository: Path) -> list[str]:
    """Return oversized existing assets that are not protected by Git LFS."""
    failures: list[str] = []
    assets = asset_repository(repository)
    for path in project_asset_paths(assets):
        if not path.is_file() or path.stat().st_size < MAX_REGULAR_GIT_BYTES:
            continue
        if uses_lfs(assets, path):
            continue
        relative = path.relative_to(repository).as_posix()
        size_mib = path.stat().st_size / (1024 * 1024)
        failures.append(f"{relative}: {size_mib:.2f} MiB is not covered by Git LFS")
    return failures


def main() -> int:
    """Validate the current repository and return a shell-friendly status code."""
    try:
        repository = Path(run_git(Path.cwd(), ["rev-parse", "--show-toplevel"]).strip())
        failures = find_violations(repository)
    except (OSError, RuntimeError) as error:
        print(f"Asset size policy could not run: {error}", file=sys.stderr)
        return 2
    if failures:
        print("Asset size policy failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Asset size policy passed: every asset >= 5 MiB is covered by Git LFS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
