"""Add the four audited map records in a supplemental pack; retain all old paths."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import zipfile

if __package__:
    from tools import build_glory_map_content_packs as maps
else:
    import build_glory_map_content_packs as maps

ADDITIONS = {
    'map:nft_bt/blackroom': 'blackroom',
    'map:nft_bt/yzzl': 'yzzl/variant_01_nft_bt',
    'map:nft_ds/roomsvr3': 'roomsvr3/variant_02_nft_ds',
    'map:nft_sk/yzzl': 'yzzl/variant_01_nft_bt',
}
PACK_NAME = 'glory_maps_recovered_20261014.zip'


def prepare() -> tuple[dict, dict, dict, dict]:
    """Validate exact registry matches before opening any output files."""
    known = {row['id']: row for row in maps.read_object(maps.KNOWN_MAPS_PATH)['definitions']}
    index = maps.read_object(maps.RUNTIME_INDEX_PATH)
    target_ids = {(row['world_code'], row['map_code'].lower()): row['runtime_id'] for row in index['runtime_maps']}
    for source_id in ADDITIONS:
        row = known[source_id]
        target_ids[(row['world_code'], row['map_code'].lower())] = maps.runtime_id(row['world_code'], row['map_code'])
    definitions, presentations, audit = {}, {}, {}
    for source_id, relative in ADDITIONS.items():
        row = known[source_id]
        if 'maps/' + relative not in row['resource_ids']:
            raise ValueError(f'Registry disagrees with audited presentation: {source_id}')
        source = maps.PARSED_MAP_ROOT / relative
        metadata = maps.read_object(source / 'map_metadata.json')
        if row['world_code'] not in metadata['source_branches'] or row['map_code'].lower() != metadata['map_code'].lower():
            raise ValueError(f'Wrong branch or map identity: {source_id}')
        thumbnail = maps.minimap_source(source)
        presentation = maps.Presentation('maps/' + relative, source, relative, 0)
        map_id = target_ids[(row['world_code'], row['map_code'].lower())]
        definition = maps.build_definition(row, presentation, map_id, maps.WORLD_IDS[row['world_code']], target_ids)
        definitions[map_id] = definition
        presentations[relative] = presentation
        audit[source_id] = {'runtime_id': map_id, 'presentation': relative,
                           'source_scripts': metadata['source_scripts'], 'script_sha256': metadata['script_sha256'],
                           'minimap_source': thumbnail.name, 'minimap_sha256': maps.sha256(thumbnail),
                           'navigation_sha256': maps.sha256(source / 'navigation_grid.bin'),
                           'exit_count': len(definition['transitions'])}
    return index, definitions, presentations, audit


def build(apply: bool = False) -> dict:
    """Write only a new supplement, then publish its catalog and map references."""
    index, definitions, presentations, audit = prepare()
    if not apply:
        return {'maps': audit, 'presentation_count': len(presentations), 'pack': PACK_NAME}
    pack = maps.PACK_ROOT / PACK_NAME
    temporary = pack.with_suffix('.zip.tmp')
    with zipfile.ZipFile(temporary, 'w', allowZip64=True) as archive:
        for map_id, definition in sorted(definitions.items()):
            maps.add_json(archive, definition, f'content/glory/map_definitions/{map_id}.json')
        for relative, presentation in sorted(presentations.items()):
            source = presentation.source
            root = 'content/glory/maps/' + relative
            metadata = maps.read_object(source / 'map_metadata.json')
            floor, floor_audit = maps.build_runtime_floor(presentation)
            maps.add_bytes(archive, floor, root + '/floor.png')
            maps.add_file(archive, maps.minimap_source(source), root + '/minimap.jpg')
            maps.add_file(archive, source / 'navigation_grid.bin', root + '/navigation_grid.bin')
            maps.add_json(archive, maps.build_manifest(presentation, metadata, floor_audit), root + '/scene_manifest.json')
            for original, target in [('scene_objects.json', 'source_scene_objects.json'),
                                     ('transitions.json', 'source_transitions.json'), ('map_metadata.json', 'source_metadata.json')]:
                maps.add_file(archive, source / original, root + '/' + target)
    temporary.replace(pack)
    catalog = maps.read_object(maps.CATALOG_PATH)
    catalog['packs'] = [row for row in catalog['packs'] if row['path'] != 'res://assets/content_packs/' + PACK_NAME]
    catalog['packs'].append({'pack_id': pack.stem, 'path': 'res://assets/content_packs/' + PACK_NAME,
                             'size_bytes': pack.stat().st_size, 'sha256': maps.sha256(pack), 'content_groups': ['maps']})
    rows = {row['source_id']: row for row in index['runtime_maps']}
    directory = maps.read_object(maps.GENERATED_DIRECTORY_PATH)
    for source_id, item in audit.items():
        definition = definitions[item['runtime_id']]
        world_code = definition['source_audit']['source_world']
        path = f"res://content/glory/map_definitions/{item['runtime_id']}.json"
        rows[source_id] = {'source_id': source_id, 'world_code': world_code,
                          'world_id': definition['world']['id'], 'map_code': definition['legacy']['codes'][0],
                          'runtime_id': item['runtime_id'], 'definition_path': path,
                          'presentation_id': 'maps/' + item['presentation'], 'presentation_mode': 'flattened_source_composite'}
        directory['definitions'][item['runtime_id']] = path
    unresolved = [item for item in index['unresolved_source_ids'] if item not in ADDITIONS]
    summary = dict(index['summary'])
    summary['resolved_runtime_rows'] = len(rows)
    summary['generated_definitions'] = sum(row['presentation_mode'] != 'semantic' for row in rows.values())
    summary['unique_presentations'] = len({row['presentation_id'] for row in rows.values()})
    summary['unresolved_source_rows'] = len(unresolved)
    catalog['summary'] = summary
    maps.write_object(maps.CATALOG_PATH, catalog)
    maps.write_runtime_index(maps.RUNTIME_INDEX_PATH, summary, [rows[key] for key in sorted(rows)], unresolved)
    directory['definitions'] = dict(sorted(directory['definitions'].items()))
    maps.write_object(maps.GENERATED_DIRECTORY_PATH, directory)
    refresh_coverage()
    evidence = {'schema_version': 1, 'source_release': 'starhome_lz_ry', 'maps': audit,
                'pack_sha256': maps.sha256(pack), 'notes': [
                    'Original parsed sources were skipped for missing minimap.jpg; thumbnails are source-derived.',
                    'Both yzzl records use identical yzzl_1 FCC content whose logical map code is yzzl.',
                    'No incoming transports to these four records were found in the current runtime index.',
                    'No entrances or return transport for blackroom were invented; this restores loadable content.']}
    maps.write_object(maps.PROJECT_ROOT / 'data/content/glory_map_recovery_20261014.json', evidence)
    return {'pack': str(pack), 'bytes': pack.stat().st_size, 'maps': len(definitions), 'summary': summary}


def refresh_coverage() -> None:
    """Refresh map evidence only; other catalogs keep their independent provenance."""
    if __package__:
        from tools import build_known_content_registries as known
    else:
        import build_known_content_registries as known
    definitions, summary = known.build_maps()
    previous = maps.read_object(known.MAP_TARGET)
    known.compact_document(known.MAP_TARGET, 'map', definitions, summary, previous['source_audit'])
    manifest = maps.read_object(known.MANIFEST_TARGET)
    manifest['expected_counts']['map'] = summary
    maps.write_object(known.MANIFEST_TARGET, manifest)
    path = maps.PROJECT_ROOT / 'data/content/glory_runtime_content_manifest_v1.json'
    coverage = maps.read_object(path)
    coverage['operational_catalogs']['maps']['runtime_ready'] = summary['runtime_ready_source_keys']
    coverage['operational_catalogs']['maps']['unresolved'] = summary['definitions'] - summary['runtime_ready_source_keys']
    coverage['explicit_exceptions'] = [row for row in coverage['explicit_exceptions'] if row['kind'] != 'map_package_missing']
    maps.write_object(path, coverage)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='Write the supplemental pack and catalogs')
    arguments = parser.parse_args()
    print(json.dumps(build(arguments.apply), ensure_ascii=False, indent=2))
