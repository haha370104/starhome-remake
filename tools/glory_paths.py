"""Workspace-local Glory archive, decoded sprite, and audit paths."""

from functools import lru_cache
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = PROJECT_ROOT / "../starhome_lz_ry_full" / "raw"
SPRITE_ROOT = PROJECT_ROOT / "assets" / "glory" / "sprites"
EVIDENCE_ROOT = PROJECT_ROOT / "data" / "source_evidence" / "glory"


def sprite_dir(logical_ale: str | Path) -> Path:
    """Resolve an ALE logical path in the materialized lowercase sprite tree."""
    logical = Path(logical_ale)
    if logical.is_absolute() or ".." in logical.parts:
        raise ValueError(f"invalid ALE logical path: {logical_ale}")
    return SPRITE_ROOT / logical.with_suffix("").as_posix().lower()


@lru_cache(maxsize=8192)
def resolve_casefold_path(root: Path, relative: str) -> Path | None:
    """Find a logical path in a source tree that preserves original casing."""
    logical = Path(relative)
    if logical.is_absolute() or ".." in logical.parts:
        raise ValueError(f"invalid logical path: {relative}")
    current = root
    for component in logical.parts:
        exact = current / component
        if exact.exists():
            current = exact
            continue
        folded = component.casefold()
        if not current.is_dir():
            return None
        matches = [child for child in current.iterdir() if child.name.casefold() == folded]
        if len(matches) != 1:
            return None
        current = matches[0]
    return current
