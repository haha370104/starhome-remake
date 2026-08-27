#!/usr/bin/env python3
"""Import the Glory-edition base hall with semantic scene ownership.

FCC call order preserves the legacy static construction, including structural
pieces that were never members of one global Y-sort.  A reusable depth profile
may then promote foreground pixels over a shallower current owner.  Dynamic
actors and promoted pixels share those same baselines.  This hybrid rule keeps
the source-faithful room assembly while avoiding both world-coordinate patches
and one-baseline-for-the-whole-sprite failures.
"""

from __future__ import annotations

import hashlib
import json
import re
import shutil
from collections import defaultdict
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageChops, ImageDraw


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
SOURCE_MAP = OUTPUTS_ROOT / "starhome_lz_ry_maps_parsed" / "maps" / "roomsvr1" / "variant_02_nft_bt"
SOURCE_FCC = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ftc_resources" / "expanded" / "NFT_BT" / "map" / "RoomSvr1" / "roomsvr1.fcc.cab"
TRANSPORT_CLASS_SOURCE = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ftc_resources" / "expanded" / "transport" / "transport.fcc.cab"
ALE_ROOT = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed" / "ale_sprites"
DESTINATION = PROJECT_ROOT / "assets" / "maps" / "yian_harbor" / "hall_floor_1"

BUSINESS_NAMES = {
    "map/mapimg/house/chn_2005_06_28_19_30_52_38/as4": "exit_to_city",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/dimiandiannaobu": "floor_console",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongjiantaibian01": "central_platform_edge_outer",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongjiantaibian01bu": "central_platform_edge_left",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongjiantaibian02": "central_platform_edge_right",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongjiantaijiao01": "central_platform_corner_left",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongjiantaijiao02bu": "central_platform_corner_right",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongxindiannao": "central_console",
    "map/mapimg/house/chn_2005_06_28_19_30_58_39/zhongxindiannao01": "central_console_wide",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/guandao": "wall_pipe_tall",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/guandao01": "wall_pipe_left",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/guandao01bu": "wall_pipe_right",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/louti": "stairway",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/men": "doorway_center",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/menbu": "doorway_left",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/menbubu": "doorway_right",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/neiqiang01": "inner_wall_segment_01",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/neiqiang01a": "inner_wall_segment_02",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/neiqiang01abu": "inner_wall_segment_03",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/neiqiang01bu": "inner_wall_segment_04",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/neiqiang02": "inner_wall_segment_05",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/neiqiang02a": "inner_wall_segment_06",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang01": "outer_wall_segment_01",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang01a": "outer_wall_segment_02",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang01abu": "outer_wall_segment_03",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang01abubu": "outer_wall_segment_04",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang01bu": "outer_wall_segment_05",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang01bubu": "outer_wall_segment_06",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang02": "outer_wall_segment_07",
    "map/mapimg/house/chn_2005_06_28_19_31_04_40/waiqiang02a": "outer_wall_segment_08",
    "map/mapimg/house/coffee/zhongjiantaibian01bu": "central_platform_edge_center",
    "map/mapimg/house/coffee/zhongjiantaibian02": "central_platform_edge_right",
    "map/mapimg/house/coffee/zhongjiantaijiao02bu": "central_platform_corner_right",
}

STAIRWAY_LOGICAL_PATH = "map/mapimg/house/chn_2005_06_28_19_31_04_40/louti"
EXIT_TRANSITION_ID = "exit_to_city"
EXIT_TRANSITION_LOGICAL_PATH = "map/mapimg/house/chn_2005_06_28_19_30_52_38/as4"
TRANSPORT_FRAME_DURATION_MS = 100
WORLD_UNDERLAY_BASELINE = -1_000_000
STAIRWAY_DEPTH_QUANTUM = 12
STAIRWAY_CONTACT_INSET = 15
SEMANTIC_CHUNK_SIZE = 256
SEMANTIC_ATLAS_WIDTH = 1024
SEMANTIC_ATLAS_PADDING = 1
CALL_LINE_RE = re.compile(
    rb"(?m)^[ \t]*(?P<comment>//+)?[ \t]*(?P<kind>AddImgEx|AddImg)"
    rb"\s*\((?P<args>[^\r\n;]*)\)\s*;"
)


def read_json(path: Path) -> dict:
    """Read a UTF-8 JSON object from ``path``."""
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict, *, compact: bool = False) -> None:
    """Write ``value`` as stable UTF-8 JSON for runtime or audit use.

    Generated runtime manifests may use one compact line so their Git change
    size reflects a generated artifact instead of tens of thousands of
    formatting-only lines.  Human-facing audit files remain indented.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    indent = None if compact else 2
    separators = (",", ":") if compact else None
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=indent, separators=separators) + "\n",
        encoding="utf-8",
    )


def sha256(path: Path) -> str:
    """Return the SHA-256 digest of one source or generated asset."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def decode_client_text(value: bytes) -> str:
    """Decode legacy client source bytes without dropping invalid evidence."""
    return value.decode("gb18030", errors="replace")


def split_arguments(value: bytes) -> list[bytes]:
    """Split FCC arguments without splitting commas inside quoted payloads."""
    result: list[bytes] = []
    start = 0
    quote = 0
    escaped = False
    for index, byte in enumerate(value):
        if escaped:
            escaped = False
            continue
        if byte == 0x5C and quote:
            escaped = True
            continue
        if quote:
            if byte == quote:
                quote = 0
            continue
        if byte in (0x22, 0x27):
            quote = byte
        elif byte == 0x2C:
            result.append(value[start:index].strip())
            start = index + 1
    result.append(value[start:].strip())
    return result


def string_argument(value: bytes) -> str:
    """Normalize one FCC string argument while retaining its decoded content."""
    token = value.strip()
    if token.startswith(b"$+"):
        token = token[2:].strip()
    if len(token) >= 2 and token[:1] in (b"'", b'"') and token[-1:] == token[:1]:
        token = token[1:-1]
    return decode_client_text(token)


