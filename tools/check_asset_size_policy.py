#!/usr/bin/env python3
"""Validate the materialized ``assets/`` runtime tree.

Runtime assets are intentionally ignored by Git after the content-tree migration.  The
migration manifest, rather than a submodule/LFS checkout, is the source of truth for
which archives were verified and removed and which files must exist locally.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path


MANIFEST_RELATIVE = Path("data/content/content_materialization_manifest_v1.json")
EXPECTED_NAMESPACE = "res://assets/"


def find_violations(repository: Path) -> list[str]:
    """Return materialization errors for *repository*."""
    content = repository / "assets"
    manifest_path = repository / MANIFEST_RELATIVE
    failures: list[str] = []
    if not content.is_dir():
        return ["assets/ is missing; materialize the approved runtime content first"]
    if not manifest_path.is_file():
        return [f"materialization manifest is missing: {MANIFEST_RELATIVE.as_posix()}"]
    try:
        document = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        return [f"cannot read materialization manifest: {error}"]
    if document.get("schema_version") != 1:
        failures.append("materialization manifest schema_version must be 1")
    if document.get("namespace") != EXPECTED_NAMESPACE:
        failures.append(f"materialization manifest namespace must be {EXPECTED_NAMESPACE}")
    archives = document.get("archives")
    if not isinstance(archives, list) or not archives:
        failures.append("materialization manifest has no archive records")
        return failures
    expected_files: set[str] = set()
    for archive in archives:
        if not isinstance(archive, dict):
            failures.append("materialization manifest contains a non-object archive record")
            continue
        if archive.get("status") != "verified_and_removed":
            failures.append(f"archive is not verified_and_removed: {archive.get('archive', '')}")
        entries = archive.get("entries", [])
        if not isinstance(entries, list):
            failures.append(f"archive entries must be an array: {archive.get('archive', '')}")
            continue
        for entry in entries:
            if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
                failures.append(f"invalid entry in archive: {archive.get('archive', '')}")
                continue
            relative = entry["path"]
            expected_files.add(relative)
            if not (repository / relative).is_file():
                failures.append(f"materialized file is missing: {relative}")
    return failures


def main() -> int:
    """Validate the current project and return a shell-friendly status code."""
    repository = Path(__file__).resolve().parents[1]
    failures = find_violations(repository)
    if failures:
        print("Content materialization policy failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Content materialization policy passed: manifest and materialized files are present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
