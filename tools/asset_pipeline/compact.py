"""Build a runtime-only asset tree while retaining an external recovery archive."""
from collections import defaultdict
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

from .runtime_usage import RuntimeUsage, normalize

OFFLINE_IMAGES = {'scene_color', 'static_composite', 'source_order_reference', 'profile_override_mask'}
BINARY = {'.png', '.jpg', '.jpeg', '.bin'}


def digest(payload):
    return hashlib.sha256(payload).hexdigest()


def rewrite(value, aliases):
    """Update exact runtime references, preserving source identities and frame geometry."""
    if isinstance(value, str):
        return aliases.get(value, value)
    if isinstance(value, list):
        return [rewrite(child, aliases) for child in value]
    if isinstance(value, dict):
        return {key: rewrite(child, aliases) for key, child in value.items()
                if key not in OFFLINE_IMAGES}
    return value


def json_bytes(value, original=b''):
    """Preserve readable versus compact generated JSON conventions."""
    if isinstance(value, dict) and 'sprites' in value and re.search(rb'\n +\{"logical_id"', original):
        lines = ['{']
        for key, child in value.items():
            if key == 'sprites':
                lines.append('  "sprites": [')
                lines.extend('    ' + json.dumps(row, ensure_ascii=False, separators=(',', ':'))
                             + (',' if index + 1 < len(child) else '') for index, row in enumerate(child))
                lines.append('  ],')
            else:
                lines.append('  ' + json.dumps(key) + ': ' + json.dumps(child, ensure_ascii=False) + ',')
        lines[-1] = lines[-1].removesuffix(',')
        return ('\n'.join(lines) + '\n}\n').encode('utf-8')
    pretty = len(original.splitlines()) > 2
    options = {'indent': 2} if pretty else {'separators': (',', ':')}
    return (json.dumps(value, ensure_ascii=False, **options) + '\n').encode('utf-8')


def build_plan(usage):
    """Deduplicate byte-identical runtime binary members, never names or metadata."""
    seen = {}
    aliases = {}
    duplicate_bytes = 0
    for path in sorted(usage.used & usage.members.keys()):
        if Path(path).suffix not in BINARY:
            continue
        payload = usage.read(path)
        key = (Path(path).suffix, digest(payload))
        if key in seen:
            aliases['res://' + path] = 'res://' + seen[key]
            duplicate_bytes += len(payload)
        else:
            seen[key] = path
    return aliases, duplicate_bytes


def backup_file(root, archive, path):
    """Copy once to an external archive; a mismatched previous backup is an error."""
    source = root / path
    target = archive / path
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if digest(target.read_bytes()) != digest(source.read_bytes()):
            raise ValueError(f'Existing archive differs from current file: {path}')
    else:
        shutil.copy2(source, target)


