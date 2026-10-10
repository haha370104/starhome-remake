"""Materialize approved cross-release ALE assets from local raw into assets/recovered."""
from __future__ import annotations
import copy
import hashlib
import json
import re
import shutil
from contextlib import ExitStack
from pathlib import Path
from tempfile import TemporaryDirectory

from audit_cross_release_assets import normalize, read, RELEASES
from recovery.fcc_workspace import RawFccWorkspace
from recovery.source_workspace import RawSpriteWorkspace

ROOT = Path(__file__).resolve().parents[1]
SELECTIONS = ROOT / 'data/import/recovered_asset_selections_v1.json'
RAW_ROOTS = {release: ROOT / (name + '_full') / 'raw' for release, name in RELEASES.items()}
DESTINATION = ROOT / 'assets/recovered'


def digest(data):
    """Return the content hash used by provenance and deterministic pack checks."""
    return hashlib.sha256(data).hexdigest()


def write_rows(path, prefix, key, rows):
    """Write machine-generated records one per line so review remains manageable."""
    header = json.dumps(prefix, ensure_ascii=False)[:-1]
    opening, closing = ('[', ']') if isinstance(rows, list) else ('{', '}')
    entries = [json.dumps(row, ensure_ascii=False) for row in rows] if isinstance(rows, list) else [
        json.dumps(k) + ':' + json.dumps(v, ensure_ascii=False) for k, v in rows.items()]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(header + ',"' + key + '":' + opening + '\n' + ',\n'.join(entries) + '\n' + closing + '}\n', encoding='utf-8')


def preserved_runtime_specs(index_rows, selections):
    """Return previously indexed recovered sprites that are outside the new selections."""
    selected = {(row['source_logical_path'], row['source_sha256']) for row in selections}
    release_names = {'starhome_lz_fr': 'free', 'starhome_jznp': 'jz'}
    specs = []
    for row in index_rows:
        identity = (row.get('source_logical_path', ''), row.get('source_sha256', ''))
        if identity in selected:
            continue
        source_version = release_names.get(row.get('source_release', ''))
        frames_path = str(row.get('frames_path', ''))
        prefix = 'res://assets/recovered/'
        suffix = '/frames.json'
        if source_version is None or not frames_path.startswith(prefix) or not frames_path.endswith(suffix):
            continue
        specs.append({
            'source_audit_id': 'legacy-runtime:' + str(row['logical_id']),
            'source_reference': row.get('source_replaced_reference', row['source_logical_path']),
            'source_version': source_version,
            'source_logical_path': row['source_logical_path'],
            'source_sha256': row['source_sha256'],
            'asset_path': frames_path[len(prefix):-len(suffix)],
            'source_match': 'preserved_runtime_index',
            'source_comparison': 'previously_recovered',
        })
    return specs


