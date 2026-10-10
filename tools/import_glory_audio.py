"""Materialize Glory map music and used effects from workspace-local raw sound.

Run with: python3 tools/import_glory_audio.py
Requires ffmpeg, plus the FTC decoder dependencies used by recovery/fcc_workspace.py.
"""

from __future__ import annotations

import csv
import hashlib
import json
import shutil
import struct
import subprocess
from pathlib import Path

from recovery.fcc_workspace import RawFccWorkspace, decode_text


ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT / "../starhome_lz_ry_full" / "raw" / "sound"
OUTPUT = ROOT / "assets" / "audio" / "glory"
CATALOG = ROOT / "data" / "audio" / "glory_audio_v1.json"

# The source GSM files include long silent tails. Keep the audible opening of each cue.
EFFECTS = {
    "ui_click": ("buttons.gsm", 0.6),
    "movement": ("tankeffect/tankwalk.gsm", 1.6),
    "mining": ("collector/dredge001.gsm", 3.0),
    "pickup": ("bool/pick.gsm", 1.5),
    "cannon": ("gun/gun1.gsm", 1.4),
    "rocket": ("firegun/CHN_2005_06_28_19_23_02_1269.gsm", 2.0),
    "missile": ("missile/missile01.gsm", 2.0),
    "monster_attack": ("npcgunsound/gun1.gsm", 1.8),
    "sama_attack": ("npcgunsound/samashibing.gsm", 1.8),
    "monster_death": ("npcdiesound/destroy.gsm", 2.5),
    "equipment_equip": ("zhuang.gsm", 7.0),
    "equipment_unequip": ("xie.gsm", 5.3),
    "impact": ("bulletsound/blast.gsm", 1.7),
    "repair": ("repair/repair001.gsm", 2.5),
    "vehicle_destroyed": ("bool/playerdie.gsm", 2.5),
    "slot_spin": ("tiger/tigerrun.gsm", 1.0),
    "slot_win": ("tiger/tigerwin.gsm", 0.8),
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def map_music() -> dict[str, str]:
    with RawFccWorkspace() as workspace:
        payload = workspace.payload("sound/mapmusic.txt")
    source, encoding = decode_text(payload)
    if encoding.endswith("-replace"):
        raise ValueError("mapmusic.txt contains undecodable text")
    lines = source.splitlines()
    if lines[:2] != ["FCTB1.00", "mytab:*s,s"]:
        raise ValueError("unexpected Glory mapmusic table header")
    rows = csv.reader(lines[2:], skipinitialspace=True)
    if next(rows) != ["mapname", "musicfilename"]:
        raise ValueError("unexpected Glory mapmusic table columns")
    mapping: dict[str, str] = {}
    for row in rows:
        if not row:
            continue
        if len(row) != 2:
            raise ValueError(f"invalid Glory mapmusic row: {row}")
        code, filename = (part.strip().lower() for part in row)
        if not code or Path(filename).name != filename or not filename.endswith(".mp3"):
            raise ValueError(f"invalid Glory map music reference: {row}")
        if code in mapping and mapping[code] != filename:
            raise ValueError(f"conflicting music for {code}")
        mapping[code] = filename
    return mapping


def import_effect(ffmpeg: str, effect_id: str, source_name: str, seconds: float) -> tuple[str, str]:
    source = RAW / source_name
    data = source.read_bytes()
    if len(data) < 45 or data[:4] != b"MSG\0" or (len(data) - 12) % 33:
        raise ValueError(f"invalid Glory GSM container: {source}")
    frame_count = struct.unpack_from("<I", data, 8)[0]
    if frame_count != (len(data) - 12) // 33:
        raise ValueError(f"GSM frame count mismatch: {source}")
    target = OUTPUT / "effects" / f"{effect_id}.mp3"
    target.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run([
        ffmpeg, "-hide_banner", "-loglevel", "error", "-y", "-skip_initial_bytes", "12",
        "-f", "gsm", "-i", str(source), "-t", str(seconds), "-ar", "24000", "-ac", "1",
        "-af", f"loudnorm=I=-20:TP=-2:LRA=11,afade=t=out:st={max(0.0, seconds - 0.08)}:d=0.08",
        "-codec:a", "libmp3lame", "-q:a", "4", str(target),
    ], check=True)
    return "res://" + target.relative_to(ROOT).as_posix(), sha256(source)


def main() -> None:
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is required to decode Glory GSM effects")
    mapping = map_music()
    tracks: dict[str, str] = {}
    evidence: dict[str, str] = {"sound/mapmusic.txt": sha256(RAW / "mapmusic.txt")}
    for filename in sorted(set(mapping.values())):
        source = RAW / "mp3" / filename
        target = OUTPUT / "music" / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        tracks[filename] = "res://" + target.relative_to(ROOT).as_posix()
        evidence["sound/mp3/" + filename] = sha256(source)
    effects: dict[str, str] = {}
    for effect_id, (source_name, seconds) in EFFECTS.items():
        effects[effect_id], evidence["sound/" + source_name] = import_effect(
            ffmpeg, effect_id, source_name, seconds
        )
    level_up_source = RAW / "LevelUp.mp3"
    level_up_target = OUTPUT / "effects" / "level_up.mp3"
    shutil.copyfile(level_up_source, level_up_target)
    effects["level_up"] = "res://" + level_up_target.relative_to(ROOT).as_posix()
    evidence["sound/LevelUp.mp3"] = sha256(level_up_source)
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(json.dumps({
        "schema_version": 1,
        "source_release": "starhome_lz_ry",
        "music_by_legacy_code": mapping,
        "remake_fallback_music_by_category": {"field": "basemic.mp3", "scene": "city.mp3"},
        "music": tracks,
        "effects": effects,
        "source_sha256": evidence,
    }, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Imported {len(tracks)} music tracks, {len(effects)} effects, {len(mapping)} map bindings")


if __name__ == "__main__":
    main()
