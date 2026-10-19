"""Split runtime ZIPs into independently mountable, byte-preserving Git-sized packs."""
import copy
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

from .runtime_usage import CATALOGS

MAX_PACK_BYTES = 48 * 1024 * 1024


def sha256(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def split_pack(source, destination, limit=MAX_PACK_BYTES):
    """Preserve member order, names and bytes; never split a member across ZIPs."""
    source, destination = Path(source), Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(source) as original:
        groups, group, size = [], [], 22
        for member in original.infolist():
            # Use uncompressed sizes and generous header/deflate overhead to bound output.
            cost = member.file_size + 512 + 2 * len(member.filename.encode('utf-8'))
            cost += 2 * len(member.extra) + len(member.comment)
            if cost + 22 > limit:
                raise ValueError(f'One member exceeds the Git pack limit: {member.filename}')
            if group and size + cost > limit:
                groups.append(group)
                group, size = [], 22
            group.append(member)
            size += cost
        if group:
            groups.append(group)
        outputs, expected = [], []
        for number, members in enumerate(groups, 1):
            target = destination / f'{source.stem}_part_{number:03d}.zip'
            if target.exists():
                raise FileExistsError(target)
            with zipfile.ZipFile(target, 'w') as packed:
                for member in members:
                    payload = original.read(member)
                    packed.writestr(copy.copy(member), payload)
                    expected.append((member.filename, hashlib.sha256(payload).hexdigest()))
            if target.stat().st_size > limit:
                raise ValueError(f'Output exceeds size limit: {target}')
            outputs.append(target)
    actual = []
    for target in outputs:
        with zipfile.ZipFile(target) as packed:
            for member in packed.infolist():
                actual.append((member.filename, hashlib.sha256(packed.read(member)).hexdigest()))
    if actual != expected:
        raise ValueError('Split changed member order, names or bytes')
    return outputs, len(expected)


def backup(path, archive, root):
    """Copy original bytes outside the repository; refuse conflicting prior backups."""
    target = archive / 'original' / path.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        if sha256(target) != sha256(path):
            raise ValueError(f'Conflicting backup: {target}')
    else:
        shutil.copy2(path, target)
        if sha256(target) != sha256(path):
            raise ValueError(f'Backup mismatch: {target}')
    return target


def prepare(root, archive):
    """Prepare all packs/catalogs externally before changing the working tree."""
    root, archive = Path(root).resolve(), Path(archive).resolve()
    if archive.is_relative_to(root):
        raise ValueError('Archive must be outside the repository')
    output = archive / 'prepared'
    if output.exists():
        raise FileExistsError(f'Use a fresh archive directory: {output}')
    output.mkdir(parents=True)
    replacements, catalogs, verified_members = [], [], 0
    for name in CATALOGS:
        relative = Path('data/content') / name
        source_catalog = root / relative
        catalog = json.loads(source_catalog.read_text(encoding='utf-8-sig'))
        entries, changed = [], False
        for entry in catalog['packs']:
            source = (root / entry['path'].removeprefix('res://')).resolve()
            if not source.is_relative_to(root / 'assets/content_packs'):
                raise ValueError(f'Pack is outside content_packs: {source}')
            if source.stat().st_size <= MAX_PACK_BYTES:
                entries.append(entry)
                continue
            original = backup(source, archive, root)
            parts, verified = split_pack(original, output / 'assets/content_packs')
            verified_members += verified
            for part in parts:
                entries.append({**entry, 'pack_id': part.stem,
                                'path': 'res://assets/content_packs/' + part.name,
                                'size_bytes': part.stat().st_size, 'sha256': sha256(part)})
            replacements.append({'old': source.relative_to(root).as_posix(),
                                 'old_sha256': sha256(original),
                                 'parts': [p.relative_to(output).as_posix() for p in parts]})
            changed = True
            print(f'{source.name}: {len(parts)} independent packs, {verified} members verified', flush=True)
        if changed:
            backup(source_catalog, archive, root)
            catalog['packs'] = entries
            if 'packs' in catalog.get('summary', {}):
                catalog['summary']['packs'] = len(entries)
            target = output / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            # Compact records keep generated catalog changes reviewable.
            rows = [json.dumps(row, ensure_ascii=False, separators=(',', ':')) for row in entries]
            lines = ['{', f'  "schema_version": {catalog["schema_version"]},',
                     '  "content_version": ' + json.dumps(catalog['content_version']) + ',',
                     '  "packs": [', '    ' + ',\n    '.join(rows), '  ],',
                     '  "summary": ' + json.dumps(catalog.get('summary', {}), ensure_ascii=False), '}']
            target.write_text('\n'.join(lines) + '\n', encoding='utf-8')
            catalogs.append(relative.as_posix())
            if name == 'glory_sprite_content_packs_v1.json':
                index_relative = Path('data/content/glory_sprite_runtime_index_v1.json')
                index_source = root / index_relative
                backup(index_source, archive, root)
                index_data = json.loads(index_source.read_text(encoding='utf-8-sig'))
                index_data['summary']['packs'] = len(entries)
                (output / index_relative).write_text(
                    json.dumps(index_data, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
                catalogs.append(index_relative.as_posix())
    report = dict(limit_bytes=MAX_PACK_BYTES, replacements=replacements,
                  catalogs=catalogs, members_sha256_verified=verified_members,
                  prepared=True, applied=False)
    (archive / 'regular-git-packs.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report


def apply(root, archive, report):
    """Install verified parts, then remove only archived originals within content_packs."""
    root, archive = Path(root).resolve(), Path(archive).resolve()
    for row in report['replacements']:
        source = (root / row['old']).resolve()
        if not source.is_relative_to(root / 'assets/content_packs'):
            raise ValueError('Unsafe source path')
        if sha256(source) != row['old_sha256']:
            raise ValueError(f'Source changed after preparing: {source}')
        for relative in row['parts']:
            target = (root / relative).resolve()
            if not target.is_relative_to(root / 'assets/content_packs') or target.exists():
                raise ValueError(f'Unsafe or existing output path: {target}')
            shutil.copy2(archive / 'prepared' / relative, target)
        source.unlink()
    for relative in report['catalogs']:
        shutil.copy2(archive / 'prepared' / relative, root / relative)
    report['applied'] = True
    (archive / 'regular-git-packs.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
