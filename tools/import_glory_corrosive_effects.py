"""Import the effects actually selected by Glory rotbullet, not its ignored constructor argument."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
SOURCES = {"flight": "CHN_2005_06_28_19_12_40_1162", "cloud": "CHN_2005_06_28_19_12_34_1161"}


def main():
    target = ROOT / "assets/monsters/toxic_gel/shared/effects/corrosion"
    target.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for key, stem in SOURCES.items():
        logical = f"pic3/effect/{stem}.ale"
        raw = ROOT.parent / "starhome_lz_ry_full/raw" / logical
        parsed = ROOT.parent / "starhome_lz_ry_full_parsed/ale_sprites/pic3/effect" / stem
        frames = json.loads((parsed / "frames.json").read_text("utf-8"))
        assert len(frames["pages"]) == 1
        shutil.copyfile(parsed / frames["pages"][0], target / f"{key}.png")
        manifest[key] = {
            "texture": "res://" + (target / f"{key}.png").relative_to(ROOT).as_posix(),
            "directions": 8 if key == "flight" else 1,
            "cycle_seconds": 0.2 if key == "flight" else 0.8,
            "frames": [{"rect": [f["x"], f["y"], f["width"], f["height"]],
                        "origin": [f["origin_x"], f["origin_y"]]} for f in frames["frames"]],
            "source_release": "starhome_lz_ry", "source_logical_path": logical,
            "source_sha256": hashlib.sha256(raw.read_bytes()).hexdigest(),
            "source_code": "bullet.fcc:981 rotbullet; fly=200ms onmap=800ms loop",
        }
    (target / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("CORROSION_ASSETS_OK flight=40 cloud=3")


if __name__ == "__main__":
    main()
