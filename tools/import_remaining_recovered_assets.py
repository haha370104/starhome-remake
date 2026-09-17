"""Build the explicitly approved cross-release recovery pack without filename fallback at runtime."""
from __future__ import annotations
import copy
import hashlib
import json
import re
import zipfile
from pathlib import Path

from audit_cross_release_assets import normalize, read, RELEASES, DEST
from import_approved_equipment_assets import ROOT, OUTPUTS

SELECTIONS = ROOT / 'data/import/recovered_asset_selections_v1.json'
PACK = ROOT / 'assets/content_packs/recovered_equipment_and_scenery.zip'


def digest(data):
    """Return the content hash used by provenance and deterministic pack checks."""
    return hashlib.sha256(data).hexdigest()


def source_files(release, reference):
    """Resolve an explicitly selected archive entry, never a basename search."""
    raw = OUTPUTS / (RELEASES[release] + '_full/raw') / reference
    parsed = OUTPUTS / (RELEASES[release] + '_full_parsed/ale_sprites') / reference.removesuffix('.ale')
    if not raw.is_file():
        raw = DEST / 'remote_cache' / release / 'raw' / reference
        parsed = DEST / 'remote_cache' / release / 'ale_sprites' / reference.removesuffix('.ale')
    if not raw.is_file() or not (parsed / 'frames.json').is_file():
        raise FileNotFoundError(reference)
    return raw, parsed


def write_rows(path, prefix, key, rows):
    """Write machine-generated records one per line so review remains manageable."""
    header = json.dumps(prefix, ensure_ascii=False)[:-1]
    opening, closing = ('[', ']') if isinstance(rows, list) else ('{', '}')
    entries = [json.dumps(row, ensure_ascii=False) for row in rows] if isinstance(rows, list) else [
        json.dumps(k) + ':' + json.dumps(v, ensure_ascii=False) for k, v in rows.items()]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(header + ',"' + key + '":' + opening + '\n' + ',\n'.join(entries) + '\n' + closing + '}\n', encoding='utf-8')


def pack_entry(archive, path, payload):
    """Use stable timestamps and semantic resource paths for repeatable archives."""
    info = zipfile.ZipInfo(path, (2026, 9, 17, 0, 0, 0))
    info.compress_type = zipfile.ZIP_DEFLATED
    archive.writestr(info, payload)


