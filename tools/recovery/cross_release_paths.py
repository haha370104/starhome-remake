"""Shared paths for optional cross-release research reports and caches."""
from __future__ import annotations

import os
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RECOVERY_ROOT = Path(os.environ.get("STARHOME_RECOVERY_ROOT", PROJECT_ROOT.parent / "starhome-recovery"))
CROSS_RELEASE_ROOT = Path(
    os.environ.get("STARHOME_CROSS_RELEASE_ROOT", RECOVERY_ROOT / "cross_release_asset_recovery")
)
REPORTS = CROSS_RELEASE_ROOT / "reports"
CACHE = CROSS_RELEASE_ROOT / "cache"