def parse_source_placements(path: Path) -> list[dict[str, Any]]:
    """Parse active and commented AddImg calls in original FCC source order."""
    placements: list[dict[str, Any]] = []
    for source_index, match in enumerate(CALL_LINE_RE.finditer(path.read_bytes())):
        kind = match.group("kind").decode("ascii")
        values = split_arguments(match.group("args"))
        comment_prefix = (match.group("comment") or b"").decode("ascii")
        comment_state = "active" if not comment_prefix else "line_comment" if comment_prefix == "//" else "disabled_marker"
        if kind == "AddImgEx":
            if len(values) < 6:
                raise ValueError(f"AddImgEx #{source_index} has only {len(values)} arguments")
            handler = string_argument(values[0])
            resource = string_argument(values[1])
            anchor = [int(values[2]), int(values[3])]
            numeric_args = [int(values[4]), int(values[5])]
            payload = string_argument(values[6]) if len(values) >= 7 else None
            payload_raw_hex = values[6].hex().upper() if len(values) >= 7 else None
        else:
            if len(values) < 3:
                raise ValueError(f"AddImg #{source_index} has only {len(values)} arguments")
            handler = None
            resource = string_argument(values[0])
            anchor = [int(values[1]), int(values[2])]
            numeric_args = None
            payload = None
            payload_raw_hex = None
        placements.append({
            "source_index": source_index,
            "kind": kind,
            "resource": resource,
            "anchor": anchor,
            "comment_prefix": comment_prefix,
            "comment_state": comment_state,
            "render_enabled": comment_state == "active",
            "handler": handler,
            "numeric_args": numeric_args,
            "payload": payload,
            "payload_raw_hex": payload_raw_hex,
            "raw_arguments": decode_client_text(match.group("args")),
        })
    return placements


def merge_source_placements(scene: dict, source_path: Path) -> list[dict[str, Any]]:
    """Merge parsed map objects with FCC comment and payload evidence."""
    source_records = parse_source_placements(source_path)
    parsed_records = scene["objects"]
    if len(source_records) != len(parsed_records):
        raise RuntimeError(f"FCC has {len(source_records)} placements, parsed map has {len(parsed_records)}")
    merged: list[dict[str, Any]] = []
    for source, parsed in zip(source_records, parsed_records, strict=True):
        if source["kind"] != parsed["kind"] or source["anchor"] != parsed["anchor"]:
            raise RuntimeError(f"FCC placement #{source['source_index']} does not match parsed map")
        if source["resource"].replace("\\", "/").lower() != parsed["source_ale"].replace("\\", "/").lower():
            raise RuntimeError(f"FCC resource #{source['source_index']} does not match parsed map")
        merged.append({**parsed, **source})
    return merged


def export_first_frame(logical_path: str, destination: Path) -> dict:
    """Export the first ALE frame and return provenance for a business asset."""
    source_dir = ALE_ROOT / Path(logical_path)
    metadata = read_json(source_dir / "frames.json")
    frame = metadata["frames"][0]
    source_sheet = source_dir / metadata["pages"][frame["page"]]
    with Image.open(source_sheet) as image:
        crop = image.crop((frame["x"], frame["y"], frame["x"] + frame["width"], frame["y"] + frame["height"]))
        crop.save(destination, compress_level=3)
    return {
        "source_logical_path": logical_path + ".ale",
        "source_frames_metadata": str((source_dir / "frames.json").relative_to(OUTPUTS_ROOT)).replace("\\", "/"),
        "source_sheet_sha256": sha256(source_sheet),
        "frame_index": int(frame["index"]),
        "frame_origin": [int(frame["origin_x"]), int(frame["origin_y"])],
        "frame_size": [int(frame["width"]), int(frame["height"])],
    }


def build_sprite_frames_resource(texture_path: Path, frame_count: int, frame_width: int, frame_height: int) -> str:
    """Build a looping Godot SpriteFrames resource for one horizontal atlas.

    Args:
        texture_path: Generated business-semantic atlas inside the Godot project.
        frame_count: Number of equally sized frames stored from left to right.
        frame_width: Width of each normalized atlas cell in pixels.
        frame_height: Height of each normalized atlas cell in pixels.

    Returns:
        Complete UTF-8 Godot text resource content using the ``active`` animation.
    """
    texture_resource = "res://" + str(texture_path.relative_to(PROJECT_ROOT)).replace("\\", "/")
    subresources: list[str] = []
    entries: list[str] = []
    for frame_index in range(frame_count):
        subresources.extend([
            f'[sub_resource type="AtlasTexture" id="frame_{frame_index}"]',
            'atlas = ExtResource("texture")',
            f"region = Rect2({frame_index * frame_width}, 0, {frame_width}, {frame_height})",
            "filter_clip = true",
            "",
        ])
        entries.append(f'{{"duration": 1.0, "texture": SubResource("frame_{frame_index}")}}')
    return (
        f'[gd_resource type="SpriteFrames" load_steps={frame_count + 2} format=3]\n\n'
        f'[ext_resource type="Texture2D" path={json.dumps(texture_resource)} id="texture"]\n\n'
        + "\n".join(subresources)
        + '[resource]\nanimations = [{\n"frames": ['
        + ", ".join(entries)
        + f'],\n"loop": true,\n"name": &"active",\n"speed": {1000.0 / TRANSPORT_FRAME_DURATION_MS:.1f}\n}}]\n'
    )


