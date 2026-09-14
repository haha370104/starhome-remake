#!/usr/bin/env python3
"""Read-only audit for the approved Free-edition HUD asset contract."""

from __future__ import annotations

import json
import struct
from pathlib import Path
from typing import Any, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[3]
RUNTIME_MANIFEST = PROJECT_ROOT / "data" / "ui" / "free_hud_assets.json"
SOURCE_AUDIT = (
    PROJECT_ROOT / "assets" / "ui" / "source_audit" / "free_hud_sources.json"
)


def read_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def asset_path(value: str) -> Path:
    assert value.startswith("res://"), f"not a Godot asset path: {value}"
    path = PROJECT_ROOT / value.removeprefix("res://")
    assert path.is_file(), f"missing imported asset: {path}"
    return path


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as handle:
        assert handle.read(8) == b"\x89PNG\r\n\x1a\n", f"not a PNG: {path}"
        length = struct.unpack(">I", handle.read(4))[0]
        assert handle.read(4) == b"IHDR" and length == 13
        width, height = struct.unpack(">II", handle.read(8))
    return width, height


def assert_single(node: dict[str, Any], size: tuple[int, int]) -> None:
    assert node["available"] is True
    assert tuple(node["size"]) == size
    assert tuple(node["origin"]) == (0, 0)
    assert png_size(asset_path(node["path"])) == size


def assert_states(node: dict[str, Any], names: Iterable[str]) -> None:
    names = list(names)
    assert node["available"] is True
    assert list(node["states"]) == names
    assert list(node["state_sizes"]) == names
    assert list(node["state_origins"]) == names
    for name in names:
        path = asset_path(node["states"][name])
        assert png_size(path) == tuple(node["state_sizes"][name])
        assert len(node["state_origins"][name]) == 2