def build():
    """Import every reviewed candidate and wire all original item presentation references."""
    selections = read(SELECTIONS)['selections']
    index_path = ROOT / 'data/content/recovered_sprite_runtime_index_v1.json'
    index = read(index_path)
    rows = {r['logical_id']: r for r in index['sprites']}
    overrides_path = ROOT / 'data/presentation/recovered_equipment_v1.json'
    overrides = read(overrides_path)['definitions']
    items = read(ROOT / 'data/gameplay/glory/glory_items_v1.json')['definitions']
    legacy_specs = preserved_runtime_specs(index['sprites'], selections)
    evidence, legacy_evidence, destinations = [], [], set()
    specs = selections + legacy_specs
    with ExitStack() as stack:
        workspaces = {release: stack.enter_context(RawSpriteWorkspace(raw_root))
                      for release, raw_root in RAW_ROOTS.items()}
        for release, workspace in workspaces.items():
            workspace.require([spec['source_logical_path'] for spec in specs if spec['source_version'] == release])
        for spec in specs:
            raw = workspaces[spec['source_version']].source(spec['source_logical_path'])
            if digest(raw.read_bytes()) != spec['source_sha256']:
                raise ValueError('source changed: ' + spec['source_reference'])

        with TemporaryDirectory(prefix='starhome-recovered-') as temporary:
            staged = Path(temporary)
            for spec_index, spec in enumerate(specs):
                relative = Path(spec['asset_path'])
                if relative == Path('.') or relative.is_absolute() or '..' in relative.parts or relative in destinations:
                    raise ValueError('invalid or duplicate destination: ' + spec['asset_path'])
                destinations.add(relative)
                decoded, decoded_metadata = workspaces[spec['source_version']].decode(spec['source_logical_path'])
                metadata = copy.deepcopy(decoded_metadata)
                target = staged / relative
                target.mkdir(parents=True, exist_ok=True)
                page_names, page_hashes = [], []
                for number, source_page in enumerate(metadata['pages']):
                    page = 'atlas.png' if number == 0 else f'atlas_{number}.png'
                    payload = (decoded / source_page).read_bytes()
                    (target / page).write_bytes(payload)
                    page_hashes.append(digest(payload))
                    page_names.append(page)
                release = RELEASES[spec['source_version']]
                metadata.update(pages=page_names, source=release + '/raw/' + spec['source_logical_path'], source_release=release)
                (target / 'frames.json').write_text(json.dumps(metadata, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
                if spec_index < len(selections):
                    logical = normalize(spec['source_reference']).removesuffix('.ale')
                    resource = 'res://assets/recovered/' + relative.as_posix()
                    rows[logical] = {'logical_id': logical, 'frames_path': resource + '/frames.json',
                        'page_paths': [resource + '/' + page for page in page_names], 'frame_count': metadata['frame_count'],
                        'source_release': release, 'source_logical_path': spec['source_logical_path'],
                        'source_replaced_reference': spec['source_reference'], 'source_sha256': spec['source_sha256']}
                    evidence.append({**spec, 'frame_count': metadata['frame_count'], 'page_sha256': page_hashes})
                    for item in items:
                        for mode, presentation in item.get('presentation', {}).items():
                            if not isinstance(presentation, dict) or normalize(presentation.get('ale_reference', '')).removesuffix('.ale') != logical:
                                continue
                            restored = copy.deepcopy(presentation)
                            restored.update(ale_reference=logical, asset_status='recovered_from_user_approved_release', source_release=release)
                            overrides.setdefault(item['id'], {})[mode] = restored
                else:
                    legacy_evidence.append({**spec, 'frame_count': metadata['frame_count'], 'page_sha256': page_hashes})

            manifest = {'schema_version': 1, 'authorization': '2026-09-17 user: install every remaining candidate; free edition preferred when identical; earlier explicit selections preserved',
                        'policy': 'All source frames, pages and pivots preserved. Explicit references only; no runtime filename fallback.',
                        'assets': evidence, 'preserved_runtime_assets': legacy_evidence}
            previous_manifest = DESTINATION / 'source_manifest.json'
            if previous_manifest.is_file():
                previous_checks = read(previous_manifest).get('source_remote_checks')
                if previous_checks:
                    manifest['source_remote_checks'] = previous_checks
            (staged / 'source_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
            for source in staged.rglob('*'):
                if not source.is_file():
                    continue
                target = DESTINATION / source.relative_to(staged)
                target.parent.mkdir(parents=True, exist_ok=True)
                if not target.is_file() or source.read_bytes() != target.read_bytes():
                    shutil.copy2(source, target)
    write_rows(index_path, {'schema_version': 1, 'content_version': 'approved-recovered-sprites-v2'}, 'sprites', sorted(rows.values(), key=lambda r: r['logical_id']))
    write_rows(overrides_path, {'schema_version': 1}, 'definitions', dict(sorted(overrides.items())))
    build_scene_decorations()
    print('RECOVERED_CONTENT', {'selected': len(selections), 'total_references': len(rows), 'item_definitions': len(overrides)})


def build_scene_decorations():
    """Recover original screen positions/timing; directional arrows already have identical shared art."""
    source_file = 'NFT_BL/map/traderoom1.fcc'
    with RawFccWorkspace() as fcc:
        source = fcc.text(source_file)
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
