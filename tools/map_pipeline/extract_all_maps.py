#!/usr/bin/env python3
"""Reconstruct every cached Glory-edition FancyBoxII map offline.

The tool inventories all NFT branch map FCC files, decodes their GB18030 map
names, deduplicates byte-identical scripts, reconstructs ALE background layers,
composites AddImg/AddImgEx scene objects for inspection, extracts navigation,
copies branch-aware minimaps, and writes UTF-8 JSON/CSV/HTML catalogs.

Generated files are research artifacts and intentionally live outside the
Godot project's ``assets/`` tree.  A selected map must still be renamed by
business semantics before it is imported into the remake.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import html
import json
import re
import shutil
import subprocess
import sys
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops

from extract_navigation import extract as extract_navigation
from extract_navigation import run_unpacker


Image.MAX_IMAGE_PIXELS = None

MAP_NAME_RE = re.compile(rb"\bm_sMapName\s*=\s*\"([^\"]*)\"", re.I)
CHECK_NAME_RE = re.compile(rb"\bm_sNameForCheck\s*=\s*\"([^\"]*)\"", re.I)
MAP_SIZE_RE = re.compile(rb"size\s*=\s*(\d+)\s*(?:\*|x)\s*(\d+)", re.I)
GRID_SIZE_RE = re.compile(rb"tilesize\s*=\s*(\d+)\s*,\s*(\d+)", re.I)
INDEX_RE = re.compile(rb"indexdata\s*=\s*\$PKH\{(\d+):([0-9A-Fa-f\s]+?)\}", re.I)
OVERDATA_RE = re.compile(
    rb"\boverdata\s*=\s*\$(HEX|PKH)\{(\d+):([0-9A-Fa-f\s]+?)\}", re.I
)
OVERSRC_RE = re.compile(
    rb"\boversrc\s*=\s*(?:\$\+\s*)?[\"']([^\"']+\.ale)[\"']", re.I
)
MASK_IMAGE_RE = re.compile(rb"\bmaskimg\s*=\s*(?:\$\+\s*)?[\"']([^\"']+)[\"']", re.I)
TILE_KIND_RE = re.compile(
    rb"\baddkind\s*=\s*[\"']([^\"']+)[\"']\s*,\s*(-?\d+)\s*,\s*"
    rb"(?:\$\+\s*)?[\"']([^\"']+)[\"']\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(\d+)",
    re.I,
)
TILE_LINK_RE = re.compile(
    rb"\blink\s*=\s*[\"']([^\"']+)[\"']\s*,\s*[\"']([^\"']+)[\"']", re.I
)
PROP_CALL_RE = re.compile(rb"\b(AddImgEx|AddImg)\s*\((.*?)\)\s*;", re.I | re.S)
PROP_RESOURCE_RE = re.compile(
    rb"(?:\$\+\s*)?[\"']([^\"']+\.ale)[\"']\s*,\s*(-?\d+)\s*,\s*(-?\d+)",
    re.I,
)
FIELD_CODE_RE = re.compile(r"^[A-Za-z]\d{2}$")
SAFE_SLUG_RE = re.compile(r"[^a-z0-9_-]+")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def decode_client_text(raw: bytes | None, fallback: str) -> str:
    if raw is None:
        return fallback
    for encoding in ("gb18030", "utf-8"):
        try:
            value = raw.decode(encoding).strip()
            if value:
                return value
        except UnicodeDecodeError:
            pass
    value = raw.decode("gb18030", errors="replace").strip()
    return value or fallback


def first_group(pattern: re.Pattern[bytes], content: bytes) -> bytes | None:
    match = pattern.search(content)
    return match.group(1) if match else None


def pair(pattern: re.Pattern[bytes], content: bytes) -> list[int] | None:
    match = pattern.search(content)
    return [int(value) for value in match.groups()] if match else None


def safe_slug(value: str, fallback: str) -> str:
    slug = SAFE_SLUG_RE.sub("_", value.lower()).strip("_")
    return slug or fallback


def normalize_ale_reference(value: str) -> str:
    normalized = value.replace("\\", "/").strip()
    while normalized.startswith("../"):
        normalized = normalized[3:]
    normalized = normalized.removeprefix("./").lstrip("/")
    lower = normalized.lower()
    map_index = lower.find("map/")
    if map_index >= 0:
        normalized = normalized[map_index:]
    elif lower.startswith("mapimg/"):
        normalized = "map/" + normalized
    if normalized.lower().endswith(".ale"):
        normalized = normalized[:-4]
    return normalized


@dataclass(frozen=True)
class PropCall:
    kind: str
    source: str
    anchor_x: int
    anchor_y: int


@dataclass(frozen=True)
class TileKind:
    name: str
    walkable: bool
    source: str
    crop_x: int
    crop_y: int
    variants: int


@dataclass(frozen=True)
class TileLink:
    first: str
    second: str


@dataclass
class MapRecord:
    script: Path
    relative_script: str
    branch: str
    map_code: str
    map_name: str
    check_name: str
    script_sha256: str
    map_size: list[int] | None
    grid_size: list[int] | None
    mask_source: str | None
    tile_kinds: list[TileKind]
    tile_links: list[TileLink]
    oversrc: str | None
    overdata_kind: str | None
    overdata_declared_size: int | None
    overdata_payload: bytes | None
    props: list[PropCall]
    category: str
    parsed_path: str = ""

    def source_json(self) -> dict[str, Any]:
        return {
            "branch": self.branch,
            "map_code": self.map_code,
            "map_name": self.map_name,
            "check_name": self.check_name,
            "category": self.category,
            "name_source": "fcc.m_sMapName",
            "map_system_label": (
                f"{self.map_code.upper()}区" if self.category == "field_code" else None
            ),
            "source_script": self.relative_script,
            "script_sha256": self.script_sha256,
            "map_pixel_size": self.map_size,
            "engine_grid_size": self.grid_size,
            "parsed_path": self.parsed_path,
        }


def parse_props(content: bytes) -> list[PropCall]:
    result: list[PropCall] = []
    for call_match in PROP_CALL_RE.finditer(content):
        resource_match = PROP_RESOURCE_RE.search(call_match.group(2))
        if not resource_match:
            continue
        result.append(
            PropCall(
                kind=call_match.group(1).decode("ascii"),
                source=decode_client_text(resource_match.group(1), ""),
                anchor_x=int(resource_match.group(2)),
                anchor_y=int(resource_match.group(3)),
            )
        )
    return result


def parse_tile_kinds(content: bytes) -> list[TileKind]:
    content = re.sub(rb"/\*.*?\*/", b"", content, flags=re.S)
    content = re.sub(rb"(?m)^[ \t]*//[^\r\n]*", b"", content)
    return [
        TileKind(
            name=decode_client_text(match.group(1), ""),
            walkable=int(match.group(2)) != 0,
            source=decode_client_text(match.group(3), ""),
            crop_x=int(match.group(4)),
            crop_y=int(match.group(5)),
            variants=int(match.group(6)),
        )
        for match in TILE_KIND_RE.finditer(content)
    ]


def parse_tile_links(content: bytes) -> list[TileLink]:
    content = re.sub(rb"/\*.*?\*/", b"", content, flags=re.S)
    content = re.sub(rb"(?m)^[ \t]*//[^\r\n]*", b"", content)
    return [
        TileLink(
            first=decode_client_text(match.group(1), ""),
            second=decode_client_text(match.group(2), ""),
        )
        for match in TILE_LINK_RE.finditer(content)
    ]


def parse_map(script: Path, expanded_root: Path) -> MapRecord | None:
    content = script.read_bytes()
    if not INDEX_RE.search(content):
        return None
    relative = script.relative_to(expanded_root)
    if len(relative.parts) < 4 or not relative.parts[0].upper().startswith("NFT_"):
        return None
    if relative.parts[1].lower() != "map":
        return None
    branch = relative.parts[0]
    fallback_code = script.parent.name
    check_name = decode_client_text(first_group(CHECK_NAME_RE, content), fallback_code)
    map_code = check_name or fallback_code
    map_name = decode_client_text(first_group(MAP_NAME_RE, content), map_code)
    overdata_match = OVERDATA_RE.search(content)
    overdata_kind = None
    overdata_declared_size = None
    overdata_payload = None
    if overdata_match:
        overdata_kind = overdata_match.group(1).decode("ascii").upper()
        overdata_declared_size = int(overdata_match.group(2))
        overdata_payload = bytes.fromhex(
            re.sub(rb"\s+", b"", overdata_match.group(3)).decode("ascii")
        )
    oversrc_raw = first_group(OVERSRC_RE, content)
    oversrc = decode_client_text(oversrc_raw, "") if oversrc_raw else None
    mask_raw = first_group(MASK_IMAGE_RE, content)
    mask_source = decode_client_text(mask_raw, "") if mask_raw else None
    category = "field_code" if FIELD_CODE_RE.fullmatch(map_name) or FIELD_CODE_RE.fullmatch(map_code) else "named"
    return MapRecord(
        script=script,
        relative_script=relative.as_posix(),
        branch=branch,
        map_code=map_code,
        map_name=map_name,
        check_name=check_name,
        script_sha256=digest(content),
        map_size=pair(MAP_SIZE_RE, content),
        grid_size=pair(GRID_SIZE_RE, content),
        mask_source=mask_source,
        tile_kinds=parse_tile_kinds(content),
        tile_links=parse_tile_links(content),
        oversrc=oversrc,
        overdata_kind=overdata_kind,
        overdata_declared_size=overdata_declared_size,
        overdata_payload=overdata_payload,
        props=parse_props(content),
        category=category,
    )


class AleRepository:
    def __init__(self, root: Path) -> None:
        self.root = root
        self.by_logical_path: dict[str, Path] = {}
        self.by_basename: dict[str, list[Path]] = defaultdict(list)
        self.manifests: dict[Path, dict[str, Any]] = {}
        self.pages: dict[tuple[Path, int], Image.Image] = {}
        for manifest_path in root.rglob("frames.json"):
            folder = manifest_path.parent
            logical = folder.relative_to(root).as_posix().lower()
            self.by_logical_path[logical] = folder
            self.by_basename[folder.name.lower()].append(folder)

    def resolve(self, source: str) -> tuple[Path | None, str]:
        logical = normalize_ale_reference(source)
        direct = self.by_logical_path.get(logical.lower())
        if direct:
            return direct, "logical_path"
        basename_matches = self.by_basename.get(Path(logical).name.lower(), [])
        if len(basename_matches) == 1:
            return basename_matches[0], "unique_basename"
        return None, "missing" if not basename_matches else "ambiguous_basename"

    def frame(self, folder: Path, index: int = 0) -> tuple[Image.Image, dict[str, Any]]:
        manifest = self.manifests.get(folder)
        if manifest is None:
            manifest = json.loads((folder / "frames.json").read_text(encoding="utf-8"))
            self.manifests[folder] = manifest
        frames = {int(row["index"]): row for row in manifest["frames"]}
        if index not in frames:
            raise KeyError(f"{folder}: frame {index} does not exist")
        frame = frames[index]
        page_number = int(frame["page"])
        page_key = (folder, page_number)
        page = self.pages.get(page_key)
        if page is None:
            page = Image.open(folder / manifest["pages"][page_number]).convert("RGBA")
            # Map backgrounds reuse a small set of ALE pages.  Bound prop-page
            # caching so a full run cannot retain every source sheet in memory.
            if len(self.pages) >= 48:
                _, discarded = self.pages.popitem()
                discarded.close()
            self.pages[page_key] = page
        image = page.crop(
            (
                int(frame["x"]),
                int(frame["y"]),
                int(frame["x"]) + int(frame["width"]),
                int(frame["y"]) + int(frame["height"]),
            )
        )
        return image, frame

    def logical_path(self, folder: Path) -> str:
        return folder.relative_to(self.root).as_posix()

    def close(self) -> None:
        for page in self.pages.values():
            page.close()
        self.pages.clear()


class MinimapRepository:
    def __init__(self, raw_root: Path) -> None:
        if (raw_root / "raw").is_dir():
            raw_root = raw_root / "raw"
        self.by_branch_and_name: dict[tuple[str, str], Path] = {}
        roots = [raw_root / "map" / "smap"]
        roots.extend(sorted(raw_root.glob("NFT_*/map/smap")))
        roots.append(raw_root / "pic3" / "smap")
        for root in roots:
            if not root.is_dir():
                continue
            branch = root.parts[-3] if root.parts[-3].upper().startswith("NFT_") else "GLOBAL"
            for image_path in root.iterdir():
                if image_path.is_file():
                    self.by_branch_and_name[(branch.lower(), image_path.stem.lower())] = image_path

    def resolve(self, record: MapRecord) -> Path | None:
        candidates = [record.map_code, record.check_name, record.script.stem, record.script.parent.name]
        for candidate in list(candidates):
            without_generation = re.sub(r"^[23]", "", candidate)
            if without_generation != candidate:
                candidates.append(without_generation)
            if without_generation.lower().endswith("1"):
                candidates.append(without_generation[:-1])
        for branch in (record.branch.lower(), "global"):
            for candidate in candidates:
                result = self.by_branch_and_name.get((branch, candidate.lower()))
                if result:
                    return result
        return None


def normalize_raw_reference(value: str) -> str:
    normalized = value.replace("\\", "/").strip()
    normalized = re.sub(r"/+", "/", normalized)
    while normalized.startswith("../"):
        normalized = normalized[3:]
    normalized = normalized.removeprefix("./").lstrip("/")
    lower = normalized.lower()
    map_index = lower.find("map/")
    if map_index >= 0:
        normalized = normalized[map_index:]
    return normalized.lower()


class RawImageRepository:
    """Resolve FCC image paths with NFT-branch precedence and global fallback."""

    def __init__(self, raw_root: Path) -> None:
        if (raw_root / "raw").is_dir():
            raw_root = raw_root / "raw"
        self.root = raw_root
        self.by_branch_and_path: dict[tuple[str, str], Path] = {}
        self.by_basename: dict[str, list[Path]] = defaultdict(list)
        roots: list[tuple[str, Path]] = [("global", raw_root / "map")]
        roots.extend(
            (branch.name.lower(), branch / "map")
            for branch in sorted(raw_root.glob("NFT_*"))
            if (branch / "map").is_dir()
        )
        for branch, map_root in roots:
            if not map_root.is_dir():
                continue
            for image_path in map_root.rglob("*"):
                if not image_path.is_file() or image_path.suffix.lower() not in {
                    ".jpg", ".jpeg", ".png", ".bmp"
                }:
                    continue
                logical = "map/" + image_path.relative_to(map_root).as_posix().lower()
                self.by_branch_and_path[(branch, logical)] = image_path
                self.by_basename[image_path.name.lower()].append(image_path)

    def resolve(self, source: str, branch: str) -> tuple[Path | None, str]:
        logical = normalize_raw_reference(source)
        for branch_key in (branch.lower(), "global"):
            found = self.by_branch_and_path.get((branch_key, logical))
            if found:
                return found, "branch_path" if branch_key != "global" else "global_path"
        matches = self.by_basename.get(Path(logical).name.lower(), [])
        if len(matches) == 1:
            return matches[0], "unique_basename"
        return None, "missing" if not matches else "ambiguous_basename"


def make_colorkey_transparent(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = []
    for red, green, blue, _alpha in rgba.getdata():
        # Old nEngine JPG sprites use near-black as their transparent key. JPEG
        # ringing prevents an exact RGB(0,0,0) test.
        alpha = 0 if max(red, green, blue) < 18 else 255
        pixels.append((red, green, blue, alpha))
    rgba.putdata(pixels)
    return rgba


def build_tile_atlas(
    record: MapRecord,
    repository: RawImageRepository,
) -> tuple[list[Image.Image], dict[str, Any]]:
    tiles: list[Image.Image] = []
    status: dict[str, Any] = {
        "tile_kinds": len(record.tile_kinds),
        "links": len(record.tile_links),
        "sources": [],
        "status": "missing",
    }
    source_cache: dict[Path, Image.Image] = {}
    kind_starts: dict[str, int] = {}
    for kind in record.tile_kinds:
        source_path, resolution = repository.resolve(kind.source, record.branch)
        status["sources"].append(
            {"reference": kind.source, "resolution": resolution, "file": str(source_path or "")}
        )
        if source_path is None:
            status["error"] = f"tile image not found: {kind.source}"
            return [], status
        source = source_cache.get(source_path)
        if source is None:
            source = Image.open(source_path).convert("RGBA")
            source_cache[source_path] = source
        kind_starts[kind.name] = len(tiles)
        for variant in range(kind.variants):
            crop_x = kind.crop_x + variant * 48
            tile = source.crop((crop_x, kind.crop_y, crop_x + 48, kind.crop_y + 24))
            tiles.append(make_colorkey_transparent(tile))

    mask_image: Image.Image | None = None
    if record.tile_links:
        if not record.mask_source:
            status["error"] = "tile links exist but maskimg is missing"
            return [], status
        mask_path, resolution = repository.resolve(record.mask_source, record.branch)
        status["mask"] = {
            "reference": record.mask_source,
            "resolution": resolution,
            "file": str(mask_path or ""),
        }
        if mask_path is None:
            status["error"] = f"mask image not found: {record.mask_source}"
            return [], status
        mask_image = Image.open(mask_path).convert("L")
        for link in record.tile_links:
            first_start = kind_starts.get(link.first)
            second_start = kind_starts.get(link.second)
            if first_start is None or second_start is None or first_start == second_start:
                # Some old scripts contain prefix/self links that the original
                # TLE builder intentionally ignored.
                continue
            for mask_row in range(mask_image.height // 24):
                for variant in range(4):
                    first = tiles[first_start + variant]
                    second = tiles[second_start + variant]
                    mask = mask_image.crop((variant * 48, mask_row * 24, variant * 48 + 48, mask_row * 24 + 24))
                    transition = Image.composite(second, first, mask)
                    transition.putalpha(
                        ImageChops.lighter(first.getchannel("A"), second.getchannel("A"))
                    )
                    tiles.append(transition)

    for source in source_cache.values():
        source.close()
    if mask_image is not None:
        mask_image.close()
    status["generated_tiles"] = len(tiles)
    status["status"] = "ok" if tiles else "missing"
    return tiles, status


def compose_tile_layer(
    record: MapRecord,
    output_dir: Path,
    repository: RawImageRepository,
) -> tuple[Image.Image | None, dict[str, Any]]:
    status: dict[str, Any] = {"status": "missing", "layout": "nengine_isometric_48x12"}
    if not record.map_size or not record.grid_size:
        status["error"] = "missing map or grid size"
        return None, status
    raw_path = output_dir / "raw_indexdata.bin"
    if not raw_path.is_file():
        status["error"] = "navigation extraction did not produce raw_indexdata.bin"
        return None, status
    tiles, atlas_status = build_tile_atlas(record, repository)
    status["atlas"] = atlas_status
    if not tiles:
        status["error"] = atlas_status.get("error", "no tile definitions")
        return None, status
    raw = raw_path.read_bytes()
    width, height = record.grid_size
    if len(raw) != width * height * 3:
        status["error"] = "indexdata size does not match tilesize"
        return None, status
    canvas = Image.new("RGBA", tuple(record.map_size), (0, 0, 0, 255))
    out_of_range: Counter[int] = Counter()
    empty_cells = 0
    for cell in range(width * height):
        offset = cell * 3
        tile_index = int.from_bytes(raw[offset : offset + 2], "little")
        if tile_index == 60000:  # 0xEA60: explicit empty-tile sentinel in nEngine.
            empty_cells += 1
            continue
        if tile_index >= len(tiles):
            out_of_range[tile_index] += 1
            continue
        cell_x = cell % width
        cell_y = cell // width
        top_left_x = cell_x * 48 + (24 if cell_y % 2 else 0) - 24
        top_left_y = cell_y * 12
        canvas.alpha_composite(tiles[tile_index], (top_left_x, top_left_y))
    for tile in tiles:
        tile.close()
    canvas.save(output_dir / "tile_layer.png", compress_level=3)
    status.update(
        {
            "status": "ok" if not out_of_range else "partial",
            "cells": width * height,
            "empty_cells": empty_cells,
            "out_of_range_cells": sum(out_of_range.values()),
            "out_of_range_tile_indices": dict(out_of_range.most_common(20)),
        }
    )
    return canvas, status


def unpack_overdata(
    record: MapRecord,
    output_dir: Path,
    unpacker: Path,
    engine_dll: Path,
) -> bytes | None:
    payload = record.overdata_payload
    if payload is None:
        return None
    if len(payload) != record.overdata_declared_size:
        raise ValueError(
            f"overdata declares {record.overdata_declared_size}, contains {len(payload)}"
        )
    packed_path = output_dir / "packed_overdata.pkh"
    raw_path = output_dir / "raw_overdata.bin"
    if record.overdata_kind == "HEX":
        raw_path.write_bytes(payload)
        return payload
    if record.overdata_kind == "PKH":
        packed_path.write_bytes(payload)
        run_unpacker(unpacker, engine_dll, packed_path, raw_path)
        return raw_path.read_bytes()
    raise ValueError(f"unsupported overdata kind: {record.overdata_kind}")


def compose_background(
    record: MapRecord,
    output_dir: Path,
    repository: AleRepository,
    unpacker: Path,
    engine_dll: Path,
    tile_layer: Image.Image | None,
) -> tuple[Image.Image | None, dict[str, Any]]:
    status: dict[str, Any] = {
        "source": record.oversrc,
        "format": record.overdata_kind,
        "records": 0,
        "status": "missing",
    }
    if not record.map_size:
        status["error"] = "missing map size"
        return None, status
    if not record.oversrc or record.overdata_payload is None:
        if tile_layer is None:
            status["error"] = "missing both tile layer and oversrc/overdata"
            return None, status
        canvas = tile_layer.copy()
        canvas.save(output_dir / "background.png", compress_level=3)
        status["status"] = "not_used"
        return canvas, status
    folder, resolution = repository.resolve(record.oversrc)
    status["resolution"] = resolution
    if folder is None:
        status["error"] = "ALE source was not found"
        if tile_layer is not None:
            canvas = tile_layer.copy()
            canvas.save(output_dir / "background.png", compress_level=3)
            status["fallback"] = "tile_layer"
            return canvas, status
        return None, status
    status["resolved_ale"] = repository.logical_path(folder)
    raw = unpack_overdata(record, output_dir, unpacker, engine_dll)
    if raw is None or len(raw) % 5:
        status["error"] = f"overdata size {0 if raw is None else len(raw)} is not divisible by 5"
        return None, status
    canvas = (
        tile_layer.copy()
        if tile_layer is not None
        else Image.new("RGBA", tuple(record.map_size), (0, 0, 0, 255))
    )
    placements: list[dict[str, Any]] = []
    for offset in range(0, len(raw), 5):
        anchor_x = int.from_bytes(raw[offset : offset + 2], "little")
        anchor_y = int.from_bytes(raw[offset + 2 : offset + 4], "little")
        frame_index = raw[offset + 4]
        frame_image, frame = repository.frame(folder, frame_index)
        top_left = [
            anchor_x + int(frame.get("origin_x", 0)),
            anchor_y + int(frame.get("origin_y", 0)),
        ]
        canvas.alpha_composite(frame_image, tuple(top_left))
        placements.append(
            {
                "anchor": [anchor_x, anchor_y],
                "frame": frame_index,
                "top_left": top_left,
            }
        )
    canvas.save(output_dir / "background.png", compress_level=3)
    (output_dir / "background_placements.json").write_text(
        json.dumps(placements, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    status["records"] = len(placements)
    status["status"] = "ok"
    return canvas, status


def composite_props(
    record: MapRecord,
    background: Image.Image | None,
    output_dir: Path,
    repository: AleRepository,
) -> tuple[dict[str, Any], Image.Image | None]:
    scene = background.copy() if background is not None else None
    objects: list[dict[str, Any]] = []
    resolved = 0
    for index, prop in enumerate(record.props):
        folder, resolution = repository.resolve(prop.source)
        item: dict[str, Any] = {
            "index": index,
            "kind": prop.kind,
            "source_ale": prop.source,
            "anchor": [prop.anchor_x, prop.anchor_y],
            "resolution": resolution,
        }
        if folder is not None:
            try:
                image, frame = repository.frame(folder, 0)
                origin = [int(frame.get("origin_x", 0)), int(frame.get("origin_y", 0))]
                top_left = [prop.anchor_x + origin[0], prop.anchor_y + origin[1]]
                item.update(
                    {
                        "resolved_ale": repository.logical_path(folder),
                        "origin": origin,
                        "top_left": top_left,
                        "status": "ok",
                    }
                )
                if scene is not None:
                    scene.alpha_composite(image, tuple(top_left))
                resolved += 1
            except (OSError, KeyError, ValueError) as error:
                item.update({"status": "error", "error": str(error)})
        else:
            item["status"] = "missing"
        objects.append(item)
    result = {
        "count": len(objects),
        "resolved": resolved,
        "missing": len(objects) - resolved,
        "objects": objects,
    }
    (output_dir / "scene_objects.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if scene is not None:
        scene.save(output_dir / "composite.png", compress_level=3)
        thumbnail = scene.copy()
        thumbnail.thumbnail((480, 360), Image.Resampling.LANCZOS)
        thumbnail.convert("RGB").save(output_dir / "thumbnail.jpg", quality=86)
        thumbnail.close()
    return result, scene


def copy_minimap(record: MapRecord, output_dir: Path, repository: MinimapRepository) -> dict[str, Any]:
    source = repository.resolve(record)
    if source is None:
        return {"status": "missing"}
    destination = output_dir / "minimap.jpg"
    with Image.open(source) as image:
        image.convert("RGB").save(destination, quality=95)
    return {"status": "ok", "source": str(source), "file": destination.name}


def output_layout(records: list[MapRecord]) -> dict[str, Path]:
    groups_by_hash: dict[str, list[MapRecord]] = defaultdict(list)
    for record in records:
        groups_by_hash[record.script_sha256].append(record)
    code_variants: dict[str, list[tuple[str, list[MapRecord]]]] = defaultdict(list)
    for script_hash, group in groups_by_hash.items():
        canonical = sorted(group, key=lambda item: item.relative_script.lower())[0]
        code_variants[canonical.map_code.lower()].append((script_hash, group))

    layout: dict[str, Path] = {}
    used_paths: set[str] = set()
    for code_key, variants in sorted(code_variants.items()):
        variants.sort(key=lambda item: min(row.relative_script.lower() for row in item[1]))
        base = safe_slug(code_key, "unnamed_map")
        for variant_index, (script_hash, group) in enumerate(variants, 1):
            canonical = sorted(group, key=lambda item: item.relative_script.lower())[0]
            if len(variants) == 1:
                relative = Path("maps") / base
            else:
                branch_slug = safe_slug(canonical.branch, "source")
                relative = Path("maps") / base / f"variant_{variant_index:02d}_{branch_slug}"
            candidate = relative.as_posix().lower()
            if candidate in used_paths:
                relative = relative.parent / f"{relative.name}_{variant_index:03d}"
                candidate = relative.as_posix().lower()
            used_paths.add(candidate)
            layout[script_hash] = relative
    return layout


def render_map(
    canonical: MapRecord,
    aliases: list[MapRecord],
    output_root: Path,
    relative_output: Path,
    ale_repository: AleRepository,
    minimap_repository: MinimapRepository,
    raw_image_repository: RawImageRepository,
    unpacker: Path,
    engine_dll: Path,
) -> dict[str, Any]:
    output_dir = output_root / relative_output
    output_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, Any] = {
        "map_code": canonical.map_code,
        "map_name": canonical.map_name,
        "check_name": canonical.check_name,
        "category": canonical.category,
        "name_source": "fcc.m_sMapName",
        "map_system_label": (
            f"{canonical.map_code.upper()}区" if canonical.category == "field_code" else None
        ),
        "output": relative_output.as_posix(),
        "script_sha256": canonical.script_sha256,
        "source_scripts": [row.relative_script for row in aliases],
        "source_branches": sorted({row.branch for row in aliases}),
        "map_pixel_size": canonical.map_size,
        "engine_grid_size": canonical.grid_size,
    }
    errors: list[str] = []
    try:
        navigation = extract_navigation(canonical.script, output_dir, unpacker, engine_dll)
        result["navigation"] = {
            "status": "ok",
            "passable": navigation["runtime_navigation"]["passable"],
            "blocked": navigation["runtime_navigation"]["blocked"],
        }
    except (OSError, RuntimeError, ValueError) as error:
        result["navigation"] = {"status": "error", "error": str(error)}
        errors.append(f"navigation: {error}")

    tile_layer: Image.Image | None = None
    try:
        tile_layer, tile_status = compose_tile_layer(
            canonical, output_dir, raw_image_repository
        )
        result["tile_layer"] = tile_status
        if tile_status["status"] not in {"ok", "not_used"}:
            errors.append(f"tile layer: {tile_status.get('error', tile_status['status'])}")
    except (OSError, RuntimeError, ValueError, KeyError, IndexError) as error:
        result["tile_layer"] = {"status": "error", "error": str(error)}
        errors.append(f"tile layer: {error}")

    background: Image.Image | None = None
    try:
        background, background_status = compose_background(
            canonical, output_dir, ale_repository, unpacker, engine_dll, tile_layer
        )
        result["background"] = background_status
        if background_status["status"] not in {"ok", "not_used"}:
            errors.append(f"background: {background_status.get('error', 'missing')}")
    except (OSError, RuntimeError, ValueError, KeyError) as error:
        result["background"] = {"status": "error", "error": str(error)}
        errors.append(f"background: {error}")
        # A broken or incomplete overlay ALE must not discard an otherwise
        # valid reconstructed tile layer.
        if tile_layer is not None:
            background = tile_layer.copy()
            background.save(output_dir / "background.png", compress_level=3)
            result["background"]["fallback"] = "tile_layer"

    scene: Image.Image | None = None
    try:
        props, scene = composite_props(canonical, background, output_dir, ale_repository)
        result["scene_objects"] = {
            "count": props["count"],
            "resolved": props["resolved"],
            "missing": props["missing"],
        }
        if props["missing"]:
            errors.append(f"scene objects: {props['missing']} unresolved")
    except (OSError, ValueError, KeyError) as error:
        result["scene_objects"] = {"status": "error", "error": str(error)}
        errors.append(f"scene objects: {error}")

    try:
        result["minimap"] = copy_minimap(canonical, output_dir, minimap_repository)
        if result["minimap"]["status"] != "ok":
            errors.append("minimap: missing")
    except OSError as error:
        result["minimap"] = {"status": "error", "error": str(error)}
        errors.append(f"minimap: {error}")

    result["status"] = "ok" if not errors else "partial"
    result["issues"] = errors
    (output_dir / "map_metadata.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    if scene is not None:
        scene.close()
    if background is not None:
        background.close()
    if tile_layer is not None:
        tile_layer.close()
    return result


def write_catalogs(
    output_root: Path,
    records: list[MapRecord],
    unique_results: list[dict[str, Any]],
) -> None:
    output_root.mkdir(parents=True, exist_ok=True)
    sources = [record.source_json() for record in sorted(records, key=lambda item: item.relative_script.lower())]
    summary = {
        "format": "starhome_glory_map_catalog_v1",
        "source_scripts": len(records),
        "unique_scripts": len({record.script_sha256 for record in records}),
        "field_code_sources": sum(record.category == "field_code" for record in records),
        "named_sources": sum(record.category == "named" for record in records),
        "branches": dict(sorted(Counter(record.branch for record in records).items())),
        "unique_maps_ok": sum(result["status"] == "ok" for result in unique_results),
        "unique_maps_partial": sum(result["status"] != "ok" for result in unique_results),
        "sources": sources,
    }
    (output_root / "map_catalog.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output_root / "unique_maps.json").write_text(
        json.dumps(unique_results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    issues = [result for result in unique_results if result["status"] != "ok"]
    (output_root / "map_issues.json").write_text(
        json.dumps(issues, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    columns = [
        "branch",
        "map_code",
        "map_name",
        "check_name",
        "category",
        "name_source",
        "map_system_label",
        "source_script",
        "script_sha256",
        "parsed_path",
        "map_width",
        "map_height",
        "grid_width",
        "grid_height",
    ]
    with (output_root / "map_names.csv").open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns)
        writer.writeheader()
        for record in sorted(records, key=lambda item: (item.map_name.lower(), item.branch, item.map_code.lower())):
            writer.writerow(
                {
                    "branch": record.branch,
                    "map_code": record.map_code,
                    "map_name": record.map_name,
                    "check_name": record.check_name,
                    "category": record.category,
                    "name_source": "fcc.m_sMapName",
                    "map_system_label": (
                        f"{record.map_code.upper()}区" if record.category == "field_code" else ""
                    ),
                    "source_script": record.relative_script,
                    "script_sha256": record.script_sha256,
                    "parsed_path": record.parsed_path,
                    "map_width": record.map_size[0] if record.map_size else "",
                    "map_height": record.map_size[1] if record.map_size else "",
                    "grid_width": record.grid_size[0] if record.grid_size else "",
                    "grid_height": record.grid_size[1] if record.grid_size else "",
                }
            )

    cards: list[str] = []
    for result in sorted(unique_results, key=lambda item: (item["map_name"].lower(), item["map_code"].lower())):
        image_path = (Path(result["output"]) / "thumbnail.jpg").as_posix()
        issues_text = "；".join(result["issues"]) if result["issues"] else "完整"
        cards.append(
            "<article data-search=\"{search}\"><a href=\"{target}\"><img loading=\"lazy\" src=\"{image}\" "
            "alt=\"{name}\"></a><h2>{name}</h2><p>{code} · {category}</p><p>{branches}</p>"
            "<p class=\"status {status}\">{issues}</p></article>".format(
                search=html.escape(f"{result['map_name']} {result['map_code']} {' '.join(result['source_branches'])}".lower()),
                target=html.escape((Path(result["output"]) / "composite.png").as_posix()),
                image=html.escape(image_path),
                name=html.escape(result["map_name"]),
                code=html.escape(result["map_code"]),
                category="野外编号" if result["category"] == "field_code" else "命名地图",
                branches=html.escape(", ".join(result["source_branches"])),
                status=html.escape(result["status"]),
                issues=html.escape(issues_text),
            )
        )
    page = """<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><title>荣耀版地图目录</title>