def main() -> int:
    runtime = read_json(RUNTIME_MANIFEST)
    sources = read_json(SOURCE_AUDIT)
    assert runtime["schema_version"] == 1
    assert runtime["asset_release"] == "free_hud"
    assert runtime["source_release"] == "starhome_lz_fr"
    assert runtime["unavailable"] == []

    serialized = RUNTIME_MANIFEST.read_text(encoding="utf-8")
    for forbidden in ("pic/", "pic2/", ".ale", "CHN_", "mainctrlpad"):
        assert forbidden not in serialized, f"legacy source name leaked: {forbidden}"
    assert ".jpg" not in serialized.lower(), "a minimap content JPG leaked into HUD"

    top = runtime["top_menu"]
    assert_single(top["background"], (327, 54))
    assert top["expanded_size"] == [330, 54]
    assert top["collapsed_size"] == [12, 26]
    for control in ("collapse_button", "expand_button"):
        assert_states(top[control], ["normal", "hover", "pressed"])
    assert set(top["buttons"]) == {
        "system_messages",
        "help",
        "party",
        "return_base",
        "self_repair",
    }
    for button in top["buttons"].values():
        assert_states(button, ["normal", "hover", "pressed"])

    bottom = runtime["bottom_main"]
    assert_single(bottom["background"], (1024, 29))
    assert bottom["background"]["edge_color_method"] == "mean_rgba_of_vertical_edge"
    for value in bottom["background"]["edge_colors"].values():
        assert len(value) == 9 and value.startswith("#")
    energy = bottom["reserve_energy"]
    assert energy["position"] == [125, 3]
    assert energy["crop_width"] == 323 and energy["crop_height"] == 3
    assert list(energy["frames"]) == ["steady", "flash"]
    assert list(energy["frame_sizes"]) == ["steady", "flash"]
    assert list(energy["frame_origins"]) == ["steady", "flash"]
    for name in energy["frames"]:
        assert png_size(asset_path(energy["frames"][name])) == (323, 3)
    assert set(bottom["menu_buttons"]) == {
        "character",
        "inventory",
        "vehicle_equipment",
        "friends",
        "scene_players",
        "missions",
        "premium_shop",
        "system",
    }
    for button in bottom["menu_buttons"].values():
        assert_states(button, ["normal", "hover", "pressed"])
    assert_states(bottom["weapons"]["energy_cannon"], ["normal", "selected"])
    primary_modes = bottom["weapons"]["primary_modes"]
    assert set(primary_modes) == {"mining_arm", "repair_arm"}
    for device_kind, mode in primary_modes.items():
        assert_states(mode, ["normal", "selected"])
        for name, path in mode["states"].items():
            assert png_size(asset_path(path)) == (29, 22)
            assert f"/{device_kind}/{name}.png" in path
    tactical = bottom["weapons"]["tactical"]
    assert tactical["position"] == [206, 8]
    assert set(tactical["modes"]) == {
        "rocket_launcher",
        "missile",
        "stealth",
        "radar",
    }
    for mode in tactical["modes"].values():
        assert_states(mode, ["normal", "selected"])

    shortcut = runtime["general_shortcut"]
    assert_single(shortcut["background"], (415, 40))
    assert_single(shortcut["page_up"], (10, 9))
    assert_single(shortcut["page_down"], (10, 9))
    assert_states(shortcut["collapse_button"], ["normal", "hover", "pressed"])
    assert_states(shortcut["expand_button"], ["normal", "hover", "pressed"])

    minimap = runtime["minimap_chrome"]
    assert_single(minimap["control_background"], (121, 23))
    assert minimap["small_size"] == [125, 165]
    assert minimap["small_viewport"] == {"position": [1, 1], "size": [120, 120]}
    assert minimap["map_content_source"] == "current_glory_map"
    for node in minimap["toggle_size"].values():
        if isinstance(node, dict):
            assert_states(node, ["normal", "pressed"])
    for node in minimap["toggle_visibility"].values():
        if isinstance(node, dict):
            assert_states(node, ["normal", "pressed"])

    assert sources["source_release"] == "starhome_lz_fr"
    assert sources["missing_assets"] == []
    assert len(sources["sources"]) == 35
    expected_source_paths = {
        "pic2/topmenu/topmenuback_0.ale",
        "pic2/topmenu/btn_systemmsg.ale",
        "pic2/topmenu/btn_help.ale",
        "pic2/topmenu/btn_looktem.ale",
        "pic2/topmenu/btn_backhome.ale",
        "pic2/topmenu/btn_repaireself.ale",
        "pic2/topmenu/btn_topmenuso.ale",
        "pic2/topmenu/btn_topmenufa.ale",
        "pic2/ctrlpad/mainctrlpad_1024.png",
        "pic2/ctrlpad/energybar.ale",
        "pic2/ctrlpad/btn_humanwnd.ale",
        "pic2/ctrlpad/btn_humanbag.ale",
        "pic2/ctrlpad/btn_humanequip.ale",
        "pic2/ctrlpad/btn_playerfriend.ale",
        "pic2/ctrlpad/btn_look.ale",
        "pic2/ctrlpad/btn_playertask.ale",
        "pic2/ctrlpad/btn_spacemap.ale",
        "pic2/ctrlpad/btn_system.ale",
        "pic/equipface/tank_gun.ale",
        "pic/equipface/tank_collent.ale",
        "pic/equipface/tank_repair.ale",
        "pic/equipface/firegun.ale",
        "pic/equipface/missile.ale",
        "pic/equipface/tank_hermit.ale",
        "pic/equipface/tank_radar.ale",
        "pic/shortcutbar/generalbar.ale",
        "pic/shortcutbar/pageupbtn.ale",
        "pic/shortcutbar/pagedownbtn.ale",
        "pic/shortcutbar/shortcutbtn.ale",
        "pic/shortcutbar/shortcutbtn1.ale",
        "pic2/smap/ditu.ale",
        "pic/interface/chn_2005_06_28_19_00_09_1031.ale",
        "pic/interface/chn_2005_06_28_19_00_15_1032.ale",
        "pic/interface/chn_2005_06_28_19_00_21_1033.ale",
        "pic/interface/chn_2005_06_28_19_00_27_1034.ale",
    }
    actual_source_paths = {
        source["source_logical_path"].lower()
        for source in sources["sources"].values()
    }
    assert actual_source_paths == expected_source_paths
    for source in sources["sources"].values():
        assert source["source_release"] == "starhome_lz_fr"
        logical = source["source_logical_path"].lower()
        assert logical.startswith(("pic/", "pic2/"))
        assert logical.endswith((".ale", ".png"))
        digest = source.get("source_ale_sha256", source.get("source_sha256", ""))
        assert len(digest) == 64

    print("Free HUD asset audit passed: 35 allowlisted sources, no minimap JPG")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
