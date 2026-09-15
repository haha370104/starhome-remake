"""Incrementally export the eight retained Free HUD buttons, preserving other HUD assets."""
from import_free_hud_assets import (
    ImportSession, TOP_BUTTONS, DESTINATION_ROOT, RUNTIME_MANIFEST,
    SOURCE_AUDIT, positioned, read_json, state_set, write_json,
)

RETAINED = ("party", "return_base", "self_repair", "summon_guard",
            "smart_assistant", "central_controller", "mercenary", "experience")


def main():
    """Keep the original three-state images and provenance; layout belongs to the view."""
    session = ImportSession()
    runtime = read_json(RUNTIME_MANIFEST)
    audit = read_json(SOURCE_AUDIT)
    for action in RETAINED:
        source, position = TOP_BUTTONS[action]
        frames = session.export_ale_frames(
            f"top_menu.buttons.{action}", source,
            DESTINATION_ROOT / "top_menu" / "buttons" / action,
            ["normal.png", "hover.png", "pressed.png"],
        )
        runtime["top_menu"]["buttons"][action] = positioned(
            state_set(frames, ["normal", "hover", "pressed"]), position,
        )
    audit["sources"].update(session.sources)
    write_json(RUNTIME_MANIFEST, runtime)
    write_json(SOURCE_AUDIT, audit)
    print(f"Retained HUD icons: {len(RETAINED)} buttons, 24 original frames")


if __name__ == "__main__":
    main()
