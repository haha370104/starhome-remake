#!/usr/bin/env python3
"""Audit the promoted Glory hall-to-city transport presentation and evidence."""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
MAP_DEFINITION = PROJECT_ROOT / "data/maps/yian_harbor_hall_floor_1.json"
MAP_MANIFEST = PROJECT_ROOT / "assets/maps/yian_harbor/hall_floor_1/map_manifest.json"
TRANSITION_DIR = PROJECT_ROOT / "assets/maps/yian_harbor/hall_floor_1/transitions/exit_to_city"
IMPORT_METADATA = TRANSITION_DIR / "import_metadata.json"
MARKER_CATALOG = PROJECT_ROOT / "data/presentation/map_transition_marker_catalog.json"
SHARED_TRANSITION_DIR = PROJECT_ROOT / "assets/maps/shared/directional_transitions/south_west"
SHARED_IMPORT_METADATA = SHARED_TRANSITION_DIR / "import_metadata.json"
SOURCE_FCC = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed/ftc_resources/expanded/NFT_BT/map/RoomSvr1/roomsvr1.fcc.cab"
TRANSPORT_CLASS = OUTPUTS_ROOT / "starhome_lz_ry_full_parsed/ftc_resources/expanded/transport/transport.fcc.cab"
EXPECTED_SHARED_RESOURCE = "res://assets/maps/shared/directional_transitions/south_west/animation_frames.tres"