def compact(root, archive, apply=False):
    """Plan or apply a reversible compaction with an explicit external archive."""
    root, archive = Path(root).resolve(), Path(archive).resolve()
    if archive.is_relative_to(root) or root.is_relative_to(archive):
        raise ValueError('Archive must be outside, and not contain, the game repository')
    usage = RuntimeUsage(root).trace()
    try:
        if usage.missing:
            raise ValueError(f'Unresolved runtime files: {dict(usage.missing)}')
        aliases, duplicate_bytes = build_plan(usage)
        removed_members = sorted(path for path in usage.members
                                 if path not in usage.used or 'res://' + path in aliases)
        keep_members = usage.used & usage.members.keys() - set(removed_members)
        protected = {'.git', '.gitattributes', '.gitignore', 'README.md'}
        removed_loose = sorted(path.relative_to(root).as_posix()
            for path in (root / 'assets').rglob('*') if path.is_file()
            and path.name not in protected and path.relative_to(root).as_posix() not in usage.used
            and path.relative_to(root).as_posix() not in usage.archives)
        report = {'schema_version': 1, 'archive': str(archive), 'apply': apply,
                  'original_sprites': len(usage.sprites), 'runtime_sprites': len(usage.used_sprites),
                  'removed_members': removed_members, 'removed_loose': removed_loose,
                  'duplicate_bytes': duplicate_bytes, 'aliases': aliases,
                  'before_bytes': sum(p.stat().st_size for p in (root/'assets').rglob('*') if p.is_file()),
                  'pack_sizes': {}}
        if not apply:
            return report
        archive.mkdir(parents=True, exist_ok=True)
        # Archive every mutated file before any replacement or deletion.
        mutations = set(usage.archives) | set(usage.indexes) | set(usage.catalogs) | set(removed_loose)
        mutations |= {p for p in usage.used if (root/p).is_file() and p.endswith('.json')}
        for path in sorted(mutations):
            backup_file(root, archive, path)
        for pack_path, original in usage.archives.items():
            temporary = archive / 'staging' / Path(pack_path).name
            temporary.parent.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(temporary, 'w') as target:
                for info in original.infolist():
                    path = info.filename
                    if path not in keep_members or usage.members[path][0] != pack_path:
                        continue
                    payload = original.read(info)
                    if path.endswith('.json'):
                        value = json.loads(payload)
                        changed = rewrite(value, aliases)
                        if changed != value:
                            payload = json_bytes(changed, payload)
                    entry = zipfile.ZipInfo(path, (2026, 1, 1, 0, 0, 0))
                    entry.compress_type = zipfile.ZIP_DEFLATED if path.endswith(('.json', '.bin')) else zipfile.ZIP_STORED
                    entry.external_attr = 0o100644 << 16
                    target.writestr(entry, payload)
            report['pack_sizes'][pack_path] = temporary.stat().st_size
            original.close()
            shutil.copy2(temporary, root / pack_path)
        for path in sorted(usage.used):
            if not (root/path).is_file() or not path.endswith('.json'):
                continue
            payload = (root/path).read_bytes()
            value = json.loads(payload.decode('utf-8-sig'))
            changed = rewrite(value, aliases)
            if changed != value:
                (root/path).write_bytes(json_bytes(changed, payload))
        for path, index in usage.indexes.items():
            index['sprites'] = [rewrite(row, aliases) for row in index['sprites']
                                if normalize(row['logical_id']) in usage.used_sprites]
            index.setdefault('summary', {})['sprites'] = len(index['sprites'])
            # Old summaries described the full offline decode, not the runtime subset.
            index['summary'].pop('decoded_bytes', None)
            (root/path).write_bytes(json_bytes(index, (root/path).read_bytes()))
        for path, catalog in usage.catalogs.items():
            for entry in catalog['packs']:
                file = root / entry['path'].removeprefix('res://')
                entry['size_bytes'] = file.stat().st_size
                entry['sha256'] = digest(file.read_bytes())
            summary = catalog.get('summary', {})
            if 'sprites' in summary and 'glory_sprite_' in path:
                summary['sprites'] = len(usage.indexes['data/content/glory_sprite_runtime_index_v1.json']['sprites'])
                summary.pop('decoded_bytes', None)
            (root/path).write_bytes(json_bytes(catalog, (root/path).read_bytes()))
        coverage_path = root/'data/content/glory_runtime_content_manifest_v1.json'
        if coverage_path.is_file():
            coverage = json.loads(coverage_path.read_bytes())
            counts = {Path(path).name: len(index['sprites']) for path, index in usage.indexes.items()}
            coverage['operational_catalogs']['animations'].update(
                decoded_ale=counts['glory_sprite_runtime_index_v1.json'],
                monster_act_variants=counts['glory_monster_palette_runtime_index_v1.json'],
                mineral_act_variants=counts['glory_mine_palette_runtime_index_v1.json'],
                recovered_animations=counts['recovered_sprite_runtime_index_v1.json'],
                runtime_total=sum(counts.values()))
            coverage_path.write_bytes(json_bytes(coverage, coverage_path.read_bytes()))
        for path in removed_loose:
            target = (root/path).resolve()
            if not target.is_relative_to(root/'assets'):
                raise ValueError(f'Refusing to remove a path outside assets: {target}')
            target.unlink()
        report['after_bytes'] = sum(p.stat().st_size for p in (root/'assets').rglob('*') if p.is_file())
        (archive/'cleanup-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
        return report
    finally:
        usage.close()
