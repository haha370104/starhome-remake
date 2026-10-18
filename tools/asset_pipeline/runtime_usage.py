"""Trace runtime resource references without treating source archives as roots."""
from collections import defaultdict
from pathlib import Path
import json
import re
import zipfile

CATALOGS = (
    'glory_map_content_packs_v1.json', 'glory_sprite_content_packs_v1.json',
    'glory_monster_palette_content_pack_v1.json', 'glory_mine_palette_content_pack_v1.json',
    'recovered_content_packs_v1.json',
)
INDEXES = (
    'glory_sprite_runtime_index_v1.json', 'glory_monster_palette_runtime_index_v1.json',
    'glory_mine_palette_runtime_index_v1.json', 'recovered_sprite_runtime_index_v1.json',
)
OFFLINE_KEYS = {'source_audit', 'legacy_properties', 'source_assets', 'source_placements',
                'owner_audit', 'scene_color', 'static_composite', 'source_order_reference',
                'profile_override_mask', 'profile_override_count', 'reference_composite'}
RESOURCE = re.compile(r'res://[^"\s\)\],;]+')
STRINGS = re.compile(r'"([^"\n]*)"|\x27([^\x27\n]*)\x27')
TEXT_SUFFIXES = {'.json', '.tres', '.tscn', '.gd', '.godot'}


def normalize(value):
    """Mirror ALE reference normalization, retaining original logical identities."""
    value = value.strip().replace('\\', '/').lower()
    while '//' in value:
        value = value.replace('//', '/')
    while value.startswith(('../', './')):
        value = value.split('/', 1)[1]
    return value.removesuffix('.ale').strip('/')


def runtime_values(value):
    """Yield runtime strings; provenance and offline comparison images are not edges."""
    if isinstance(value, str):
        yield value
    elif isinstance(value, list):
        for child in value:
            yield from runtime_values(child)
    elif isinstance(value, dict):
        for key, child in value.items():
            if key in OFFLINE_KEYS or (key.startswith('source_') and key != 'source_animation'):
                continue
            yield from runtime_values(child)


class RuntimeUsage:
    """Resolve real files and mounted ZIP members with the same first-pack-wins order."""

    def __init__(self, root):
        self.root = Path(root).resolve()
        self.catalogs = {}
        self.archives = {}
        self.members = {}
        self.indexes = {}
        self.sprites = {}
        self.by_basename = defaultdict(list)
        self.used_sprites = set()
        self.used = set()
        self.reasons = defaultdict(set)
        self.missing = defaultdict(set)
        self.queue = []
        for name in CATALOGS:
            path = 'data/content/' + name
            data = self.read_json(path)
            self.catalogs[path] = data
            for pack in data['packs']:
                pack_path = pack['path'].removeprefix('res://')
                archive = zipfile.ZipFile(self.root / pack_path)
                self.archives[pack_path] = archive
                for item in archive.infolist():
                    if not item.is_dir():
                        self.members.setdefault(item.filename, (pack_path, item))
        for name in INDEXES:
            path = 'data/content/' + name
            data = self.read_json(path)
            self.indexes[path] = data
            for row in data['sprites']:
                identity = normalize(row['logical_id'])
                self.sprites[identity] = row
                self.by_basename[identity.rsplit('/', 1)[-1]].append(identity)

    def read(self, path):
        """Read a physical resource or a mounted member without extracting archives."""
        physical = self.root / path
        if physical.is_file():
            return physical.read_bytes()
        pack, _ = self.members[path]
        return self.archives[pack].read(path)

    def read_json(self, path):
        return json.loads(self.read(path).decode('utf-8-sig'))

    def exists(self, path):
        return (self.root / path).is_file() or path in self.members

    def add(self, path, reason):
        """Queue a concrete runtime file; reject implicit inclusion of whole indexes."""
        path = path.removeprefix('res://')
        if path in self.catalogs or path in self.indexes or path.startswith('data/content/known_'):
            return
        if not self.exists(path):
            if path.startswith(('assets/', 'content/')) and Path(path).suffix:
                self.missing[path].add(reason)
            return
        self.reasons[path].add(reason)
        if path not in self.used:
            self.used.add(path)
            self.queue.append(path)

    def reference(self, value, reason):
        """Resolve resource paths and exact/prefix-resolved ALE references."""
        if value.startswith('res://'):
            self.add(value, reason)
            return
        identity = normalize(value)
        matches = [identity] if identity in self.sprites else []
        if not matches and '/' not in identity and value.lower().endswith('.ale'):
            matches = self.by_basename.get(identity, [])
        for identity in matches:
            self.used_sprites.add(identity)
            row = self.sprites[identity]
            self.add(row['frames_path'], reason + ' -> ' + identity)
            for page in row['page_paths']:
                self.add(page, reason + ' -> ' + identity)

    def trace(self):
        """Follow runtime code/scenes/configuration, excluding tests and importer evidence."""
        for folder in ('scripts', 'scenes'):
            for path in sorted((self.root / folder).rglob('*')):
                if path.suffix in {'.gd', '.tscn', '.tres'}:
                    self.add(path.relative_to(self.root).as_posix(), 'runtime entry')
        self.add('project.godot', 'project entry')
        while self.queue:
            path = self.queue.pop()
            if Path(path).suffix not in TEXT_SUFFIXES:
                continue
            text = self.read(path).decode('utf-8-sig')
            if path.endswith('.json'):
                values = runtime_values(json.loads(text))
            else:
                # Comments document old examples; they are not runtime dependencies.
                lines = [line.split('#', 1)[0] for line in text.splitlines()]
                values = [a or b for a, b in STRINGS.findall('\n'.join(lines))]
            for value in values:
                self.reference(value, path)
        # Import settings and provenance for retained physical resources remain reproducible.
        for path in list(self.used):
            if not path.startswith('assets/'):
                continue
            if self.exists(path + '.import'):
                self.used.add(path + '.import')
            parent = (self.root / path).parent
            while parent != self.root / 'assets' and parent.is_relative_to(self.root / 'assets'):
                for name in ('manifest.json', 'import_metadata.json', 'source_manifest.json'):
                    file = parent / name
                    if file.is_file():
                        self.used.add(file.relative_to(self.root).as_posix())
                parent = parent.parent
        return self

    def close(self):
        for archive in self.archives.values():
            archive.close()
