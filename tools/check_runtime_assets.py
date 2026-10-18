"""Reject unreachable runtime assets and verify retained bytes against an external archive."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

from asset_pipeline.runtime_usage import RuntimeUsage, CATALOGS
from asset_pipeline.compact import BINARY, rewrite


def check(root, archive=None):
    """Check graph closure; optionally prove binary and JSON preservation after cleanup."""
    usage = RuntimeUsage(root).trace()
    try:
        failures = [f'Missing {path}: {sorted(reasons)}' for path, reasons in usage.missing.items()]
        unused = set(usage.members) - usage.used
        failures.extend('Unused packed member: ' + path for path in sorted(unused))
        protected = {'.git', '.gitattributes', '.gitignore', 'README.md'}
        for file in (root/'assets').rglob('*'):
            if not file.is_file() or file.name in protected:
                continue
            path = file.relative_to(root).as_posix()
            if path not in usage.used and path not in usage.archives:
                failures.append('Unused physical resource: ' + path)
        summary = {'runtime_sprites': len(usage.used_sprites), 'packed_members': len(usage.members),
                   'binary_bytes_verified': 0, 'binary_files_verified': 0, 'json_files_verified': 0}
        if archive:
            report = json.loads((archive/'cleanup-report.json').read_text(encoding='utf-8'))
            originals, old_members = {}, {}
            try:
                for name in CATALOGS:
                    catalog = json.loads((archive/'data/content'/name).read_bytes())
                    for row in catalog['packs']:
                        path = row['path'].removeprefix('res://')
                        original = zipfile.ZipFile(archive/path)
                        originals[path] = original
                        for member in original.namelist():
                            old_members.setdefault(member, original)
                for path in sorted(usage.used):
                    if not path.startswith(('assets/', 'content/')):
                        continue
                    if (archive/path).is_file():
                        before = (archive/path).read_bytes()
                    elif path in old_members:
                        before = old_members[path].read(path)
                    else:
                        failures.append('Retained resource missing from archive: ' + path)
                        continue
                    after = usage.read(path)
                    if Path(path).suffix in BINARY:
                        if hashlib.sha256(before).digest() != hashlib.sha256(after).digest():
                            failures.append('Binary changed: ' + path)
                        summary['binary_files_verified'] += 1
                        summary['binary_bytes_verified'] += len(after)
                    elif path.endswith('.json'):
                        expected = rewrite(json.loads(before.decode('utf-8-sig')), report['aliases'])
                        if expected != json.loads(after.decode('utf-8-sig')):
                            failures.append('Runtime metadata changed: ' + path)
                        summary['json_files_verified'] += 1
                for source, target in report['aliases'].items():
                    before = old_members[source.removeprefix('res://')].read(source.removeprefix('res://'))
                    after = usage.read(target.removeprefix('res://'))
                    if hashlib.sha256(before).digest() != hashlib.sha256(after).digest():
                        failures.append('Invalid shared binary: ' + source)
                summary['aliases_verified'] = len(report['aliases'])
            finally:
                for original in originals.values():
                    original.close()
        return summary, failures
    finally:
        usage.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path)
    args = parser.parse_args()
    summary, failures = check(Path(__file__).resolve().parents[1], args.archive)
    print(json.dumps({**summary, 'failures': failures}, ensure_ascii=False, indent=2))
    return int(bool(failures))


if __name__ == '__main__':
    raise SystemExit(main())
