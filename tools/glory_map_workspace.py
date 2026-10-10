"""Render one Glory map from workspace-local raw sources into a temporary workspace."""

from __future__ import annotations

import hashlib
import json
import shutil
from contextlib import contextmanager
from pathlib import Path, PurePosixPath
from tempfile import TemporaryDirectory
from typing import Iterator

if __package__:
    from tools.map_pipeline.extract_all_maps import (
        AleRepository, DEFAULT_GLORY_UPDATE_URL, MinimapRepository, RawImageRepository, parse_map, render_map,
    )
    from tools.map_pipeline.official_asset_recovery import OfficialAleRecovery
    from tools.recovery.fcc_workspace import RawFccWorkspace
else:
    from map_pipeline.extract_all_maps import (
        AleRepository, DEFAULT_GLORY_UPDATE_URL, MinimapRepository, RawImageRepository, parse_map, render_map,
    )
    from map_pipeline.official_asset_recovery import OfficialAleRecovery
    from recovery.fcc_workspace import RawFccWorkspace


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = PROJECT_ROOT / "../starhome_lz_ry_full" / "raw"
SPRITE_ROOT = PROJECT_ROOT / "assets" / "glory" / "sprites"
EVIDENCE_ROOT = PROJECT_ROOT / "data" / "source_evidence" / "glory" / "map_recovery"
UNPACKER = PROJECT_ROOT / "tools" / "recovery" / "maps" / "pkh_unpack.py"
ENGINE_DLL = PROJECT_ROOT / "../starhome_lz_ry_full" / "fkernel.dll"
OFFICIAL_MANIFEST = EVIDENCE_ROOT.parent / "official_recovery_manifest.json"
UNINDEXED_RAW_ROOT = PROJECT_ROOT / "../starhome_lz_ry_full" / "unindexed_raw"
ALE_DECODER = PROJECT_ROOT / "tools" / "recovery" / "sprites" / "ale_sprite.py"


class RawMapWorkspace:
    def __init__(self) -> None:
        self._fcc = RawFccWorkspace()
        self._sprites: AleRepository | None = None
        self._minimaps: MinimapRepository | None = None
        self._images: RawImageRepository | None = None

    def __enter__(self) -> RawMapWorkspace:
        self._fcc.__enter__()
        try:
            recovery = OfficialAleRecovery(
                DEFAULT_GLORY_UPDATE_URL, SPRITE_ROOT.parent, ALE_DECODER,
                allow_network=False, raw_root=UNINDEXED_RAW_ROOT,
                manifest_path=OFFICIAL_MANIFEST, parsed_root=SPRITE_ROOT,
            )
            self._sprites = AleRepository(SPRITE_ROOT, recovery=recovery)
            self._minimaps = MinimapRepository(RAW_ROOT)
            self._images = RawImageRepository(RAW_ROOT)
        except BaseException:
            self._fcc.__exit__(None, None, None)
            raise
        return self

    def __exit__(self, *_: object) -> None:
        if self._sprites is not None:
            self._sprites.close()
        self._sprites = None
        self._minimaps = None
        self._images = None
        self._fcc.__exit__(None, None, None)

    @contextmanager
    def render(self, relative_source: str) -> Iterator[tuple[Path, dict]]:
        """Yield a parsed map and its result; remove all intermediate images on exit."""
        if self._sprites is None or self._minimaps is None or self._images is None:
            raise RuntimeError("RawMapWorkspace must be used as a context manager")
        relative = PurePosixPath(relative_source)
        if relative.is_absolute() or not relative.parts or any(part in (".", "..") for part in relative.parts):
            raise ValueError(f"invalid map path: {relative_source}")
        source = EVIDENCE_ROOT / "maps" / Path(*relative.parts)
        metadata = json.loads((source / "map_metadata.json").read_text(encoding="utf-8"))
        expected_hash = metadata["script_sha256"]
        with TemporaryDirectory(prefix="starhome-map-") as temporary:
            root = Path(temporary)
            expanded = root / "expanded"
            records = []
            for script_ref in metadata["source_scripts"]:
                if ".fcc.expanded/" not in script_ref:
                    raise ValueError(f"invalid expanded map reference: {script_ref}")
                logical = script_ref.split(".fcc.expanded/", 1)[0] + ".fcc"
                payload = self._fcc.payload(logical)
                if hashlib.sha256(payload).hexdigest() != expected_hash:
                    raise ValueError(f"raw map FCC differs from source audit: {logical}")
                script = expanded / script_ref
                script.parent.mkdir(parents=True, exist_ok=True)
                script.write_bytes(payload)
                record = parse_map(script, expanded)
                if record is None:
                    raise ValueError(f"raw FCC has no map definition: {logical}")
                records.append(record)
            canonical = min(records, key=lambda row: row.relative_script.lower())
            output = root / "output"
            output_relative = Path("maps", *relative.parts)
            result = render_map(
                canonical, records, output, output_relative,
                self._sprites, self._minimaps, self._images, UNPACKER, ENGINE_DLL,
            )
            map_path = output / output_relative
            shutil.copyfile(source / "transitions.json", map_path / "transitions.json")
            yield map_path, result
