#!/usr/bin/env python3
"""Unit tests for exact-path Glory map asset recovery and its persistent cache."""

from __future__ import annotations

import struct
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import patch


PROJECT_ROOT = Path(__file__).resolve().parents[2]
PIPELINE_ROOT = PROJECT_ROOT / "tools" / "map_pipeline"
if str(PIPELINE_ROOT) not in sys.path:
    sys.path.insert(0, str(PIPELINE_ROOT))

from official_asset_recovery import OfficialAleRecovery, normalize_logical_ale_path


class FakeResponse:
    """Minimal successful urllib response used by recovery tests."""

    def __init__(self, payload: bytes) -> None:
        """Store response bytes and expose an HTTP 200 status.

        Args:
            payload: Bytes returned by ``read``.
        """
        self.payload = payload
        self.status = 200

    def __enter__(self) -> "FakeResponse":
        """Enter the urllib-compatible context manager.

        Returns:
            This response instance.
        """
        return self

    def __exit__(self, *_args: object) -> None:
        """Leave the urllib-compatible context manager without suppression.

        Args:
            *_args: Exception context supplied by Python.

        Returns:
            None.
        """
        return None

    def getcode(self) -> int:
        """Return the response HTTP status.

        Returns:
            HTTP 200.
        """
        return self.status

    def read(self, _limit: int = -1) -> bytes:
        """Return the complete synthetic payload.

        Args:
            _limit: Ignored urllib-compatible maximum byte count.

        Returns:
            Synthetic response body.
        """
        return self.payload


def placeholder_ale() -> bytes:
    """Build a valid ALE v3 containing one transparent 0x0 placeholder frame.

    Returns:
        Minimal bytes accepted by the audited ALE decoder.
    """
    header = b"ALE\0" + struct.pack("<H", 3) + b"\0\0\0\0" + struct.pack("<H", 1)
    frame = struct.pack("<IIIIiiH", 26, 0, 0, 0, 0, 0, 0)
    return header + frame


class OfficialAleRecoveryTests(unittest.TestCase):
    """Verify normalization, successful decoding, and one-shot failure caching."""

    def test_successful_download_is_decoded_and_reused_offline(self) -> None:
        """A valid response becomes a parsed cache hit without a second request."""
        with tempfile.TemporaryDirectory() as temporary:
            cache_root = Path(temporary)
            recovery = OfficialAleRecovery(
                "http://example.invalid/ry_www/",
                cache_root,
                PROJECT_ROOT.parents[1] / "work" / "ale_sprite.py",
            )
            with patch(
                "official_asset_recovery.urllib.request.urlopen",
                return_value=FakeResponse(placeholder_ale()),
            ) as request:
                folder, resolution = recovery.resolve(
                    "../../map/mapimg/house/demo.ale"
                )
            self.assertEqual(resolution, "official_http_recovery")
            self.assertIsNotNone(folder)
            self.assertTrue((folder / "frames.json").is_file())
            request.assert_called_once()

            offline = OfficialAleRecovery(
                "http://example.invalid/ry_www/",
                cache_root,
                PROJECT_ROOT.parents[1] / "work" / "ale_sprite.py",
                allow_network=False,
            )
            folder, resolution = offline.resolve("map/mapimg/house/demo.ale")
            self.assertEqual(resolution, "official_lazy_cache")
            self.assertTrue((folder / "frames.json").is_file())

    def test_http_404_is_persisted_and_not_probed_again(self) -> None:
        """A prior exact-path 404 suppresses later requests until explicit retry."""
        with tempfile.TemporaryDirectory() as temporary:
            cache_root = Path(temporary)
            recovery = OfficialAleRecovery(
                "http://example.invalid/ry_www/",
                cache_root,
                PROJECT_ROOT.parents[1] / "work" / "ale_sprite.py",
            )
            error = urllib.error.HTTPError(
                "http://example.invalid/missing.ale", 404, "Not Found", {}, None
            )
            with patch(
                "official_asset_recovery.urllib.request.urlopen", side_effect=error
            ) as request:
                folder, resolution = recovery.resolve("map/missing.ale")
            self.assertIsNone(folder)
            self.assertEqual(resolution, "official_not_found")
            request.assert_called_once()

            second_run = OfficialAleRecovery(
                "http://example.invalid/ry_www/",
                cache_root,
                PROJECT_ROOT.parents[1] / "work" / "ale_sprite.py",
            )
            with patch("official_asset_recovery.urllib.request.urlopen") as request:
                folder, resolution = second_run.resolve("map/missing.ale")
            self.assertIsNone(folder)
            self.assertEqual(resolution, "official_cached_not_found")
            request.assert_not_called()

    def test_reference_normalization_keeps_only_safe_map_path(self) -> None:
        """Legacy traversal prefixes normalize to the exact server map path."""
        self.assertEqual(
            normalize_logical_ale_path(
                "..\\..\\map\\mapimg\\house\\building.ale"
            ),
            "map/mapimg/house/building.ale",
        )
        with self.assertRaises(ValueError):
            normalize_logical_ale_path("C:/outside/cache.ale")


if __name__ == "__main__":
    unittest.main()
