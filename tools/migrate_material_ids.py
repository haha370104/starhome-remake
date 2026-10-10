"""One-time migration of old material IDs in runtime data and player saves."""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
from datetime import datetime
from pathlib import Path

from material_id_registry import REGISTRY_PATH, legacy_to_canonical

ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIXES = {".gd", ".json", ".py", ".md", ".txt", ".cfg", ".tscn", ".tres"}
SKIP_PARTS = {".git", ".godot", "material_id_migration_v1.json"}


def migrate_text_tree() -> int:
    mapping = legacy_to_canonical()
    changed = 0
    paths = subprocess.check_output(
        ["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT
    ).split(b"\0")
    for raw_path in paths:
        if not raw_path:
            continue
        path = ROOT / raw_path.decode()
        if path.name == "material_id_migration_v1.json" or path.suffix not in TEXT_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        updated = text
        for old, new in mapping.items():
            updated = updated.replace(old, new)
        if updated != text:
            path.write_text(updated, encoding="utf-8")
            changed += 1
    return changed


def migrate_save(path: Path, backup: bool = True) -> None:
    mapping = legacy_to_canonical()
    if backup:
        stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
        backup_path = path.with_name(path.name + f".backup-material-id-{stamp}")
        shutil.copy2(path, backup_path)
        print(f"backup={backup_path}")
    text = path.read_text(encoding="utf-8")
    for old, new in mapping.items():
        text = text.replace(old, new)
    json.loads(text)
    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--save", type=Path)
    parser.add_argument("--no-save", action="store_true")
    args = parser.parse_args()
    print(f"registry={REGISTRY_PATH}")
    print(f"changed_files={migrate_text_tree()}")
    if args.save and not args.no_save:
        migrate_save(args.save)