def export_transition_animation(logical_path: str, transition: dict, placement: dict) -> dict:
    """Export one promoted transport animation and its auditable presentation.

    The Glory hall FCC comments out transport calls as static placements while
    the extracted reciprocal topology marks the route enabled.  Keeping this
    animation outside semantic static layers preserves both facts: the source
    comment remains evidence and the enabled transition receives a dynamic
    presentation instead of a frozen first frame.

    Args:
        logical_path: Normalized Glory ALE path without its extension.
        transition: Extracted enabled transition record for this transport.
        placement: Matching parsed FCC AddImgEx placement with source evidence.

    Returns:
        Business-semantic runtime presentation plus source provenance.
    """
    source_dir = ALE_ROOT / Path(logical_path)
    frames_path = source_dir / "frames.json"
    metadata = read_json(frames_path)
    frames = metadata["frames"]
    if int(metadata["frame_count"]) != len(frames) or not frames:
        raise RuntimeError("Transport frame metadata is empty or inconsistent")
    origins = {(int(frame["origin_x"]), int(frame["origin_y"])) for frame in frames}
    sizes = {(int(frame["width"]), int(frame["height"])) for frame in frames}
    if origins != {(0, 0)} or len(sizes) != 1:
        raise RuntimeError(f"Transport frames require unexpected normalization: origins={origins}, sizes={sizes}")

    frame_width, frame_height = next(iter(sizes))
    target_dir = DESTINATION / "transitions" / EXIT_TRANSITION_ID
    target_dir.mkdir(parents=True, exist_ok=True)
    atlas_path = target_dir / "frames.png"
    atlas = Image.new("RGBA", (frame_width * len(frames), frame_height), (0, 0, 0, 0))
    source_sheets: dict[int, Image.Image] = {}
    try:
        for frame in frames:
            page = int(frame["page"])
            if page not in source_sheets:
                source_sheets[page] = Image.open(source_dir / metadata["pages"][page]).convert("RGBA")
            crop = source_sheets[page].crop((
                int(frame["x"]),
                int(frame["y"]),
                int(frame["x"]) + frame_width,
                int(frame["y"]) + frame_height,
            ))
            atlas.alpha_composite(crop, (int(frame["index"]) * frame_width, 0))
            crop.close()
        atlas.save(atlas_path, compress_level=3)
    finally:
        atlas.close()
        for sheet in source_sheets.values():
            sheet.close()

    resource_path = target_dir / "animation_frames.tres"
    resource_path.write_text(
        build_sprite_frames_resource(atlas_path, len(frames), frame_width, frame_height),
        encoding="utf-8",
        newline="\n",
    )
    presentation = {
        "asset_id": "maps/yian_harbor/hall_floor_1/transitions/exit_to_city",
        "kind": "animated_sprite",
        "resource": "res://assets/maps/yian_harbor/hall_floor_1/transitions/exit_to_city/animation_frames.tres",
        "animation": "active",
        "anchor": [int(value) for value in placement["anchor"]],
        "offset": [0, 0],
        "centered": False,
        "interaction_rect": [0, 0, frame_width, frame_height],
        "interaction_space": "asset_local_fixed_bounds",
        "sort_baseline": int(placement["anchor"][1]),
        "frame_count": len(frames),
        "frame_duration_ms": TRANSPORT_FRAME_DURATION_MS,
        "loop": True,
        "activation": "enabled_transition",
    }
    source_raw = Path(metadata["source"])
    audit = {
        "schema_version": 1,
        "transition_id": EXIT_TRANSITION_ID,
        "presentation": presentation,
        "source_audit": {
            "source_release": "starhome_lz_ry",
            "source_map_code": transition["source_map_code"],
            "source_script": transition["source_script"],
            "source_line": int(transition["source_line"]),
            "source_comment_state": placement["comment_state"],
            "promotion_reason": transition["source_state"],
            "source_transport_handler": placement["handler"],
            "source_transport_class": str(TRANSPORT_CLASS_SOURCE.relative_to(OUTPUTS_ROOT)).replace("\\", "/"),
            "source_transport_class_sha256": sha256(TRANSPORT_CLASS_SOURCE),
            "source_playdelay_ms": TRANSPORT_FRAME_DURATION_MS,
            "source_logical_path": logical_path + ".ale",
            "source_raw": str(source_raw.relative_to(OUTPUTS_ROOT)).replace("\\", "/"),
            "source_raw_sha256": sha256(source_raw),
            "source_frames_metadata": str(frames_path.relative_to(OUTPUTS_ROOT)).replace("\\", "/"),
            "source_frames_metadata_sha256": sha256(frames_path),
            "source_sheet_sha256": sha256(source_dir / metadata["pages"][0]),
            "frame_origins": [[int(frame["origin_x"]), int(frame["origin_y"])] for frame in frames],
            "frame_sizes": [[int(frame["width"]), int(frame["height"])] for frame in frames],
            "destination_map_code": transition["destination_map_code"],
            "destination_entry_number": int(transition["destination_entry_number"]),
            "approach_point": [int(value) for value in transition["approach_point"]],
            "payload": transition["payload"],
        },
    }
    write_json(target_dir / "import_metadata.json", audit)
    return audit