def build():
    """Import every reviewed candidate and wire all original item presentation references."""
    selections = read(SELECTIONS)['selections']
    index_path = ROOT / 'data/content/recovered_sprite_runtime_index_v1.json'
    index = read(index_path)
    rows = {r['logical_id']: r for r in index['sprites']}
    overrides_path = ROOT / 'data/presentation/recovered_equipment_v1.json'
    overrides = read(overrides_path)['definitions']
    items = read(ROOT / 'data/gameplay/glory/glory_items_v1.json')['definitions']
    evidence, destinations = [], set()
    checks = read(DEST / 'remote_checks.json')
    with zipfile.ZipFile(PACK, 'w') as archive:
        for spec in selections:
            raw, parsed = source_files(spec['source_version'], spec['source_logical_path'])
            source_bytes = raw.read_bytes()
            if digest(source_bytes) != spec['source_sha256']:
                raise ValueError('source changed: ' + spec['source_reference'])
            metadata = copy.deepcopy(read(parsed / 'frames.json'))
            target = 'assets/recovered/' + spec['asset_path']
            if target in destinations or '..' in target:
                raise ValueError('invalid or duplicate destination: ' + target)
            destinations.add(target)
            page_names = []
            page_hashes = []
            for n, source_page in enumerate(metadata['pages']):
                page = 'atlas.png' if n == 0 else f'atlas_{n}.png'
                payload = (parsed / source_page).read_bytes()
                page_hashes.append(digest(payload))
                pack_entry(archive, target + '/' + page, payload)
                page_names.append(page)
            release = RELEASES[spec['source_version']]
            metadata.update(pages=page_names, source=release + '/raw/' + spec['source_logical_path'], source_release=release)
            pack_entry(archive, target + '/frames.json', json.dumps(metadata, ensure_ascii=False, separators=(',', ':')).encode())
            logical = normalize(spec['source_reference']).removesuffix('.ale')
            row = {'logical_id': logical, 'frames_path': 'res://' + target + '/frames.json',
                   'page_paths': ['res://' + target + '/' + p for p in page_names], 'frame_count': metadata['frame_count'],
                   'source_release': release, 'source_logical_path': spec['source_logical_path'],
                   'source_replaced_reference': spec['source_reference'], 'source_sha256': spec['source_sha256']}
            rows[logical] = row
            evidence.append({**spec, 'frame_count': metadata['frame_count'], 'page_sha256': page_hashes})
            for item in items:
                for mode, presentation in item.get('presentation', {}).items():
                    if not isinstance(presentation, dict) or normalize(presentation.get('ale_reference', '')).removesuffix('.ale') != logical:
                        continue
                    restored = copy.deepcopy(presentation)
                    # Explicit normalized references also repair the source's doubled slash in old armor paths.
                    restored.update(ale_reference=logical, asset_status='recovered_from_user_approved_release', source_release=release)
                    overrides.setdefault(item['id'], {})[mode] = restored
        manifest = {'schema_version': 1, 'authorization': '2026-09-17 user: install every remaining candidate; free edition preferred when identical; earlier explicit selections preserved',
                    'policy': 'All source frames, pages and pivots preserved. Explicit references only; no runtime filename fallback.',
                    'assets': evidence, 'source_remote_checks': checks}
        pack_entry(archive, 'assets/recovered/source_manifest.json', json.dumps(manifest, ensure_ascii=False, separators=(',', ':')).encode())
    write_rows(index_path, {'schema_version': 1, 'content_version': 'approved-recovered-sprites-v2'}, 'sprites', sorted(rows.values(), key=lambda r: r['logical_id']))
    write_rows(overrides_path, {'schema_version': 1}, 'definitions', dict(sorted(overrides.items())))
    catalog = {'schema_version': 1, 'content_version': 'approved-recovered-sprites-v2', 'packs': [{
        'pack_id': 'recovered_equipment_and_scenery', 'path': 'res://assets/content_packs/' + PACK.name,
        'size_bytes': PACK.stat().st_size, 'sha256': digest(PACK.read_bytes()), 'content_groups': ['recovered_equipment', 'recovered_scenery']}],
        'summary': {'packed_references': len(selections), 'total_recovered_references': len(rows), 'item_definitions': len(overrides)}}
    (ROOT / 'data/content/recovered_content_packs_v1.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    build_scene_decorations()
    print('RECOVERY_PACK', catalog['summary'], 'bytes', PACK.stat().st_size)


def build_scene_decorations():
    """Recover original screen positions/timing; directional arrows already have identical shared art."""
    source_file = 'NFT_BL/map/traderoom1.fcc'
    source = (OUTPUTS/'starhome_lz_ry_fcc_source'/source_file).read_text(encoding='utf-8')
    rows = []
    for line, text in enumerate(source.splitlines(), 1):
        match = re.search(r"AddImgEx\('',\$\+'([^']*d\.\.ale)',(\d+),(\d+),0,(\d+)\)", text)
        if match:
            reference, x, y, interval = match.groups()
            rows.append({'id':f'TradeScreen{len(rows)+1}', 'ale_reference':reference, 'anchor':[int(x),int(y)],
                         'frame_duration_ms':int(interval), 'source_release':'starhome_lz_ry',
                         'source_file':source_file, 'source_line':line, 'source_asset_release':'starhome_lz_fr'})
    if len(rows) != 3:
        raise ValueError('Trade center declarations changed; review before regeneration')
    path = ROOT/'data/presentation/recovered_scene_decorations_v1.json'
    path.write_text(json.dumps({'schema_version':1,'maps':{'glory_nft_bl_traderoom1':rows}},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')


if __name__ == '__main__':
    build()
