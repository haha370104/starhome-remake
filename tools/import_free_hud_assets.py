#!/usr/bin/env python3
"""Import the approved Free-edition HUD chrome into business-named paths.

Only assets explicitly covered by docs/free_hud_rendering.md are imported.
Legacy paths are kept in the source-audit file and never leak into the runtime
manifest.  The current-map minimap JPG is intentionally out of scope.
"""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path
from typing import Any, Iterable

from PIL import Image


PROJECT_ROOT = Path(__file__).resolve().parents[1]
OUTPUTS_ROOT = PROJECT_ROOT.parent
PARSED_ROOT = OUTPUTS_ROOT / "starhome_lz_fr_full_parsed" / "ale_sprites"
RAW_ROOT = OUTPUTS_ROOT / "starhome_lz_fr_full" / "raw"
DESTINATION_ROOT = PROJECT_ROOT / "assets" / "ui" / "free_hud"
RUNTIME_MANIFEST = PROJECT_ROOT / "data" / "ui" / "free_hud_assets.json"
SOURCE_AUDIT = (
    PROJECT_ROOT / "assets" / "ui" / "source_audit" / "free_hud_sources.json"
)


TOP_BUTTONS = {
    "system_messages": ("pic2/topmenu/btn_systemmsg", [18, 0]),
    "help": ("pic2/topmenu/btn_help", [56, 0]),
    "party": ("pic2/topmenu/btn_looktem", [94, 0]),
    "return_base": ("pic2/topmenu/btn_backhome", [133, 0]),
    "self_repair": ("pic2/topmenu/btn_repaireself", [172, 0]),
}

BOTTOM_MENU_BUTTONS = {
    "character": ("pic2/ctrlpad/btn_humanwnd", [519, 0]),
    "inventory": ("pic2/ctrlpad/btn_humanbag", [557, 0]),
    "vehicle_equipment": ("pic2/ctrlpad/btn_humanequip", [595, 0]),
    "friends": ("pic2/ctrlpad/btn_playerfriend", [633, 0]),
    "scene_players": ("pic2/ctrlpad/btn_look", [671, 0]),
    "missions": ("pic2/ctrlpad/btn_playertask", [709, 0]),
    "system": ("pic2/ctrlpad/btn_system", [747, 0]),
    "premium_shop": ("pic2/ctrlpad/shopping", [785, 0]),
}


def read_json(path: Path) -> dict[str, Any]:
    """Decode one UTF-8 JSON object from ``path``."""
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict[str, Any]) -> None:
    """Write ``value`` as stable, human-readable UTF-8 JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def sha256(path: Path) -> str:
    """Return the lowercase SHA-256 digest for one file."""
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def res_path(path: Path) -> str:
    """Convert a project-local filesystem path to a Godot ``res://`` path."""
    return "res://" + path.relative_to(PROJECT_ROOT).as_posix()


def average_edge_color(image: Image.Image, x: int) -> str:
    """Return the mean RGBA color for vertical column ``x`` as ``#RRGGBBAA``."""
    rgba = image.convert("RGBA")
    pixels = [rgba.getpixel((x, y)) for y in range(rgba.height)]
    averages = [round(sum(pixel[channel] for pixel in pixels) / len(pixels)) for channel in range(4)]
    return "#" + "".join(f"{value:02X}" for value in averages)


def available_single(frame: dict[str, Any]) -> dict[str, Any]:
    """Build the runtime contract for one exported frame."""
    return {
        "available": True,
        "path": frame["path"],
        "size": frame["size"],
        "origin": frame["origin"],
    }


def state_set(frames: list[dict[str, Any]], names: Iterable[str]) -> dict[str, Any]:
    """Map ordered exported ``frames`` onto named UI states with geometry."""
    names = list(names)
    if len(frames) != len(names):
        raise RuntimeError(f"expected {len(names)} states, source has {len(frames)}")
    return {
        "available": True,
        "states": {name: frame["path"] for name, frame in zip(names, frames)},
        "state_sizes": {name: frame["size"] for name, frame in zip(names, frames)},
        "state_origins": {
            name: frame["origin"] for name, frame in zip(names, frames)
        },
    }