def build_stairway_depth_profile(props_dir: Path) -> tuple[dict, dict[str, Any]]:
    """Generate an asset-local tread mask and quantized handrail depth field.

    Rigid side rails share the bottom envelope of their whole segment, keeping
    their tall posts on one ground plane.  The diagonal front crossbar uses a
    per-column bottom envelope, so its left side naturally sorts shallower than
    its right corner.  The result is reusable for every stair placement and
    contains no map/world coordinates.
    """
    source_path = props_dir / "stairway.png"
    with Image.open(source_path) as source_file:
        source = source_file.convert("RGBA")
    width, height = source.size
    segment_polygons = {
        "left_slope": [[0, 128], [96, 3], [109, 0], [128, 10], [109, 31], [18, 143], [19, 153], [0, 161]],
        "right_slope": [[233, 61], [248, 46], [275, 77], [275, 179], [207, 240], [178, 232], [190, 213], [258, 158], [258, 83]],
        "front_crossbar": [[0, 146], [158, 222], [191, 212], [208, 240], [157, 240], [0, 165]],
    }
    segment_depth_modes = {
        "left_slope": "segment_bottom_envelope",
        "right_slope": "segment_bottom_envelope",
        "front_crossbar": "column_bottom_envelope",
    }
    alpha = np.asarray(source.getchannel("A"), dtype=np.uint8)
    segment_masks: dict[str, np.ndarray] = {}
    # Front pixels own shared joints; remaining segments are made disjoint in
    # deterministic order so every source-alpha pixel gets at most one depth.
    claimed = np.zeros((height, width), dtype=bool)
    for segment_name in ("front_crossbar", "left_slope", "right_slope"):
        polygon_mask = Image.new("L", (width, height), 0)
        ImageDraw.Draw(polygon_mask).polygon(
            [tuple(point) for point in segment_polygons[segment_name]], fill=255
        )
        visible = (np.asarray(polygon_mask, dtype=np.uint8) > 0) & (alpha > 0)
        visible &= ~claimed
        segment_masks[segment_name] = visible
        claimed |= visible
    rail = claimed
    tread = (alpha > 0) & ~rail
    if not rail.any() or not tread.any() or np.any(rail & tread):
        raise RuntimeError("Stairway depth profile did not partition the source alpha")

    profile_dir = DESTINATION / "depth_profiles" / "industrial_stairway"
    profile_dir.mkdir(parents=True, exist_ok=True)
    mask_paths: dict[str, str] = {}
    component_paths: dict[str, str] = {}
    source_pixels = np.asarray(source, dtype=np.uint8)
    for component_id, mask in (("tread_underlay", tread), ("handrail_occluder", rail)):
        mask_path = profile_dir / f"{component_id}_mask.png"
        Image.fromarray(mask.astype(np.uint8) * 255, mode="L").save(mask_path, compress_level=3)
        component = np.zeros_like(source_pixels)
        component[mask] = source_pixels[mask]
        component_path = profile_dir / f"{component_id}.png"
        Image.fromarray(component, mode="RGBA").save(component_path, compress_level=3)
        mask_paths[component_id] = "res://" + str(mask_path.relative_to(PROJECT_ROOT)).replace("\\", "/")
        component_paths[component_id] = "res://" + str(component_path.relative_to(PROJECT_ROOT)).replace("\\", "/")

    depth_field = np.zeros((height, width), dtype=np.uint8)
    depth_bands: dict[int, np.ndarray] = {}
    for segment_name, segment_mask in segment_masks.items():
        segment_y = np.flatnonzero(np.any(segment_mask, axis=1))
        segment_contact_y = max(0, int(segment_y.max()) - STAIRWAY_CONTACT_INSET)
        for x in range(width):
            column_y = np.flatnonzero(segment_mask[:, x])
            if column_y.size == 0:
                continue
            if segment_depth_modes[segment_name] == "segment_bottom_envelope":
                contact_y = segment_contact_y
            else:
                contact_y = max(0, int(column_y.max()) - STAIRWAY_CONTACT_INSET)
            baseline_local_y = (contact_y // STAIRWAY_DEPTH_QUANTUM) * STAIRWAY_DEPTH_QUANTUM
            column_pixels = segment_mask[:, x]
            depth_field[column_pixels, x] = baseline_local_y + 1
            depth_bands.setdefault(
                baseline_local_y, np.zeros((height, width), dtype=bool)
            )[column_pixels, x] = True
    if not depth_bands or np.any((depth_field > 0) != rail):
        raise RuntimeError("Stairway depth field does not cover the handrail mask")
    depth_field_path = profile_dir / "handrail_depth_field.png"
    Image.fromarray(depth_field, mode="L").save(depth_field_path, compress_level=3)
    depth_field_res_path = "res://" + str(depth_field_path.relative_to(PROJECT_ROOT)).replace("\\", "/")

    profile = {
        "schema_version": 1,
        "profile_id": "industrial_stairway_traversable",
        "asset_id": "maps/yian_harbor/hall_floor_1/props/stairway",
        "coordinate_space": "asset_local_pixels",
        "source_size": [width, height],
        "mask_generation": {
            "method": "segmented_column_ground_envelope_quantized",
            "segment_polygons": segment_polygons,
            "segment_depth_modes": segment_depth_modes,
            "contact_inset": STAIRWAY_CONTACT_INSET,
            "depth_quantum": STAIRWAY_DEPTH_QUANTUM,
            "review_note": "多边形、列底包络与深度量化均位于资产局部坐标，可复用于所有摆放实例。",
        },
        "components": [
            {"component_id": "tread_underlay", "role": "traversable_surface", "sort_mode": "world_underlay", "sort_baseline": WORLD_UNDERLAY_BASELINE, "mask": mask_paths["tread_underlay"], "texture": component_paths["tread_underlay"]},
            {"component_id": "handrail_occluder", "role": "foreground_occluder", "sort_mode": "asset_local_quantized_depth_field", "depth_field": depth_field_res_path, "depth_quantum": STAIRWAY_DEPTH_QUANTUM, "mask": mask_paths["handrail_occluder"], "texture": component_paths["handrail_occluder"]},
        ],
        "source_audit": {"source_release": "starhome_lz_ry", "source_asset": STAIRWAY_LOGICAL_PATH + ".ale", "source_texture_sha256": sha256(source_path)},
    }
    write_json(profile_dir / "depth_profile.json", profile)
    return profile, {
        "tread_underlay": tread,
        "handrail_occluder": rail,
        "handrail_depth_bands": [
            {"baseline_local_y": baseline, "mask": depth_bands[baseline]}
            for baseline in sorted(depth_bands)
        ],
    }


def paste_owner(
    owner: np.ndarray,
    local_mask: np.ndarray,
    top_left: tuple[int, int],
    owner_id: int,
) -> dict[int, int]:
    """Paint one semantic owner and report every lower owner it replaces.

    The returned ``owner_id -> pixel_count`` mapping is a coordinate-free
    overlap graph.  It proves which semantic component wins without embedding
    map-specific sample points in runtime code or tests.
    """
    destination_height, destination_width = owner.shape
    source_height, source_width = local_mask.shape
    x, y = top_left
    sx0, sy0 = max(0, -x), max(0, -y)
    sx1, sy1 = min(source_width, destination_width - x), min(source_height, destination_height - y)
    if sx0 >= sx1 or sy0 >= sy1:
        return {}
    clipped = local_mask[sy0:sy1, sx0:sx1]
    target = owner[y + sy0:y + sy1, x + sx0:x + sx1]
    replaced: dict[int, int] = {}
    previous = target[clipped]
    previous = previous[previous >= 0]
    if previous.size:
        previous_ids, counts = np.unique(previous, return_counts=True)
        replaced = {
            int(previous_id): int(count)
            for previous_id, count in zip(previous_ids, counts, strict=True)
        }
    target[clipped] = owner_id
    return replaced


def apply_depth_override(
    owner: np.ndarray,
    local_mask: np.ndarray,
    top_left: tuple[int, int],
    owner_id: int,
    owner_definitions: list[dict[str, Any]],
) -> tuple[np.ndarray, dict[int, int]]:
    """Promote one profile occluder only over owners with a lower baseline.

    Returns an asset-local mask of promoted pixels plus the replaced-owner
    counts.  The comparison is entirely semantic and reusable; map coordinates
    only clip the placed asset to the canvas.
    """
    destination_height, destination_width = owner.shape
    source_height, source_width = local_mask.shape
    x, y = top_left
    sx0, sy0 = max(0, -x), max(0, -y)
    sx1, sy1 = min(source_width, destination_width - x), min(source_height, destination_height - y)
    promoted_local = np.zeros_like(local_mask, dtype=bool)
    if sx0 >= sx1 or sy0 >= sy1:
        return promoted_local, {}
    clipped = local_mask[sy0:sy1, sx0:sx1]
    target = owner[y + sy0:y + sy1, x + sx0:x + sx1]
    current_baseline = int(owner_definitions[owner_id]["sort_baseline"])
    target_baselines = np.full(target.shape, current_baseline, dtype=np.int32)
    occupied = target >= 0
    if occupied.any():
        baseline_lookup = np.asarray(
            [int(value["sort_baseline"]) for value in owner_definitions],
            dtype=np.int32,
        )
        target_baselines[occupied] = baseline_lookup[target[occupied]]
    promoted = clipped & occupied & (target != owner_id) & (target_baselines < current_baseline)
    replaced: dict[int, int] = {}
    previous = target[promoted]
    if previous.size:
        previous_ids, counts = np.unique(previous, return_counts=True)
        replaced = {
            int(previous_id): int(count)
            for previous_id, count in zip(previous_ids, counts, strict=True)
        }
    target[promoted] = owner_id
    promoted_local[sy0:sy1, sx0:sx1] = promoted
    return promoted_local, replaced


def semantic_components_for(item: dict, source_alpha: np.ndarray, stairway_masks: dict[str, Any]) -> list[dict[str, Any]]:
    """Return reusable semantic components and baselines for one placement.

    Ordinary props use their engine anchor Y.  Traversable stair treads remain
    below actors, while the asset-local handrail depth field supplies its own
    ground-contact baselines.  No world coordinate or placement index affects
    the semantic choice.
    """
    if item["resolved_ale"] != STAIRWAY_LOGICAL_PATH:
        return [{
            "component_id": "default",
            "role": "scene_object",
            "sort_mode": "placement_anchor_y",
            "sort_baseline": int(item["anchor"][1]),
            "mask": source_alpha > 0,
        }]
    components: list[dict[str, Any]] = [{
        "component_id": "tread_underlay",
        "role": "traversable_surface",
        "sort_mode": "world_underlay",
        "sort_baseline": WORLD_UNDERLAY_BASELINE,
        "mask": stairway_masks["tread_underlay"],
    }]
    for band in stairway_masks["handrail_depth_bands"]:
        components.append({
            "component_id": "handrail_occluder",
            "role": "foreground_occluder",
            "sort_mode": "asset_local_quantized_depth_field",
            "baseline_local_y": int(band["baseline_local_y"]),
            "sort_baseline": int(item["top_left"][1]) + int(band["baseline_local_y"]),
            "mask": band["mask"],
        })
    return components


def pack_semantic_chunks(chunks: list[dict]) -> tuple[Image.Image, list[dict]]:
    """Shelf-pack alpha-bbox chunks into one atlas shared by all runtime nodes."""
    ordered = sorted(chunks, key=lambda item: (-item["pixels"].shape[0], -item["pixels"].shape[1], item["sort_baseline"], item["region"][1], item["region"][0]))
    x = y = shelf_height = 0
    for item in ordered:
        height, width = item["pixels"].shape[:2]
        if width > SEMANTIC_ATLAS_WIDTH:
            raise RuntimeError(f"Semantic chunk width {width} exceeds atlas width")
        if x and x + width > SEMANTIC_ATLAS_WIDTH:
            x = 0
            y += shelf_height + SEMANTIC_ATLAS_PADDING
            shelf_height = 0
        item["atlas_region"] = [x, y, width, height]
        x += width + SEMANTIC_ATLAS_PADDING
        shelf_height = max(shelf_height, height)
    atlas_height = y + shelf_height
    atlas_pixels = np.zeros((atlas_height, SEMANTIC_ATLAS_WIDTH, 4), dtype=np.uint8)
    for item in ordered:
        atlas_x, atlas_y, width, height = item["atlas_region"]
        atlas_pixels[atlas_y:atlas_y + height, atlas_x:atlas_x + width] = item["pixels"]
    return Image.fromarray(atlas_pixels, mode="RGBA"), ordered


def build_semantic_scene_layers(
    placements: list[dict],
    props_dir: Path,
    background_path: Path,
    stairway_masks: dict[str, Any],
) -> tuple[list[dict], list[int], str, str, list[dict], list[dict], dict[str, Any]]:
    """Build final-visible semantic chunks from engine-style baseline order.

    FCC order first reconstructs the source-faithful structural scene.  Profile
    foreground components then replace only overlapping owners whose baseline
    is shallower.  Final-owner chunks use the same baselines as dynamic actors,
    while unrelated static objects retain the client construction order.

    Returns semantic layers, atlas size, composite hash, scene hash, owner audit,
    and the generated overlap graph.
    """
    with Image.open(background_path) as source_background:
        background = source_background.convert("RGBA")
        canvas_size = background.size
    scene_color = Image.new("RGBA", canvas_size, (0, 0, 0, 0))
    owner = np.full((canvas_size[1], canvas_size[0]), -1, dtype=np.int32)
    owner_definitions: list[dict[str, Any]] = []

    for item in placements:
        if not item["render_enabled"] or item.get("status") != "ok":
            continue
        business_name = BUSINESS_NAMES[item["resolved_ale"]]
        with Image.open(props_dir / f"{business_name}.png") as source_file:
            source_image = source_file.convert("RGBA")
        top_left = (int(item["top_left"][0]), int(item["top_left"][1]))
        scene_color.alpha_composite(source_image, top_left)
        source_pixels = np.asarray(source_image, dtype=np.uint8)
        source_alpha = np.asarray(source_image.getchannel("A"), dtype=np.uint8)
        for component_order, component in enumerate(semantic_components_for(item, source_alpha, stairway_masks)):
            mask = component["mask"]
            owner_id = len(owner_definitions)
            owner_definitions.append({
                "owner_id": owner_id,
                "source_index": int(item["source_index"]),
                "asset_id": f"maps/yian_harbor/hall_floor_1/props/{business_name}",
                "component_order": component_order,
                "component_id": component["component_id"],
                "role": component["role"],
                "sort_mode": component["sort_mode"],
                "sort_baseline": component["sort_baseline"],
                "baseline_local_y": component.get("baseline_local_y"),
                "_mask": mask,
                "_pixels": source_pixels,
                "_top_left": top_left,
            })
            paste_owner(owner, mask, top_left, owner_id)

    overlap_graph: list[dict[str, Any]] = []
    source_order_scene = scene_color.copy()
    source_order_owner = owner.copy()
    foreground_definitions = sorted(
        (
            definition
            for definition in owner_definitions
            if definition["role"] == "foreground_occluder"
        ),
        key=lambda value: (
            int(value["sort_baseline"]),
            int(value["source_index"]),
            int(value["component_order"]),
        ),
    )
    for definition in foreground_definitions:
        promoted_mask, replaced = apply_depth_override(
            owner,
            definition["_mask"],
            definition["_top_left"],
            int(definition["owner_id"]),
            owner_definitions,
        )
        if not promoted_mask.any():
            continue
        component_pixels = np.zeros_like(definition["_pixels"])
        component_pixels[promoted_mask] = definition["_pixels"][promoted_mask]
        scene_color.alpha_composite(
            Image.fromarray(component_pixels, mode="RGBA"), definition["_top_left"]
        )
        for lower_owner_id, pixel_count in replaced.items():
            overlap_graph.append({
                "below_owner_id": lower_owner_id,
                "above_owner_id": int(definition["owner_id"]),
                "pixel_count": pixel_count,
                "rule": "foreground_over_shallower_owner",
            })

    scene_pixels = np.asarray(scene_color, dtype=np.uint8)
    source_order_pixels = np.asarray(source_order_scene, dtype=np.uint8)
    owner[scene_pixels[:, :, 3] == 0] = -1
    profile_override_pixels = owner != source_order_owner
    changed_pixels = np.any(scene_pixels != source_order_pixels, axis=2)
    changed_outside_profile = changed_pixels & ~profile_override_pixels
    if changed_outside_profile.any():
        raise RuntimeError("Profile depth correction changed unrelated source-order pixels")
    owners_by_baseline: dict[int, list[dict]] = defaultdict(list)
    for definition in owner_definitions:
        owners_by_baseline[int(definition["sort_baseline"])].append(definition)

    obsolete_layer_dir = DESTINATION / "semantic_layers"
    if obsolete_layer_dir.exists():
        shutil.rmtree(obsolete_layer_dir)
    chunks: list[dict] = []
    reconstructed_pixels = np.zeros_like(scene_pixels)
    owner_lookup = {int(item["owner_id"]): item for item in owner_definitions}
    for baseline in sorted(owners_by_baseline):
        definitions = owners_by_baseline[baseline]
        owner_ids = np.array([item["owner_id"] for item in definitions], dtype=np.int32)
        mask = np.isin(owner, owner_ids)
        if not mask.any():
            continue
        for tile_y in range(0, canvas_size[1], SEMANTIC_CHUNK_SIZE):
            for tile_x in range(0, canvas_size[0], SEMANTIC_CHUNK_SIZE):
                tile_mask = mask[tile_y:min(tile_y + SEMANTIC_CHUNK_SIZE, canvas_size[1]), tile_x:min(tile_x + SEMANTIC_CHUNK_SIZE, canvas_size[0])]
                if not tile_mask.any():
                    continue
                local_ys, local_xs = np.nonzero(tile_mask)
                x0, x1 = tile_x + int(local_xs.min()), tile_x + int(local_xs.max()) + 1
                y0, y1 = tile_y + int(local_ys.min()), tile_y + int(local_ys.max()) + 1
                crop_mask = mask[y0:y1, x0:x1]
                crop_pixels = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.uint8)
                source_crop = scene_pixels[y0:y1, x0:x1]
                crop_pixels[crop_mask] = source_crop[crop_mask]
                reconstructed_pixels[y0:y1, x0:x1][crop_mask] = source_crop[crop_mask]
                visible_ids = [int(value) for value in np.unique(owner[y0:y1, x0:x1][crop_mask])]
                chunks.append({
                    "pixels": crop_pixels,
                    "region": [x0, y0, x1 - x0, y1 - y0],
                    "sort_baseline": baseline,
                    "owners": [owner_lookup[value] for value in visible_ids],
                })

    atlas, packed_chunks = pack_semantic_chunks(chunks)
    atlas_path = DESTINATION / "semantic_layer_atlas.png"
    atlas.save(atlas_path, compress_level=3)
    semantic_layers: list[dict] = []
    for layer_index, item in enumerate(sorted(packed_chunks, key=lambda value: (value["sort_baseline"], value["region"][1], value["region"][0]))):
        region = item["region"]
        semantic_layers.append({
            "layer_id": f"semantic_scene_{layer_index:03d}",
            "texture": "res://assets/maps/yian_harbor/hall_floor_1/semantic_layer_atlas.png",
            "atlas_region": item["atlas_region"],
            "pixel_offset": region[:2],
            "size": region[2:],
            "region": region,
            "sort_baseline": item["sort_baseline"],
            "owners": [{"owner_id": owner_item["owner_id"], "source_index": owner_item["source_index"], "asset_id": owner_item["asset_id"], "component_id": owner_item["component_id"], "role": owner_item["role"]} for owner_item in item["owners"]],
        })

    reconstructed = Image.fromarray(reconstructed_pixels, mode="RGBA")
    if ImageChops.difference(reconstructed, scene_color).getbbox() is not None:
        raise RuntimeError("Semantic owner layers do not reconstruct scene_color exactly")
    composite = background.copy()
    composite.alpha_composite(scene_color)
    source_order_composite = background.copy()
    source_order_composite.alpha_composite(source_order_scene)
    reconstructed_composite = background.copy()
    reconstructed_composite.alpha_composite(reconstructed)
    if ImageChops.difference(reconstructed_composite, composite).getbbox() is not None:
        raise RuntimeError("Semantic layer composite differs from the FCC-order static composite")
    composite.save(DESTINATION / "static_composite.png", compress_level=3)
    source_order_composite.save(DESTINATION / "source_order_reference.png", compress_level=3)
    scene_color.save(DESTINATION / "scene_color.png", compress_level=3)
    Image.fromarray(profile_override_pixels.astype(np.uint8) * 255, mode="L").save(
        DESTINATION / "profile_override_mask.png", compress_level=3
    )
    owner_audit = []
    for definition in owner_definitions:
        owner_audit.append({
            key: value
            for key, value in definition.items()
            if not key.startswith("_")
        } | {
            "final_visible_pixel_count": int(np.count_nonzero(owner == definition["owner_id"]))
        })
    return (
        semantic_layers,
        list(atlas.size),
        hashlib.sha256(composite.tobytes()).hexdigest(),
        hashlib.sha256(scene_color.tobytes()).hexdigest(),
        owner_audit,
        overlap_graph,
        {
            "source_order_reference_pixel_sha256": hashlib.sha256(source_order_composite.tobytes()).hexdigest(),
            "profile_override_pixel_count": int(np.count_nonzero(profile_override_pixels)),
            "profile_changed_pixel_count": int(np.count_nonzero(changed_pixels)),
            "non_profile_changed_pixel_count": int(np.count_nonzero(changed_outside_profile)),
        },
    )


