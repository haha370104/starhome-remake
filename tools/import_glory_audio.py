"""Import Glory audio into the existing asset submodule with source hashes.

The decoded mapmusic table is produced by the existing FTC extraction workflow.
FFmpeg is used only offline; the game has no converter or Python dependency.
Adapted from karei03/starhome-remake commit 1f46553.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
RAW = ROOT.parent / 'starhome_lz_ry_full/raw/sound'
TABLE = ROOT.parent / 'starhome_lz_ry_full_parsed/ftc_resources/expanded/sound/mapmusic/mapmusic.txt.cab'
OUTPUT = ROOT / 'assets/audio'
EFFECTS = {
    'ui_click': ('buttons.gsm', 0.6), 'movement': ('tankeffect/tankwalk.gsm', 1.6),
    'mining': ('collector/dredge001.gsm', 3.0), 'pickup': ('bool/pick.gsm', 1.5),
    'cannon': ('gun/gun1.gsm', 1.4), 'rocket': ('firegun/CHN_2005_06_28_19_23_02_1269.gsm', 2.0),
    'missile': ('missile/missile01.gsm', 2.0), 'monster_attack': ('npcgunsound/gun1.gsm', 1.8),
    'sama_attack': ('npcgunsound/samashibing.gsm', 1.8), 'monster_death': ('npcdiesound/destroy.gsm', 2.5),
    'equipment_equip': ('zhuang.gsm', 7.0), 'equipment_unequip': ('xie.gsm', 5.3),
    'impact': ('bulletsound/blast.gsm', 1.7), 'repair': ('repair/repair001.gsm', 2.5),
    'vehicle_destroyed': ('bool/playerdie.gsm', 2.5),
}
MUSIC_NAMES = {'city': 'city_hall', 'basemic': 'field_patrol', 'clothing': 'tailor_shop',
    'home': 'residence', 'loginmic': 'login', 'newplay': 'training', 'ogrebase': 'hostile_base',
    'pkhome': 'arena', 'space': 'spaceflight', 'waitroom': 'waiting_room', 'wedding': 'wedding_hall',
    'mechanic01': 'mechanical_region'}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ffmpeg', default=shutil.which('ffmpeg'))
    args = parser.parse_args()
    if not args.ffmpeg:
        parser.error('--ffmpeg executable is required')
    lines = TABLE.read_text(encoding='utf-8-sig').splitlines()
    if lines[:2] != ['FCTB1.00', 'mytab:*s,s']:
        raise ValueError('unexpected mapmusic table')
    mapping = {a.strip().lower(): b.strip().lower() for a, b in csv.reader(lines[3:], skipinitialspace=True) if a}
    music, effects, sources = {}, {}, []
    for filename in sorted(set(mapping.values())):
        if Path(filename).name != filename or not filename.endswith('.mp3'):
            raise ValueError('unsafe track reference')
        stem = Path(filename).stem
        target = OUTPUT / 'music' / (MUSIC_NAMES.get(stem, 'sector_' + stem) + '.mp3')
        target.parent.mkdir(parents=True, exist_ok=True)
        source = RAW / 'mp3' / filename
        shutil.copyfile(source, target)
        music[filename] = 'res://' + target.relative_to(ROOT).as_posix()
        sources.append({'asset': target.relative_to(OUTPUT).as_posix(), 'source_path': 'sound/mp3/' + filename,
                        'source_sha256': digest(source), 'output_sha256': digest(target), 'conversion': 'unchanged_mp3'})
    for effect, (logical, seconds) in EFFECTS.items():
        source = RAW / logical
        data = source.read_bytes()
        if len(data) < 45 or data[:4] != b'MSG\0' or (len(data)-12) % 33 or struct.unpack_from('<I', data, 8)[0] != (len(data)-12)//33:
            raise ValueError('invalid MSG GSM: ' + logical)
        target = OUTPUT / 'effects' / (effect + '.mp3')
        target.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run([args.ffmpeg, '-hide_banner', '-loglevel', 'error', '-y', '-skip_initial_bytes', '12',
                        '-f', 'gsm', '-i', str(source), '-t', str(seconds), '-ar', '24000', '-ac', '1',
                        '-af', f'loudnorm=I=-20:TP=-2:LRA=11,afade=t=out:st={seconds-0.08}:d=0.08',
                        '-codec:a', 'libmp3lame', '-q:a', '4', str(target)], check=True)
        effects[effect] = 'res://' + target.relative_to(ROOT).as_posix()
        sources.append({'asset': target.relative_to(OUTPUT).as_posix(), 'source_path': 'sound/' + logical,
                        'source_sha256': digest(source), 'output_sha256': digest(target), 'audible_seconds': seconds,
                        'conversion': 'GSM610 to mono MP3; normalized -20 LUFS; trim silent tail; fade 80ms'})
    source = RAW / 'LevelUp.mp3'
    target = OUTPUT / 'effects/level_up.mp3'
    shutil.copyfile(source, target)
    effects['level_up'] = 'res://' + target.relative_to(ROOT).as_posix()
    sources.append({'asset': 'effects/level_up.mp3', 'source_path': 'sound/LevelUp.mp3',
                    'source_sha256': digest(source), 'output_sha256': digest(target), 'conversion': 'unchanged_mp3'})
    manifest = {'schema_version': 1, 'source_release': 'starhome_lz_ry',
                'source_table': 'sound/mapmusic.txt', 'source_table_sha256': digest(RAW / 'mapmusic.txt'),
                'decoded_table_sha256': digest(TABLE), 'assets': sources}
    (OUTPUT / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    catalog = {'schema_version': 1, 'source_release': 'starhome_lz_ry', 'music_by_legacy_code': mapping,
               'music': music, 'effects': effects,
               'remake_fallback_music_by_category': {'field': 'basemic.mp3', 'scene': 'city.mp3'}}
    path = ROOT / 'data/audio/glory_audio_v1.json'
    path.parent.mkdir(exist_ok=True)
    path.write_text(json.dumps(catalog, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(f'Imported {len(music)} tracks, {len(effects)} effects, {len(mapping)} map bindings')


if __name__ == '__main__':
    main()
