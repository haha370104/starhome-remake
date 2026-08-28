#!/usr/bin/env python3
"""Recover Glory map ALE files that are referenced by FCC but absent from files_dir.dz."""

from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from types import ModuleType
from typing import Any


SUPPORTED_ALE_SIGNATURES = {b"ALE\0", b"RLE0", b"AEX\0"}
MAX_DOWNLOAD_BYTES = 128 * 1024 * 1024


def normalize_logical_ale_path(reference: str) -> str:
    """Return a traversal-free, slash-separated ALE path from an FCC reference.

    Args:
        reference: Logical path written by the original client FCC.

    Returns:
        A relative path ending in ``.ale`` and rooted at the first ``map/``
        segment when one is present.

    Raises:
        ValueError: The reference is empty, absolute, or still contains parent
            traversal after normalization.
    """
    normalized = reference.replace("\\", "/").strip()
    while normalized.startswith("../"):
        normalized = normalized[3:]
    normalized = normalized.removeprefix("./").lstrip("/")
    map_index = normalized.lower().find("map/")
    if map_index >= 0:
        normalized = normalized[map_index:]
    if not normalized.lower().endswith(".ale"):
        normalized += ".ale"
    candidate = Path(normalized)
    parts = candidate.parts
    if (
        not normalized
        or candidate.is_absolute()
        or candidate.drive
        or any(":" in part or part in {"", ".", ".."} for part in parts)
    ):
        raise ValueError(f"unsafe ALE reference: {reference!r}")
    return Path(*parts).as_posix()


def safe_output_stem(stem: str) -> str:
    """Encode Windows-invalid trailing dots or spaces in a parsed folder name.

    Args:
        stem: Original ALE filename stem.

    Returns:
        A filesystem-safe stem that remains reversible for provenance.
    """
    trimmed = stem.rstrip(" .")
    suffix = stem[len(trimmed) :]
    if not suffix:
        return stem
    return trimmed + "".join(f"__x{ord(character):02X}" for character in suffix)


def file_hashes(path: Path) -> tuple[str, str, int]:
    """Calculate MD5, SHA-256, and byte length for a recovered artifact.

    Args:
        path: Local file to hash.

    Returns:
        ``(md5, sha256, byte_count)`` using lowercase hexadecimal digests.
    """
    md5 = hashlib.md5(usedforsecurity=False)
    sha256 = hashlib.sha256()
    byte_count = 0
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            md5.update(chunk)
            sha256.update(chunk)
            byte_count += len(chunk)
    return md5.hexdigest(), sha256.hexdigest(), byte_count


