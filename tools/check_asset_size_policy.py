#!/usr/bin/env python3
"""Enforce the explicit LFS or temporary regular-Git asset storage contract."""

from __future__ import annotations

import subprocess
import sys
import json
from pathlib import Path


MAX_REGULAR_GIT_BYTES = 5 * 1024 * 1024
REGULAR_GIT_LIMIT = 48 * 1024 * 1024
POLICY_PATH = 'data/content/asset_storage_policy_v1.json'
LFS_POINTER = b'version https://git-lfs.github.com/spec/v1'


def run_git(repository: Path, arguments: list[str], input_text=None) -> str:
    """Run a read-only Git command in *repository* and return decoded stdout."""
    process = subprocess.run(
        ["git", *arguments],
        cwd=repository,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
        input=None if input_text is None else input_text.encode('utf-8'),
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
    """Reject oversize assets, residual LFS filters and unhydrated LFS pointers."""
    failures: list[str] = []
    assets = asset_repository(repository)
    policy_path = repository / POLICY_PATH
    settings = json.loads(policy_path.read_text(encoding='utf-8-sig')) if policy_path.exists() else {}
    mode = settings.get('mode', 'lfs')
    if mode not in {'lfs', 'regular_git'}:
        raise RuntimeError(f'Unknown asset storage mode: {mode}')
    paths = [p for p in project_asset_paths(assets) if p.is_file()]
    if mode == 'regular_git':
        limit = settings.get('max_file_bytes', REGULAR_GIT_LIMIT)
        if not isinstance(limit, int) or not 0 < limit <= REGULAR_GIT_LIMIT:
            raise RuntimeError('Regular Git asset limit must be at most 48 MiB')
        attributes = run_git(assets, ['check-attr', '-z', '--stdin', 'filter'],
                             ''.join(p.relative_to(assets).as_posix() + '\0' for p in paths)).split('\0')
        for name, _, value in zip(attributes[0::3], attributes[1::3], attributes[2::3]):
            if value == 'lfs':
                failures.append(f'assets/{name}: LFS filter remains in regular Git mode')
        for path in paths:
            relative = path.relative_to(repository).as_posix()
            if path.stat().st_size > limit:
                failures.append(f'{relative}: exceeds regular Git limit of {limit} bytes')
            with path.open('rb') as stream:
                if stream.read(len(LFS_POINTER)) == LFS_POINTER:
                    failures.append(f'{relative}: unresolved LFS pointer instead of asset bytes')
        return failures
    for path in paths:
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
    print("Asset size policy passed for the configured storage mode")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
