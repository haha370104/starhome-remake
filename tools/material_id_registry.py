"""Canonical semantic IDs for material definitions and offline migrations."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "data/content/material_id_migration_v1.json"


def _load() -> dict:
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


_REGISTRY = _load()
_BY_DISPLAY_NAME = _REGISTRY["by_display_name"]
_BY_SOURCE_CLASS = _REGISTRY["by_source_class"]


def canonical_material_id(display_name: str, source_class: str = "") -> str:
    """Return the canonical runtime ID; unknown materials require an explicit registry entry."""
    source = str(source_class).strip()
    name = str(display_name).strip()
    if source in _BY_SOURCE_CLASS:
        return _BY_SOURCE_CLASS[source]
    if name in _BY_DISPLAY_NAME:
        return _BY_DISPLAY_NAME[name]
    raise ValueError(
        f"Material {name!r} ({source!r}) is not in material_id_migration_v1.json; "
        "assign a semantic ID before generating content"
    )


def legacy_to_canonical() -> dict[str, str]:
    return {row["legacy_id"]: row["id"] for row in _REGISTRY["definitions"]}