class ImportSession:
    def __init__(self) -> None:
        """Create an empty provenance session for this deterministic import."""
        self.sources: dict[str, Any] = {}
        self.missing: list[dict[str, str]] = []

    def export_raw_png(
        self, business_id: str, logical_path: str, destination: Path
    ) -> dict[str, Any]:
        """Copy an approved source PNG and return its runtime geometry record."""
        source = RAW_ROOT / Path(logical_path)
        if not source.is_file():
            self.missing.append(
                {
                    "business_id": business_id,
                    "source_logical_path": logical_path,
                    "reason": "Free-edition raw PNG is missing",
                }
            )
            raise FileNotFoundError(source)
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
        with Image.open(destination) as image:
            width, height = image.size
            left = average_edge_color(image, 0)
            right = average_edge_color(image, width - 1)
        result = {
            "path": res_path(destination),
            "size": [width, height],
            "origin": [0, 0],
            "sha256": sha256(destination),
            "edge_colors": {"left": left, "right": right},
        }
        self.sources[business_id] = {
            "source_release": "starhome_lz_fr",
            "source_logical_path": logical_path,
            "source_sha256": sha256(source),
            "exported": result,
        }
        return result

    def export_ale_frames(
        self,
        business_id: str,
        logical_path_without_suffix: str,
        destination: Path,
        filenames: list[str],
    ) -> list[dict[str, Any]]:
        """Crop parsed ALE frames into named PNGs and record source provenance."""
        logical = Path(logical_path_without_suffix)
        parsed_dir = PARSED_ROOT / logical
        raw_ale = RAW_ROOT / logical.with_suffix(".ale")
        frames_path = parsed_dir / "frames.json"
        if not frames_path.is_file() or not raw_ale.is_file():
            self.missing.append(
                {
                    "business_id": business_id,
                    "source_logical_path": logical_path_without_suffix + ".ale",
                    "reason": "Free-edition ALE or parsed frames are missing",
                }
            )
            raise FileNotFoundError(frames_path if not frames_path.is_file() else raw_ale)

        metadata = read_json(frames_path)
        frames = metadata["frames"]
        if len(frames) != len(filenames):
            raise RuntimeError(
                f"{business_id}: expected {len(filenames)} frames, source has {len(frames)}"
            )
        destination.mkdir(parents=True, exist_ok=True)
        pages: dict[int, Image.Image] = {}
        exported: list[dict[str, Any]] = []
        try:
            for filename, frame in zip(filenames, frames):
                page_index = int(frame["page"])
                if page_index not in pages:
                    page_path = parsed_dir / metadata["pages"][page_index]
                    pages[page_index] = Image.open(page_path).convert("RGBA")
                width = int(frame["width"])
                height = int(frame["height"])
                x = int(frame["x"])
                y = int(frame["y"])
                output = destination / filename
                pages[page_index].crop((x, y, x + width, y + height)).save(
                    output, compress_level=6
                )
                exported.append(
                    {
                        "path": res_path(output),
                        "frame_index": int(frame["index"]),
                        "size": [width, height],
                        "origin": [int(frame["origin_x"]), int(frame["origin_y"])],
                        "sha256": sha256(output),
                    }
                )
        finally:
            for page in pages.values():
                page.close()

        self.sources[business_id] = {
            "source_release": "starhome_lz_fr",
            "source_logical_path": logical_path_without_suffix + ".ale",
            "source_ale_sha256": sha256(raw_ale),
            "source_frames_sha256": sha256(frames_path),
            "source_frame_count": len(frames),
            "exported_frames": exported,
        }
        return exported


def positioned(node: dict[str, Any], position: list[int]) -> dict[str, Any]:
    """Return a runtime asset node augmented with a 1024-design coordinate."""
    return {**node, "position": position}