<style>
body{margin:0;background:#10161d;color:#e8f3ff;font:14px system-ui,sans-serif}header{position:sticky;top:0;background:#16222dcc;padding:16px;backdrop-filter:blur(8px);z-index:2}h1{margin:0 0 10px}input{width:min(600px,90vw);padding:9px 12px;background:#071018;color:white;border:1px solid #3b769d;border-radius:6px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:14px;padding:16px}article{background:#172531;border:1px solid #29465b;border-radius:8px;overflow:hidden;padding-bottom:10px}img{width:100%;height:190px;object-fit:contain;background:#000}h2,p{margin:8px 12px}.status{color:#7fffb4}.status.partial{color:#ffd36b}</style></head>
<body><header><h1>荣耀版地图目录</h1><input id="q" placeholder="搜索地图名称、代码或 NFT 分支"></header><main>""" + "\n".join(cards) + """</main>
<script>q.oninput=()=>{const s=q.value.toLowerCase();document.querySelectorAll('article').forEach(x=>x.hidden=!x.dataset.search.includes(s))}</script></body></html>"""
    (output_root / "index.html").write_text(page, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expanded_root", type=Path)
    parser.add_argument("ale_root", type=Path)
    parser.add_argument("raw_root", type=Path)
    parser.add_argument("output_root", type=Path)
    parser.add_argument("--unpacker", type=Path, required=True)
    parser.add_argument("--engine-dll", type=Path, required=True)
    parser.add_argument("--catalog-only", action="store_true")
    parser.add_argument("--limit", type=int, help="render only the first N unique maps")
    parser.add_argument(
        "--retry-structural-partials",
        action="store_true",
        help="rerender only maps whose navigation/tile/background structure failed previously",
    )
    args = parser.parse_args()

    scripts = sorted(args.expanded_root.glob("NFT_*/map/**/*.cab"))
    records = [record for script in scripts if (record := parse_map(script, args.expanded_root))]
    layout = output_layout(records)
    groups: dict[str, list[MapRecord]] = defaultdict(list)
    for record in records:
        record.parsed_path = layout[record.script_sha256].as_posix()
        groups[record.script_sha256].append(record)

    print(
        json.dumps(
            {
                "source_scripts": len(records),
                "unique_scripts": len(groups),
                "field_code_sources": sum(row.category == "field_code" for row in records),
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    args.output_root.mkdir(parents=True, exist_ok=True)
    if args.catalog_only:
        write_catalogs(args.output_root, records, [])
        return 0

    ale_repository = AleRepository(args.ale_root)
    minimap_repository = MinimapRepository(args.raw_root)
    raw_image_repository = RawImageRepository(args.raw_root)
    unique_results: list[dict[str, Any]] = []
    ordered_groups = sorted(groups.items(), key=lambda item: layout[item[0]].as_posix())
    previous_results: dict[str, dict[str, Any]] = {}
    previous_path = args.output_root / "unique_maps.json"
    if args.retry_structural_partials and previous_path.is_file():
        previous_results = {
            row["script_sha256"]: row
            for row in json.loads(previous_path.read_text(encoding="utf-8"))
        }
        ordered_groups = [
            item
            for item in ordered_groups
            if item[0] not in previous_results
            or previous_results[item[0]].get("navigation", {}).get("status") != "ok"
            or previous_results[item[0]].get("tile_layer", {}).get("status") != "ok"
            or previous_results[item[0]].get("background", {}).get("status") == "error"
            or previous_results[item[0]].get("background", {}).get("status") == "missing"
            or previous_results[item[0]].get("minimap", {}).get("status") != "ok"
        ]
    if args.limit is not None:
        ordered_groups = ordered_groups[: args.limit]
    try:
        for index, (script_hash, aliases) in enumerate(ordered_groups, 1):
            canonical = sorted(aliases, key=lambda item: item.relative_script.lower())[0]
            print(
                f"[{index}/{len(ordered_groups)}] {canonical.map_name} ({canonical.map_code})",
                flush=True,
            )
            try:
                result = render_map(
                    canonical,
                    aliases,
                    args.output_root,
                    layout[script_hash],
                    ale_repository,
                    minimap_repository,
                    raw_image_repository,
                    args.unpacker,
                    args.engine_dll,
                )
            except Exception as error:  # Keep the full batch auditable.
                result = {
                    "map_code": canonical.map_code,
                    "map_name": canonical.map_name,
                    "category": canonical.category,
                    "output": layout[script_hash].as_posix(),
                    "script_sha256": script_hash,
                    "source_scripts": [row.relative_script for row in aliases],
                    "source_branches": sorted({row.branch for row in aliases}),
                    "status": "error",
                    "issues": [f"unhandled: {type(error).__name__}: {error}"],
                }
                error_dir = args.output_root / layout[script_hash]
                error_dir.mkdir(parents=True, exist_ok=True)
                (error_dir / "map_metadata.json").write_text(
                    json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
                )
            unique_results.append(result)
    finally:
        ale_repository.close()

    if previous_results:
        for result in unique_results:
            previous_results[result["script_sha256"]] = result
        unique_results = sorted(
            previous_results.values(), key=lambda row: row["output"].lower()
        )
    write_catalogs(args.output_root, records, unique_results)
    print(
        json.dumps(
            {
                "rendered": len(unique_results),
                "complete": sum(row["status"] == "ok" for row in unique_results),
                "partial_or_error": sum(row["status"] != "ok" for row in unique_results),
                "output": str(args.output_root.resolve()),
            },
            ensure_ascii=False,
        ),
        flush=True,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
