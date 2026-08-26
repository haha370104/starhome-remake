#!/usr/bin/env python3
"""Extract an offline navigation grid from one decoded FancyBoxII map FCC.

The client stores the grid as ``indexdata=$PKH{packed_size:hex...}``.  PKH is
unpacked by the original engine's LZW implementation; the resulting stream is
made of three-byte little-endian cells: ``uint16 tile_kind, uint8 flags``.
Bit 0x80 of flags is the walkable bit.

This tool deliberately writes analysis artifacts outside ``assets/``.  Select,
rename and import a map by game semantics before it becomes a runtime asset.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from collections import Counter
from pathlib import Path


PKH_RE = re.compile(rb"indexdata\s*=\s*\$PKH\{(\d+):([0-9A-Fa-f\s]+?)\}", re.I)
MAP_SIZE_RE = re.compile(rb"size\s*=\s*(\d+)\s*\*\s*(\d+)", re.I)
GRID_SIZE_RE = re.compile(rb"tilesize\s*=\s*(\d+)\s*,\s*(\d+)", re.I)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def parse_pair(pattern: re.Pattern[bytes], content: bytes) -> list[int] | None:
    match = pattern.search(content)
    return [int(value) for value in match.groups()] if match else None


def run_unpacker(
    unpacker: Path, engine_dll: Path, packed_path: Path, raw_path: Path
) -> str:
    process = subprocess.run(
        [
            str(unpacker.resolve()),
            str(engine_dll.resolve()),
            str(packed_path.resolve()),
            str(raw_path.resolve()),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode:
        message = (process.stdout + process.stderr).strip()
        raise RuntimeError(f"PKH unpack failed with exit code {process.returncode}: {message}")
    return (process.stdout + process.stderr).strip()


def extract(script_path: Path, output_dir: Path, unpacker: Path, engine_dll: Path) -> dict:
    content = script_path.read_bytes()
    match = PKH_RE.search(content)
    if not match:
        raise ValueError(f"{script_path} does not contain bktile.indexdata PKH data")

    declared_packed_size = int(match.group(1))
    packed = bytes.fromhex(re.sub(rb"\s+", b"", match.group(2)).decode("ascii"))
    if len(packed) != declared_packed_size:
        raise ValueError(
            f"PKH declares {declared_packed_size} bytes, but contains {len(packed)}"
        )

    output_dir.mkdir(parents=True, exist_ok=True)
    packed_path = output_dir / "packed_indexdata.pkh"
    raw_path = output_dir / "raw_indexdata.bin"
    packed_path.write_bytes(packed)
    unpacker_output = run_unpacker(unpacker, engine_dll, packed_path, raw_path)
    raw = raw_path.read_bytes()
    if len(raw) % 3:
        raise ValueError(f"unpacked indexdata size {len(raw)} is not divisible by 3")

    entry_count = len(raw) // 3
    map_size = parse_pair(MAP_SIZE_RE, content)
    grid_size = parse_pair(GRID_SIZE_RE, content)
    if grid_size and grid_size[0] * grid_size[1] != entry_count:
        raise ValueError(
            "FCC tilesize does not match unpacked cells: "
            f"{grid_size[0]}x{grid_size[1]} != {entry_count}"
        )

    flag_counts: Counter[int] = Counter()
    tile_kind_counts: Counter[int] = Counter()
    navigation = bytearray(entry_count)
    for cell_index in range(entry_count):
        offset = cell_index * 3
        tile_kind = int.from_bytes(raw[offset : offset + 2], "little")
        flags = raw[offset + 2]
        tile_kind_counts[tile_kind] += 1
        flag_counts[flags] += 1
        navigation[cell_index] = 1 if flags & 0x80 else 0

    navigation_path = output_dir / "navigation_grid.bin"
    navigation_path.write_bytes(navigation)
    passable_count = sum(navigation)
    metadata = {
        "format": "fancyboxii_bktile_navigation_v1",
        "source_script": str(script_path.resolve()),
        "source_script_sha256": sha256(content),
        "engine_dll": str(engine_dll.resolve()),
        "map_pixel_size": map_size,
        "engine_grid_size": grid_size,
        "cell_record": {
            "size_bytes": 3,
            "layout": "uint16_le tile_kind, uint8 flags",
            "walkable_rule": "(flags & 0x80) != 0",
        },
        "packed": {"size": len(packed), "sha256": sha256(packed)},
        "unpacked": {
            "size": len(raw),
            "sha256": sha256(raw),
            "entry_count": entry_count,
        },
        "runtime_navigation": {
            "file": navigation_path.name,
            "size": len(navigation),
            "sha256": sha256(navigation),
            "passable": passable_count,
            "blocked": entry_count - passable_count,
        },
        "flag_counts": {
            f"0x{flag:02X}": count for flag, count in sorted(flag_counts.items())
        },
        "tile_kind_counts": {
            f"0x{kind:04X}": count
            for kind, count in sorted(tile_kind_counts.items())
        },
        "unpacker_output": unpacker_output,
    }
    (output_dir / "navigation_metadata.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", type=Path, help="decoded *.fcc.cab map script")
    parser.add_argument("output_dir", type=Path, help="analysis output directory")
    parser.add_argument("--unpacker", type=Path, required=True, help="pkh_unpack.exe")
    parser.add_argument(
        "--engine-dll", type=Path, required=True, help="matching version's fkernel.dll"
    )
    args = parser.parse_args()
    metadata = extract(args.script, args.output_dir, args.unpacker, args.engine_dll)
    print(
        json.dumps(
            {
                "grid": metadata["engine_grid_size"],
                "passable": metadata["runtime_navigation"]["passable"],
                "blocked": metadata["runtime_navigation"]["blocked"],
                "output": str(args.output_dir.resolve()),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