def main() -> int:
    """Regenerate the Glory hall presentation, navigation audit, and manifest."""
    if not SOURCE_MAP.is_dir() or not ALE_ROOT.is_dir() or not SOURCE_FCC.is_file() or not TRANSPORT_CLASS_SOURCE.is_file():
        raise SystemExit("Glory map, FCC source, transport class, or ALE source root is missing")
    scene = read_json(SOURCE_MAP / "scene_objects.json")
    metadata = read_json(SOURCE_MAP / "map_metadata.json")
    transitions = read_json(SOURCE_MAP / "transitions.json")
    placements = merge_source_placements(scene, SOURCE_FCC)
    resolved_paths = {item["resolved_ale"] for item in placements if item.get("status") == "ok"}
    unmapped = sorted(resolved_paths - BUSINESS_NAMES.keys())
    if unmapped:
        raise SystemExit("Missing business names: " + ", ".join(unmapped))

    props_dir = DESTINATION / "props"
    props_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(SOURCE_MAP / "background.png", DESTINATION / "floor.png")
    shutil.copy2(SOURCE_MAP / "minimap.jpg", DESTINATION / "minimap.jpg")
    shutil.copy2(SOURCE_MAP / "navigation_grid.bin", DESTINATION / "navigation_grid.bin")
    asset_sources = {}
    for logical_path in sorted(resolved_paths):
        business_name = BUSINESS_NAMES[logical_path]
        asset_sources[business_name] = export_first_frame(logical_path, props_dir / f"{business_name}.png")

    exit_transition = next(
        (
            transition
            for transition in transitions["enabled"]
            if transition["destination_map_code"].lower() == "city1svr"
            and [int(value) for value in transition["icon_anchor"]] == [408, 348]
        ),
        None,
    )
    exit_placement = next(
        (
            item
            for item in placements
            if item.get("status") == "ok"
            and item.get("handler") == "transport"
            and item.get("resolved_ale") == EXIT_TRANSITION_LOGICAL_PATH
            and [int(value) for value in item["anchor"]] == [408, 348]
        ),
        None,
    )
    if exit_transition is None or exit_placement is None:
        raise RuntimeError("Enabled RoomSvr1 -> City1Svr transport evidence is incomplete")
    transition_animation = export_transition_animation(
        EXIT_TRANSITION_LOGICAL_PATH,
        exit_transition,
        exit_placement,
    )
    runtime_transitions = []
    for transition in transitions["enabled"]:
        runtime_transition = dict(transition)
        if transition is exit_transition:
            runtime_transition["transition_id"] = EXIT_TRANSITION_ID
            runtime_transition["presentation"] = transition_animation["presentation"]
        runtime_transitions.append(runtime_transition)

    stairway_profile, stairway_masks = build_stairway_depth_profile(props_dir)
    semantic_layers, semantic_atlas_size, composite_pixel_sha256, scene_pixel_sha256, owner_audit, overlap_graph, presentation_audit = build_semantic_scene_layers(placements, props_dir, DESTINATION / "floor.png", stairway_masks)

    props, missing_dependencies, source_placements = [], [], []
    for item in placements:
        source_placements.append({
            "source_index": int(item["source_index"]), "placement_kind": item["kind"],
            "source_resource": item["resource"], "anchor": item["anchor"],
            "comment_prefix": item["comment_prefix"], "comment_state": item["comment_state"],
            "render_enabled": bool(item["render_enabled"]), "handler": item["handler"],
            "numeric_args": item["numeric_args"], "payload": item["payload"],
            "payload_raw_hex": item["payload_raw_hex"],
            "numeric_arg_1": item["numeric_args"][0] if item["numeric_args"] else None,
            "numeric_arg_2": item["numeric_args"][1] if item["numeric_args"] else None,
            "raw_arguments": item["raw_arguments"], "resolution": item.get("resolution", "missing"),
            "status": item.get("status", "missing"),
        })
        if item.get("status") != "ok":
            if item["render_enabled"]:
                missing_dependencies.append({"source_resource": item["resource"], "kind": item["kind"], "anchor": item["anchor"], "reason": item.get("resolution", "missing")})
            continue
        logical_path = item["resolved_ale"]
        business_name = BUSINESS_NAMES[logical_path]
        props.append({
            "asset_id": f"maps/yian_harbor/hall_floor_1/props/{business_name}",
            "texture": f"res://assets/maps/yian_harbor/hall_floor_1/props/{business_name}.png",
            "anchor": item["anchor"], "offset": item["origin"],
            "sort_baseline": int(item["anchor"][1]), "source_order": int(item["source_index"]),
            "placement_kind": item["kind"], "render_enabled": bool(item["render_enabled"]),
            "comment_state": item["comment_state"],
            "add_img_ex": {"handler": item["handler"], "numeric_arg_1": item["numeric_args"][0], "numeric_arg_2": item["numeric_args"][1], "numeric_args": item["numeric_args"], "payload": item["payload"], "payload_raw_hex": item["payload_raw_hex"]} if item["kind"] == "AddImgEx" else None,
            "depth_profile": "res://assets/maps/yian_harbor/hall_floor_1/depth_profiles/industrial_stairway/depth_profile.json" if logical_path == STAIRWAY_LOGICAL_PATH else None,
            "source_audit": {"source_logical_path": item["resource"], "resolved_logical_path": logical_path + ".ale"},
        })

    disabled_count = sum(not item["render_enabled"] for item in placements)
    manifest = {
        "schema_version": 3, "map_id": "yian_harbor_hall_floor_1", "display_name": "易安港基地大厅一层",
        "source_audit": {
            "source_release": "starhome_lz_ry", "source_map_code": metadata["map_code"],
            "source_map_name": metadata["map_name"], "source_output": metadata["output"],
            "source_branches": metadata["source_branches"], "source_script_sha256": metadata["script_sha256"],
            "expanded_fcc": str(SOURCE_FCC.relative_to(OUTPUTS_ROOT)).replace("\\", "/"), "expanded_fcc_sha256": sha256(SOURCE_FCC),
        },
        "composition": {
            "size": metadata["map_pixel_size"], "floor": "res://assets/maps/yian_harbor/hall_floor_1/floor.png",
            "render_strategy": "semantic_owner_layers", "scene_color": "res://assets/maps/yian_harbor/hall_floor_1/scene_color.png",
            "static_composite": "res://assets/maps/yian_harbor/hall_floor_1/static_composite.png", "semantic_layers": semantic_layers,
            "source_order_reference": "res://assets/maps/yian_harbor/hall_floor_1/source_order_reference.png",
            "profile_override_mask": "res://assets/maps/yian_harbor/hall_floor_1/profile_override_mask.png",
            "semantic_atlas": "res://assets/maps/yian_harbor/hall_floor_1/semantic_layer_atlas.png", "semantic_atlas_size": semantic_atlas_size,
            "semantic_chunk_size": SEMANTIC_CHUNK_SIZE,
            "reference_pixel_sha256": composite_pixel_sha256, "scene_pixel_sha256": scene_pixel_sha256,
            **presentation_audit,
            "semantic_sort_rule": "fcc_source_order_with_profile_depth_overrides",
            "owner_audit": owner_audit, "semantic_overlap_graph": overlap_graph,
            "depth_profiles": [stairway_profile["profile_id"]],
            "props": props, "source_placements": source_placements, "disabled_placement_count": disabled_count,
        },
        "navigation": {"grid_size": metadata["engine_grid_size"], "cell_size": [48, 12], "data_path": "res://assets/maps/yian_harbor/hall_floor_1/navigation_grid.bin", "source_sha256": sha256(SOURCE_MAP / "navigation_grid.bin")},
        "minimap": "res://assets/maps/yian_harbor/hall_floor_1/minimap.jpg", "transitions": runtime_transitions,
        "transition_visuals": {EXIT_TRANSITION_ID: transition_animation},
        "missing_dependencies": missing_dependencies, "asset_sources": asset_sources,
    }
    write_json(DESTINATION / "map_manifest.json", manifest, compact=True)
    write_json(DESTINATION / "navigation_summary.json", {
        "map_id": manifest["map_id"], "source_release": "starhome_lz_ry", "grid": metadata["engine_grid_size"],
        "cell_size": [48, 12], "runtime_sha256": manifest["navigation"]["source_sha256"],
        "walkable_rule": "(flags & 0x80) != 0", "passable": metadata["navigation"]["passable"], "blocked": metadata["navigation"]["blocked"],
    })
    for obsolete in (DESTINATION / "scene_depth_layer.png", DESTINATION / "scene_depth_layer.png.import"):
        obsolete.unlink(missing_ok=True)
    print(json.dumps({
        "map": manifest["map_id"], "source_placements": len(placements), "disabled_placements": disabled_count,
        "runtime_props": sum(item["render_enabled"] for item in props), "semantic_layers": len(semantic_layers),
        "missing_enabled_dependencies": len(missing_dependencies), "world_size": metadata["map_pixel_size"],
    }, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
