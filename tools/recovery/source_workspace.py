"""Decode selected source sprites for one import run without a persistent parsed tree."""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory

from .paths import source_path
from .sprites.ale_sprite import AexFile, AleFile, build_sheets


class RawSpriteWorkspace:
    def __init__(self, raw_root: Path):
        self.raw_root = raw_root
        self._temporary: TemporaryDirectory[str] | None = None
        self._decoded: dict[str, tuple[Path, dict]] = {}

    def __enter__(self) -> RawSpriteWorkspace:
        self._temporary = TemporaryDirectory(prefix="starhome-sprites-")
        return self

    def __exit__(self, *_: object) -> None:
        assert self._temporary is not None
        self._temporary.cleanup()
        self._temporary = None
        self._decoded.clear()

    def source(self, logical_path: str) -> Path:
        return source_path(self.raw_root, logical_path)

    def require(self, logical_paths: list[str]) -> None:
        missing = []
        for logical in sorted(set(logical_paths)):
            try:
                self.source(logical)
            except FileNotFoundError:
                missing.append(logical)
        if missing:
            raise FileNotFoundError(
                f"{len(missing)} source files missing from {self.raw_root}:\n"
                + "\n".join(f"  {path}" for path in missing)
            )

    def decode(self, logical_path: str) -> tuple[Path, dict]:
        if logical_path not in self._decoded:
            if self._temporary is None:
                raise RuntimeError("RawSpriteWorkspace must be used as a context manager")
            source = self.source(logical_path)
            decoder = AexFile(source) if source.suffix.lower() == ".aex" else AleFile(source)
            target = Path(self._temporary.name).joinpath(*PurePosixPath(logical_path).parts)
            metadata = build_sheets(decoder, target)
            metadata["source"] = logical_path
            (target / "frames.json").write_text(
                json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )
            self._decoded[logical_path] = (target, metadata)
        return self._decoded[logical_path]
