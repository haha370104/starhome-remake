"""Apply explicit remake material supply without rewriting original evidence."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
BIO_NAMES = {grade + material for grade in ('中级', '高级')
             for material in ('生物硅', '四足甲的壳', '类胶', '能量催化剂')}
CRAWLERS = {'glory_monster_046', 'glory_monster_114'}
MINING_POLICY = {
    '硫矿': (150, 'c07'), '磷矿': (200, 'g06'), '钾矿': (250, 'h07'),
    '镭矿': (300, 'd08'), '铬矿': (300, 'd08'),
    '镍矿': (300, 'c08'), '锌矿': (300, 'c08'),
    '钛矿': (350, 'h08'), '钪矿': (450, 'e07'),
    '镁矿': (500, 'e06'), '钡矿': (550, 'd06'),
}


def read(path):
    return json.loads(path.read_text(encoding='utf-8'))


def write(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def build_drops():
    """Keep original ranges, deduplicate candidates, and label remake odds."""
    monsters = read(ROOT / 'data/gameplay/glory/glory_monsters_v1.json')
    items = read(ROOT / 'data/gameplay/glory/glory_items_v1.json')
    ids = {row['display_name']: row['id'] for row in items['definitions']}
    rows = []
    for monster in monsters['definitions']:
        grouped = {}
        for candidate in monster['source_drop_candidates']:
            name = candidate['display_name']
            if name not in BIO_NAMES:
                continue
            if name not in grouped:
                grouped[name] = {'item_definition_id': ids[name],
                                 'minimum_quantity': candidate['minimum_quantity'],
                                 'maximum_quantity': candidate['maximum_quantity'],
                                 'chance': 0.75 if name.startswith('中级') else 0.5}
            else:
                grouped[name]['minimum_quantity'] = min(grouped[name]['minimum_quantity'], candidate['minimum_quantity'])
                grouped[name]['maximum_quantity'] = max(grouped[name]['maximum_quantity'], candidate['maximum_quantity'])
        drops = list(grouped.values())
        if monster['id'] in CRAWLERS:
            # P(0)=.25; P(1)=P(2)=P(3)=.75/3=.25; E=1.5.
            drops.append({'item_definition_id': ids['接合器升级碎片'],
                          'minimum_quantity': 1, 'maximum_quantity': 3, 'chance': 0.75})
        if drops:
            rows.append({'monster_id': monster['id'], 'display_name': monster['display_name'], 'drops': drops})
    document = {'schema_version': 1, 'content_version': 'upgrade-material-supply-v1',
                'source_audit': {'source_release': 'starhome_lz_ry',
                                 'catalog': 'glory/glory_monsters_v1.json',
                                 'bio_targets_and_ranges': 'client produce_obj candidates; duplicate names merged, not rolled twice',
                                 'bio_chance': 'remake default: middle 0.75, high 0.5; original raw_weight algorithm unconfirmed',
                                 'crawler_chance': 'user confirmed two crawler species and variants; uniform 0..3, expectation 1.5'},
                'definitions': rows}
    write(ROOT / 'data/gameplay/monster_material_drops_v1.json', document)
    print(f'Material drops: {len(rows)} species; {sum(len(r["drops"]) for r in rows)} rules')


def apply_mining():
    """Preserve historical pools while adding explicit material-chain placements."""
    path = ROOT / 'data/gameplay/mining_v1.json'
    document = read(path)
    manifest_path = ROOT / 'assets/minerals/mining_asset_manifest.json'
    manifest = read(manifest_path)
    for mineral in document['minerals']:
        if mineral['display_name'] not in MINING_POLICY:
            continue
        level, coordinate = MINING_POLICY[mineral['display_name']]
        mineral['required_mining_level'] = level
        mineral['experience_coefficient'] = level / 10.0
        mineral['tooltip'] = f'{mineral["display_name"]}，需要采矿等级{level}级'
        mineral['evidence']['runtime_supply'] = '2026-09-15 user requested level-based remake placement'
        if mineral['display_name'] in ('硫矿', '磷矿', '钾矿', '钛矿', '钪矿'):
            mineral['evidence']['level'] = '复刻配置；原版矿源等级未确认'
            presentation = mineral['presentation']
            presentation['world_animation'] = presentation['inventory_animation']
            mineral['evidence']['world_presentation'] = '复用本矿石的荣耀物品图；未声称恢复独立矿源动画'
            manifest['definitions'][mineral['id']]['world_animation'] = presentation['world_animation']
        for world in ('bl', 'bt'):
            policy = document['maps'][f'glory_nft_{world}_{coordinate}']
            policy['remake_material_supply'] = '2026-09-15 按采掘等级补充接合器材料矿物；原矿池保留'
            if not any(entry['mineral_id'] == mineral['id'] for entry in policy['mineral_pool']):
                policy['mineral_pool'].append({'mineral_id': mineral['id'], 'weight': 1.0})
    write(path, document)
    write(manifest_path, manifest)


if __name__ == '__main__':
    build_drops()
    apply_mining()
