"""Resolve original logical resource names beneath a caller-owned source tree."""
from pathlib import Path, PurePosixPath, PureWindowsPath


def source_path(root: Path, logical: str) -> Path:
    """Reject absolute/drive/traversal paths, including Windows alternate streams."""
    normalized = logical.replace('\\', '/')
    parts = PurePosixPath(normalized).parts
    if not parts or ':' in normalized or PureWindowsPath(logical).drive or normalized.startswith('/') \
            or any(part in ('.', '..') for part in normalized.split('/')):
        raise ValueError(f'invalid source path: {logical}')
    root = root.resolve()
    path = root.joinpath(*parts).resolve()
    if not path.is_relative_to(root):
        raise ValueError(f'source escapes root: {logical}')
    if not path.is_file():
        raise FileNotFoundError(path)
    return path