def main() -> int:
    """Rebuild all allowlisted Free-edition HUD assets and both manifests."""
    if not PARSED_ROOT.is_dir() or not RAW_ROOT.is_dir():
        raise SystemExit("Free-edition raw or parsed resource root is missing")

    if DESTINATION_ROOT.exists():
        shutil.rmtree(DESTINATION_ROOT)
    session = ImportSession()

    top_background = session.export_ale_frames(
        "top_menu.background",
        "pic2/topmenu/topmenuback_0",
        DESTINATION_ROOT / "top_menu",
        ["background.png"],
    )[0]
    top_buttons: dict[str, Any] = {}
    for name, (source, position) in TOP_BUTTONS.items():
        frames = session.export_ale_frames(
            f"top_menu.buttons.{name}",
            source,
            DESTINATION_ROOT / "top_menu" / "buttons" / name,
            ["normal.png", "hover.png", "pressed.png"],
        )
        top_buttons[name] = positioned(
            state_set(frames, ["normal", "hover", "pressed"]), position
        )
    collapse_top = session.export_ale_frames(
        "top_menu.collapse",
        "pic2/topmenu/btn_topmenuso",
        DESTINATION_ROOT / "top_menu" / "collapse",
        ["normal.png", "hover.png", "pressed.png"],
    )
    expand_top = session.export_ale_frames(
        "top_menu.expand",
        "pic2/topmenu/btn_topmenufa",
        DESTINATION_ROOT / "top_menu" / "expand",
        ["normal.png", "hover.png", "pressed.png"],
    )

    bottom_background = session.export_raw_png(
        "bottom_main.background",
        "pic2/ctrlpad/mainctrlpad_1024.png",
        DESTINATION_ROOT / "bottom_main" / "background.png",
    )
    energy_frames = session.export_ale_frames(
        "bottom_main.reserve_energy",
        "pic2/ctrlpad/energybar",
        DESTINATION_ROOT / "bottom_main" / "reserve_energy",
        ["steady.png", "flash.png"],
    )

    bottom_buttons: dict[str, Any] = {}
    for name, (source, position) in BOTTOM_MENU_BUTTONS.items():
        frames = session.export_ale_frames(
            f"bottom_main.menu_buttons.{name}",
            source,
            DESTINATION_ROOT / "bottom_main" / "menu_buttons" / name,
            ["normal.png", "hover.png", "pressed.png"],
        )
        bottom_buttons[name] = positioned(
            state_set(frames, ["normal", "hover", "pressed"]), position
        )

    energy_cannon = session.export_ale_frames(
        "bottom_main.weapons.energy_cannon",
        "pic/equipface/tank_gun",
        DESTINATION_ROOT / "bottom_main" / "weapon_modes" / "energy_cannon",
        ["normal.png", "selected.png"],
    )
    tactical_modes: dict[str, Any] = {}
    for action_id, source_name in {
        "rocket_launcher": "firegun",
        "missile": "missile",
        "stealth": "tank_hermit",
        "radar": "tank_radar",
    }.items():
        frames = session.export_ale_frames(
            f"bottom_main.weapons.tactical.{action_id}",
            f"pic/equipface/{source_name}",
            DESTINATION_ROOT / "bottom_main" / "weapon_modes" / action_id,
            ["normal.png", "selected.png"],
        )
        tactical_modes[action_id] = state_set(frames, ["normal", "selected"])

    shortcut_background = session.export_ale_frames(
        "general_shortcut.background",
        "pic/shortcutbar/generalbar",
        DESTINATION_ROOT / "general_shortcut",
        ["background.png"],
    )[0]
    page_up = session.export_ale_frames(
        "general_shortcut.page_up",
        "pic/shortcutbar/pageupbtn",
        DESTINATION_ROOT / "general_shortcut" / "page_up",
        ["normal.png"],
    )[0]
    page_down = session.export_ale_frames(
        "general_shortcut.page_down",
        "pic/shortcutbar/pagedownbtn",
        DESTINATION_ROOT / "general_shortcut" / "page_down",
        ["normal.png"],
    )[0]
    shortcut_collapse = session.export_ale_frames(
        "general_shortcut.collapse",
        "pic/shortcutbar/shortcutbtn1",
        DESTINATION_ROOT / "general_shortcut" / "collapse",
        ["normal.png", "hover.png", "pressed.png"],
    )
    shortcut_expand = session.export_ale_frames(
        "general_shortcut.expand",
        "pic/shortcutbar/shortcutbtn",
        DESTINATION_ROOT / "general_shortcut" / "expand",
        ["normal.png", "hover.png", "pressed.png"],
    )

    minimap_background = session.export_ale_frames(
        "minimap_chrome.control_background",
        "pic2/smap/ditu",
        DESTINATION_ROOT / "minimap_chrome",
        ["control_background.png"],
    )[0]
    to_large = session.export_ale_frames(
        "minimap_chrome.toggle_size.to_large",
        "pic/interface/chn_2005_06_28_19_00_09_1031",
        DESTINATION_ROOT / "minimap_chrome" / "toggle_size" / "to_large",
        ["normal.png", "pressed.png"],
    )
    to_small = session.export_ale_frames(
        "minimap_chrome.toggle_size.to_small",
        "pic/interface/chn_2005_06_28_19_00_15_1032",
        DESTINATION_ROOT / "minimap_chrome" / "toggle_size" / "to_small",
        ["normal.png", "pressed.png"],
    )
    collapse_minimap = session.export_ale_frames(
        "minimap_chrome.toggle_visibility.collapse",
        "pic/interface/chn_2005_06_28_19_00_21_1033",
        DESTINATION_ROOT / "minimap_chrome" / "toggle_visibility" / "collapse",
        ["normal.png", "pressed.png"],
    )
    expand_minimap = session.export_ale_frames(
        "minimap_chrome.toggle_visibility.expand",
        "pic/interface/chn_2005_06_28_19_00_27_1034",
        DESTINATION_ROOT / "minimap_chrome" / "toggle_visibility" / "expand",
        ["normal.png", "pressed.png"],
    )

    runtime_manifest: dict[str, Any] = {
        "schema_version": 1,
        "asset_release": "free_hud",
        "source_release": "starhome_lz_fr",
        "design_size": [1024, 768],
        "top_menu": {
            "background": available_single(top_background),
            "expanded_size": [330, 54],
            "collapsed_size": [12, 26],
            "collapse_button": positioned(
                state_set(collapse_top, ["normal", "hover", "pressed"]), [1, 1]
            ),
            "expand_button": positioned(
                state_set(expand_top, ["normal", "hover", "pressed"]), [1, 1]
            ),
            "buttons": top_buttons,
        },
        "bottom_main": {
            "background": {
                "available": True,
                "path": bottom_background["path"],
                "size": bottom_background["size"],
                "origin": bottom_background["origin"],
                "edge_colors": bottom_background["edge_colors"],
                "edge_color_method": "mean_rgba_of_vertical_edge",
            },
            "design_width": 1024,
            "visible_height": 29,
            "reserve_energy": {
                "available": True,
                "position": [125, 3],
                "crop_width": 323,
                "crop_height": 3,
                "frames": {
                    "steady": energy_frames[0]["path"],
                    "flash": energy_frames[1]["path"],
                },
                "frame_sizes": {
                    "steady": energy_frames[0]["size"],
                    "flash": energy_frames[1]["size"],
                },
                "frame_origins": {
                    "steady": energy_frames[0]["origin"],
                    "flash": energy_frames[1]["origin"],
                },
            },
            "weapons": {
                "energy_cannon": positioned(
                    state_set(energy_cannon, ["normal", "selected"]), [178, 8]
                ),
                "tactical": {
                    "position": [206, 8],
                    "modes": tactical_modes,
                },
            },
            "menu_buttons": bottom_buttons,
            "shortcut_visibility_button_position": [475, 2],
        },
        "general_shortcut": {
            "background": available_single(shortcut_background),
            "size": [415, 40],
            "default_anchor": "bottom_center_above_main_bar",
            "item_page_count": 2,
            "initial_item_page_count": 1,
            "skill_page_count": 2,
            "initial_skill_page_count": 1,
            "page_up": positioned(available_single(page_up), [15, 4]),
            "page_down": positioned(available_single(page_down), [15, 20]),
            "skill_page_up_position": [391, 4],
            "skill_page_down_position": [391, 20],
            "collapse_button": state_set(
                shortcut_collapse, ["normal", "hover", "pressed"]
            ),
            "expand_button": state_set(
                shortcut_expand, ["normal", "hover", "pressed"]
            ),
        },
        "minimap_chrome": {
            "control_background": positioned(
                available_single(minimap_background), [1, 122]
            ),
            "small_size": [125, 165],
            "collapsed_size": [125, 41],
            "small_viewport": {"position": [1, 1], "size": [120, 120]},
            "control_area": {"position": [1, 122], "size": [124, 41]},
            "coordinate_position": [10, 4],
            "map_name_position": [0, 24],
            "toggle_size": {
                "position": [90, 5],
                "to_large": state_set(to_large, ["normal", "pressed"]),
                "to_small": state_set(to_small, ["normal", "pressed"]),
            },
            "toggle_visibility": {
                "position": [105, 5],
                "collapse": state_set(collapse_minimap, ["normal", "pressed"]),
                "expand": state_set(expand_minimap, ["normal", "pressed"]),
            },
            "map_content_source": "current_glory_map",
        },
        "unavailable": [],
    }
    source_audit = {
        "schema_version": 1,
        "source_release": "starhome_lz_fr",
        "scope": "HUD appearance allowlist from docs/free_hud_rendering.md section 1",
        "policy": "Original paths are provenance only; runtime uses data/ui/free_hud_assets.json.",
        "sources": session.sources,
        "missing_assets": session.missing,
    }
    write_json(RUNTIME_MANIFEST, runtime_manifest)
    write_json(SOURCE_AUDIT, source_audit)
    print(
        json.dumps(
            {
                "source_count": len(session.sources),
                "top_buttons": len(top_buttons),
                "bottom_menu_buttons": len(bottom_buttons),
                "missing": len(session.missing),
                "runtime_manifest": str(RUNTIME_MANIFEST),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0 if not session.missing else 2


if __name__ == "__main__":
    raise SystemExit(main())
