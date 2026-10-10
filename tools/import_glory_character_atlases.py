"""Rebuild the startup character atlas catalog from decoded Glory ALE sprites."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

if __package__:
    from tools.import_glory_character_clothing import render_action_atlas
else:
    from import_glory_character_clothing import render_action_atlas


ROOT = Path(__file__).resolve().parents[1]
PARSED = ROOT / "assets" / "glory" / "sprites"
RAW = ROOT / "../starhome_lz_ry_full" / "raw"
TARGET = ROOT / "assets" / "characters"
SOURCES = {
    "bodies": {
        "male": {"move": "pic3/interface/char/man", "stand": "pic3/interface/char/manstand"},
        "female": {"move": "pic3/interface/char/girl", "stand": "pic3/interface/char/womanstand"},
    },
    "shadows": {
        "male": {"move": "pic3/interface/char/manshadow", "stand": "pic3/interface/char/manstandshadow"},
        "female": {"move": "pic3/interface/char/womanshadow", "stand": "pic3/interface/char/womanstandshadow"},
    },
    "player": {"move": "pic3/clothing/body/man/mancloth01a", "stand": "pic3/clothing/stand/man/mancloth01a"},
    "npc_red": {"move": "pic3/clothing/body/man/mancloth03a", "stand": "pic3/clothing/stand/man/mancloth03a"},
    "npc_blue": {"move": "pic3/clothing/body/man/mancloth02a", "stand": "pic3/clothing/stand/man/mancloth02a"},
}


def export_action(group: str, action: str, logical: str) -> dict:
    source = PARSED / logical
    expected = 64 if action == "move" else 8
    output = TARGET / group / f"{action}_atlas.png"
    geometry = render_action_atlas(source, output, expected_frames=expected, optimize=True)
    raw = RAW / f"{logical}.ale"
    return {
        "texture": "res://" + output.relative_to(ROOT).as_posix(),
        "columns": geometry["columns"],
        "cell": geometry["cell"],
        "offset": geometry["offset"],
        "source_release": "starhome_lz_ry",
        "source_logical_path": f"{logical}.ale",
        "source_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
    }


def main() -> None:
    catalog: dict = {"schema_version": 2, "bodies": {}, "shadows": {}}
    for category in ("bodies", "shadows"):
        for sex, actions in SOURCES[category].items():
            catalog[category][sex] = {
                action: export_action(f"{category}/{sex}", action, logical)
                for action, logical in actions.items()
            }
    for group, actions in SOURCES.items():
        if group in ("bodies", "shadows"):
            continue
        result = {action: export_action(group, action, logical) for action, logical in actions.items()}
        catalog[group] = {"equipment": result}
    TARGET.mkdir(parents=True, exist_ok=True)
    (TARGET / "character_atlases.json").write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print("CHARACTER_ATLASES", len(catalog) - 1, "groups")


if __name__ == "__main__":
    main()