def read_json(path: Path) -> dict:
    """Read one UTF-8 JSON object.

    Args:
        path: JSON file to parse.

    Returns:
        Parsed top-level dictionary.
    """
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    """Return a lowercase SHA-256 digest for one evidence file.

    Args:
        path: File whose content must be hashed.

    Returns:
        Hexadecimal SHA-256 digest.
    """
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    """Validate topology, Glory provenance, animation geometry and runtime paths.

    Returns:
        Zero when all invariants hold, otherwise one after printing failures.
    """
    errors: list[str] = []
    required = (
        MAP_DEFINITION,
        MAP_MANIFEST,
        IMPORT_METADATA,
        MARKER_CATALOG,
        SHARED_IMPORT_METADATA,
        TRANSITION_DIR / "frames.png",
        TRANSITION_DIR / "animation_frames.tres",
        SHARED_TRANSITION_DIR / "frames.png",
        SHARED_TRANSITION_DIR / "animation_frames.tres",
        SOURCE_FCC,
        TRANSPORT_CLASS,
    )
    for path in required:
        if not path.is_file():
            errors.append(f"missing required file: {path}")
    if errors:
        for error in errors:
            print(error)
        return 1

    map_definition = read_json(MAP_DEFINITION)
    manifest = read_json(MAP_MANIFEST)
    metadata = read_json(IMPORT_METADATA)
    marker_catalog = read_json(MARKER_CATALOG)
    shared_metadata = read_json(SHARED_IMPORT_METADATA)
    definition_transition = next(
        (item for item in map_definition.get("transitions", []) if item.get("transition_id") == "exit_to_city"),
        None,
    )
    manifest_transition = next(
        (item for item in manifest.get("transitions", []) if item.get("transition_id") == "exit_to_city"),
        None,
    )
    if definition_transition is None or manifest_transition is None:
        errors.append("exit_to_city is missing from map definition or scene manifest")
    else:
        if definition_transition.get("source_anchor") != [408, 348]:
            errors.append("map definition source anchor differs from Glory FCC")
        if definition_transition.get("approach_point") != [480, 370]:
            errors.append("map definition approach point differs from Glory payload")
        destination = definition_transition.get("destination", {})
        if destination.get("map_id") != "yian_harbor_city" or destination.get("entry_number") != 0:
            errors.append("map definition destination is not City1Svr entry 0")
        expected_definition_presentation = {
            "kind": "directional_transition",
            "orientation": "south_west",
            "activation": "enabled_transition",
        }
        if definition_transition.get("presentation") != expected_definition_presentation:
            errors.append("map definition no longer delegates the hall marker to the shared south-west component")
        if manifest_transition.get("presentation") != metadata.get("presentation", {}):
            errors.append("scene manifest presentation drifted from import metadata")

    presentation = metadata.get("presentation", {})
    if presentation.get("resource") != "res://assets/maps/yian_harbor/hall_floor_1/transitions/exit_to_city/animation_frames.tres":
        errors.append("historical hall transport evidence path drifted")
    if any(token in str(presentation.get("resource", "")).lower() for token in ("/pic/", "/pic2/", ".ale")):
        errors.append("runtime resource path leaks a legacy directory or ALE name")
    expected_presentation_fields = {
        "kind": "animated_sprite",
        "animation": "active",
        "anchor": [408, 348],
        "offset": [0, 0],
        "centered": False,
        "interaction_rect": [0, 0, 78, 41],
        "interaction_space": "asset_local_fixed_bounds",
        "sort_baseline": 348,
        "frame_count": 9,
        "frame_duration_ms": 100,
        "loop": True,
        "activation": "enabled_transition",
    }
    for field, expected in expected_presentation_fields.items():
        if presentation.get(field) != expected:
            errors.append(f"presentation {field} expected {expected!r}, got {presentation.get(field)!r}")

    shared_presentation = marker_catalog.get("markers", {}).get("south_west", {})
    if shared_presentation.get("resource") != EXPECTED_SHARED_RESOURCE:
        errors.append("hall marker does not resolve to the shared as4 directional animation")
    if shared_metadata.get("source_logical_path") != "pic3/interface/sportimg/as4.ale":
        errors.append("shared south-west marker no longer proves the Glory sportimg/as4 source")
    if shared_metadata.get("frame_count") != 9 or shared_metadata.get("legacy_playdelay_ms") != 100:
        errors.append("shared south-west marker frame timing drifted from Glory evidence")

    source_audit = metadata.get("source_audit", {})
    if source_audit.get("source_release") != "starhome_lz_ry":
        errors.append("transport does not declare Glory provenance")
    if source_audit.get("source_line") != 107 or source_audit.get("source_comment_state") != "line_comment":
        errors.append("FCC comment evidence does not identify RoomSvr1 line 107")
    if source_audit.get("promotion_reason") != "metadata_enabled":
        errors.append("dynamic transport was not promoted from enabled topology")
    if source_audit.get("destination_map_code") != "City1Svr" or source_audit.get("destination_entry_number") != 0:
        errors.append("source payload destination is not City1Svr entry 0")
    if source_audit.get("source_playdelay_ms") != 100:
        errors.append("transport playback delay is not the source-confirmed 100 ms")

    source_raw = OUTPUTS_ROOT / Path(str(source_audit.get("source_raw", "")))
    source_frames = OUTPUTS_ROOT / Path(str(source_audit.get("source_frames_metadata", "")))
    if not source_raw.is_file() or sha256(source_raw) != source_audit.get("source_raw_sha256"):
        errors.append("raw Glory transport ALE is missing or its digest drifted")
    if not source_frames.is_file() or sha256(source_frames) != source_audit.get("source_frames_metadata_sha256"):
        errors.append("parsed Glory frame metadata is missing or its digest drifted")
    if sha256(TRANSPORT_CLASS) != source_audit.get("source_transport_class_sha256"):
        errors.append("transport class source digest drifted")

    fcc_bytes = SOURCE_FCC.read_bytes()
    expected_call = re.compile(
        rb"//AddImgEx\('transport',\$\+'\.\./\.\./map/mapimg/house/CHN_2005_06_28_19_30_52_38/as4\.ale',408,348,0,0,'City1Svr [^']+ 480 370'\);"
    )
    if expected_call.search(fcc_bytes) is None:
        errors.append("exact commented RoomSvr1 transport call was not found")
    transport_source = TRANSPORT_CLASS.read_bytes()
    if b"class transport:img" not in transport_source or b"playdelay=100;" not in transport_source:
        errors.append("transport class no longer proves the 100 ms animation delay")

    frames_resource = (SHARED_TRANSITION_DIR / "animation_frames.tres").read_text(encoding="utf-8")
    if frames_resource.count('[sub_resource type="AtlasTexture"') != 9:
        errors.append("SpriteFrames does not expose all nine Glory frames")
    if '"name": &"active"' not in frames_resource or '"speed": 10.0' not in frames_resource:
        errors.append("SpriteFrames animation identity or speed is incorrect")
    with Image.open(SHARED_TRANSITION_DIR / "frames.png") as atlas:
        if atlas.size != (702, 41):
            errors.append(f"normalized transport atlas expected 702x41, got {atlas.size}")

    source_placements = manifest.get("composition", {}).get("source_placements", [])
    source_placement = next(
        (
            item
            for item in source_placements
            if item.get("handler") == "transport" and item.get("anchor") == [408, 348]
        ),
        None,
    )
    if source_placement is None:
        errors.append("manifest lost the original transport placement evidence")
    elif source_placement.get("render_enabled") is not False or source_placement.get("comment_state") != "line_comment":
        errors.append("commented transport was incorrectly converted into a static placement")
    owners = manifest.get("composition", {}).get("owner_audit", [])
    if any(item.get("asset_id", "").endswith("/exit_to_city") for item in owners):
        errors.append("animated transport was frozen into semantic static owner layers")

    if errors:
        for error in errors:
            print(error)
        return 1
    print(
        "Hall exit transition audit passed: RoomSvr1 (408,348) -> "
        "City1Svr entry 0 via shared sportimg/as4, approach (480,370), 9 frames at 100 ms"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