class OfficialAleRecovery:
    """Persistent same-release resolver for Glory assets omitted by files_dir.dz.

    The cache is deliberately separate from the indexed archive. This keeps the
    immutable full-package audit truthful while still making lazy HTTP assets a
    first-class Glory source. One manifest entry is written per exact logical
    path, including failures, so normal runs never probe the same URL twice.
    """

    def __init__(
        self,
        base_url: str,
        cache_root: Path,
        decoder_path: Path,
        timeout_seconds: float = 30.0,
        retry_failures: bool = False,
        allow_network: bool = True,
    ) -> None:
        """Configure the official URL, persistent cache, and ALE decoder.

        Args:
            base_url: Glory update root ending above logical resource paths.
            cache_root: Directory containing ``raw/``, ``ale_sprites/``, and
                the recovery manifest.
            decoder_path: Path to the trusted ``ale_sprite.py`` implementation.
            timeout_seconds: Per-request HTTP timeout.
            retry_failures: Whether persisted failed probes may be attempted again.
            allow_network: Whether a cache miss may issue an HTTP request.
        """
        self.base_url = base_url.rstrip("/") + "/"
        self.cache_root = cache_root.resolve()
        self.raw_root = self.cache_root / "raw"
        self.parsed_root = self.cache_root / "ale_sprites"
        self.manifest_path = self.cache_root / "official_recovery_manifest.json"
        self.decoder_path = decoder_path.resolve()
        self.timeout_seconds = timeout_seconds
        self.retry_failures = retry_failures
        self.allow_network = allow_network
        self.assets: dict[str, dict[str, Any]] = {}
        self._decoder: ModuleType | None = None
        self._load_manifest()

    def _load_manifest(self) -> None:
        """Load prior success and failure records from the persistent cache.

        Args:
            None.

        Returns:
            None.
        """
        if not self.manifest_path.is_file():
            return
        payload = json.loads(self.manifest_path.read_text(encoding="utf-8"))
        if payload.get("format") != "starhome_glory_official_ale_cache_v1":
            raise ValueError(f"unsupported recovery manifest: {self.manifest_path}")
        self.assets = dict(payload.get("assets", {}))

    def _save_manifest(self) -> None:
        """Atomically persist all exact-path recovery outcomes.

        Args:
            None.

        Returns:
            None.
        """
        self.cache_root.mkdir(parents=True, exist_ok=True)
        payload = {
            "format": "starhome_glory_official_ale_cache_v1",
            "source_release": "starhome_lz_ry",
            "base_url": self.base_url,
            "policy": "one exact-path request; no fuzzy or cross-release substitution",
            "assets": dict(sorted(self.assets.items())),
        }
        temporary = self.manifest_path.with_suffix(".json.tmp")
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, self.manifest_path)

    def _record(self, logical_path: str, **fields: Any) -> dict[str, Any]:
        """Replace one manifest entry and flush it immediately.

        Args:
            logical_path: Normalized exact resource path used as the cache key.
            **fields: Auditable status, transport, hash, and parser metadata.

        Returns:
            The stored record.
        """
        record = {
            "logical_path": logical_path,
            "source_release": "starhome_lz_ry",
            "source_resolution": "official_exact_path_lazy_recovery",
            **fields,
        }
        self.assets[logical_path.lower()] = record
        self._save_manifest()
        return record

    def _url_for(self, logical_path: str) -> str:
        """Encode an original client path as a Glory update-server URL.

        Args:
            logical_path: Normalized resource path whose non-ASCII bytes use
                the old client's GB18030 encoding.

        Returns:
            Fully qualified and percent-encoded HTTP URL.
        """
        encoded = urllib.parse.quote_from_bytes(
            logical_path.encode("gb18030"), safe="/"
        )
        return urllib.parse.urljoin(self.base_url, encoded)

    def _parsed_folder(self, logical_path: str) -> Path:
        """Map a logical ALE path to its parsed sprite directory.

        Args:
            logical_path: Normalized resource path ending in ``.ale``.

        Returns:
            Target folder containing ``frames.json`` and sprite sheets.
        """
        relative = Path(logical_path)
        return self.parsed_root / relative.parent / safe_output_stem(relative.stem)

    def _decoder_module(self) -> ModuleType:
        """Load the existing audited ALE decoder without copying its implementation.

        Args:
            None.

        Returns:
            Imported module exposing ``AleFile``, ``AexFile``, and
            ``build_sheets``.

        Raises:
            FileNotFoundError: The configured decoder does not exist.
            ImportError: Python cannot load the decoder module.
        """
        if self._decoder is not None:
            return self._decoder
        if not self.decoder_path.is_file():
            raise FileNotFoundError(f"ALE decoder not found: {self.decoder_path}")
        spec = importlib.util.spec_from_file_location(
            "starhome_recovery_ale_sprite", self.decoder_path
        )
        if spec is None or spec.loader is None:
            raise ImportError(f"cannot load ALE decoder: {self.decoder_path}")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        self._decoder = module
        return module

    def _parse(self, raw_path: Path, logical_path: str) -> Path:
        """Decode one validated raw ALE into an atomically promoted sprite folder.

        Args:
            raw_path: Downloaded ALE file in the recovery cache.
            logical_path: Exact normalized source path for output placement.

        Returns:
            Parsed sprite directory.

        Raises:
            RuntimeError: A partial target exists or decoding produces no manifest.
        """
        target = self._parsed_folder(logical_path)
        if (target / "frames.json").is_file():
            return target
        if target.exists():
            raise RuntimeError(f"partial parsed target requires manual review: {target}")
        target.parent.mkdir(parents=True, exist_ok=True)
        temporary = target.with_name(target.name + f".__tmp_{os.getpid()}")
        if temporary.exists():
            raise RuntimeError(f"stale parser temporary directory: {temporary}")
        decoder = self._decoder_module()
        with raw_path.open("rb") as stream:
            magic = stream.read(4)
        ale = decoder.AexFile(raw_path) if magic == b"AEX\0" else decoder.AleFile(raw_path)
        decoder.build_sheets(ale, temporary, 8192)
        if not (temporary / "frames.json").is_file():
            raise RuntimeError("ALE decoder did not produce frames.json")
        os.replace(temporary, target)
        return target

    def resolve(self, reference: str) -> tuple[Path | None, str]:
        """Resolve, fetch once, validate, and parse one exact ALE reference.

        Args:
            reference: Original FCC ALE reference.

        Returns:
            ``(parsed_folder, resolution)``. The folder is ``None`` when the
            cached or newly attempted recovery did not succeed.
        """
        logical_path = normalize_logical_ale_path(reference)
        key = logical_path.lower()
        parsed_folder = self._parsed_folder(logical_path)
        if (parsed_folder / "frames.json").is_file():
            if key not in self.assets:
                raw_path = self.raw_root / Path(logical_path)
                hashes = file_hashes(raw_path) if raw_path.is_file() else (None, None, None)
                self._record(
                    logical_path,
                    status="recovered",
                    cache_state="preexisting",
                    source_url=self._url_for(logical_path),
                    raw_file=raw_path.relative_to(self.cache_root).as_posix()
                    if raw_path.is_file()
                    else None,
                    parsed_folder=parsed_folder.relative_to(self.cache_root).as_posix(),
                    md5=hashes[0],
                    sha256=hashes[1],
                    bytes=hashes[2],
                )
            return parsed_folder, "official_lazy_cache"

        prior = self.assets.get(key)
        if prior and prior.get("status") != "recovered" and not self.retry_failures:
            return None, f"official_cached_{prior.get('status', 'failure')}"

        raw_path = self.raw_root / Path(logical_path)
        source_url = self._url_for(logical_path)
        if not raw_path.is_file():
            if not self.allow_network:
                return None, "official_offline_cache_miss"
            try:
                request = urllib.request.Request(
                    source_url,
                    headers={"User-Agent": "starhome-remake-map-recovery/1.0"},
                )
                with urllib.request.urlopen(request, timeout=self.timeout_seconds) as response:
                    status = int(getattr(response, "status", response.getcode()))
                    payload = response.read(MAX_DOWNLOAD_BYTES + 1)
                if status != 200:
                    self._record(
                        logical_path,
                        status="http_error",
                        http_status=status,
                        source_url=source_url,
                    )
                    return None, "official_http_error"
                if len(payload) > MAX_DOWNLOAD_BYTES:
                    self._record(
                        logical_path,
                        status="too_large",
                        http_status=status,
                        source_url=source_url,
                    )
                    return None, "official_too_large"
                raw_path.parent.mkdir(parents=True, exist_ok=True)
                temporary = raw_path.with_suffix(raw_path.suffix + ".part")
                temporary.write_bytes(payload)
                os.replace(temporary, raw_path)
            except urllib.error.HTTPError as error:
                self._record(
                    logical_path,
                    status="not_found" if error.code == 404 else "http_error",
                    http_status=error.code,
                    source_url=source_url,
                    error=str(error),
                )
                return None, "official_not_found" if error.code == 404 else "official_http_error"
            except (OSError, urllib.error.URLError) as error:
                self._record(
                    logical_path,
                    status="network_error",
                    source_url=source_url,
                    error=f"{type(error).__name__}: {error}",
                )
                return None, "official_network_error"

        md5, sha256, byte_count = file_hashes(raw_path)
        with raw_path.open("rb") as stream:
            magic = stream.read(4)
        if magic not in SUPPORTED_ALE_SIGNATURES:
            self._record(
                logical_path,
                status="invalid_format",
                source_url=source_url,
                raw_file=raw_path.relative_to(self.cache_root).as_posix(),
                md5=md5,
                sha256=sha256,
                bytes=byte_count,
            )
            return None, "official_invalid_format"
        try:
            parsed_folder = self._parse(raw_path, logical_path)
        except Exception as error:
            self._record(
                logical_path,
                status="parse_error",
                source_url=source_url,
                raw_file=raw_path.relative_to(self.cache_root).as_posix(),
                md5=md5,
                sha256=sha256,
                bytes=byte_count,
                error=f"{type(error).__name__}: {error}",
            )
            return None, "official_parse_error"
        self._record(
            logical_path,
            status="recovered",
            cache_state="downloaded_or_raw_cache",
            http_status=200,
            source_url=source_url,
            raw_file=raw_path.relative_to(self.cache_root).as_posix(),
            parsed_folder=parsed_folder.relative_to(self.cache_root).as_posix(),
            md5=md5,
            sha256=sha256,
            bytes=byte_count,
        )
        return parsed_folder, "official_http_recovery"

    def audit_for(self, reference: str) -> dict[str, Any] | None:
        """Return a copy of persisted provenance for one FCC reference.

        Args:
            reference: Original FCC ALE reference.

        Returns:
            Recovery record when previously attempted, otherwise ``None``.
        """
        key = normalize_logical_ale_path(reference).lower()
        record = self.assets.get(key)
        return dict(record) if record else None
