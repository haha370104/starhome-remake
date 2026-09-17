"""Compile approved clothing stones and strength-based mutant/boss rewards."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUALITY = ['破损', '瑕疵', '平凡', '明亮', '闪耀', '完美']
PREFIX = {'tiger': '虎', 'turtle': '龟', 'dragon': '龙', 'phoenix': '凤'}
TRAITS = {'economy': '节能', 'repair': '稳修', 'pursuit': '追击', 'purification': '净化', 'prospecting': '勘探'}
GEMS = {'max_health': '生命', 'defense': '防御', 'movement_speed': '速度',
        'energy_cannon_attack': '能量炮', 'missile_attack': '导弹', 'rocket_attack': '火箭炮',
        'self_repair': '自维修', 'mining_power': '挖掘', 'working_energy_capacity': '工作能量',
        'output_power': '输出功率', 'energy_cannon_range': '能量炮射程'}
PARENTS = {**dict(zip(range(70, 81), range(1, 12))), 81: 13, 82: 14, 83: 15, 84: 16,
           85: 17, 86: 19, 87: 21, 88: 22, 89: 36, 90: 34, 91: 28, 92: 27, 93: 30,
           94: 32, 95: 31, 96: 40}
BOSSES = [111, 112, 113, 114, 115, 116, 127, 128, 129, 130]


def read(relative):
    return json.loads((ROOT / relative).read_text(encoding='utf8'))


def write(relative, value):
    path = ROOT / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf8')


def identity(family, effect, rank):
    return f'enhancement:{family}:{effect}:{rank}'


def item_definitions():
    rules = read('data/gameplay/clothing_enhancement_rules_v1.json')
    result = []
    for family, effects in [('prefix', PREFIX), ('trait', TRAITS), ('gem', GEMS)]:
        for effect, label in effects.items():
            for rank in range(1, 16 if family == 'gem' else 7):
                if family == 'gem':
                    name = f'{rank}级{label}宝石'
                    icon = f'res://assets/items/enhancement/gems/{effect}/icon.png'
                    description = f'人物装备逐段镶嵌材料，每段增加{rules["gems"][effect]}{label}。每次只升1段，空装备使用本宝石仍为1段。相同宝石2合1，最高15级。'
                else:
                    name = f'{QUALITY[rank-1]}·{label}{"强化石" if family == "prefix" else "特性石"}'
                    icon = f'res://assets/items/enhancement/{family}/{effect}/quality_{rank}.png'
                    description = f'为人物装备赋予{QUALITY[rank-1]}品质的{label}{"前缀" if family == "prefix" else "特性"}。同类同品质3合1，最高完美。'
                presentation = {'icon': icon, 'native_size': [36, 36], 'level_badge': rank if family == 'gem' else 0}
                result.append({'id': identity(family, effect, rank), 'kind': 'enhancement_stone',
                               'display_name': name, 'description': description, 'max_stack': 999,
                               'enhancement': {'family': family, 'effect': effect, 'rank': rank},
                               'presentation': {'inventory': presentation, 'world': {**presentation, 'texture': icon, 'origin': [-18, -18]}},
                               'source_audit': {'source_release': 'remake_generated', 'design_version': 1}})
    return result


def weighted_drops(family, effects, ranks, weights, expected):
    """Independent rolls sum to the requested expectation before account modifiers."""
    total = sum(weights)
    return [{'item_definition_id': identity(family, effect, rank), 'minimum_quantity': 1,
             'maximum_quantity': 1, 'chance': round(expected * weight / total / len(effects), 10)}
            for rank, weight in zip(ranks, weights) for effect in effects]


def reward_row(monster, boss=False):
    hp, attack = monster['stats']['max_health'], monster['stats']['base_attack']
    if boss:
        strength = min(1.0, max(0.0, (hp - 28000) / 322000))
        gem_expected = round(3 + 5 * strength, 3)
        affix_expected = round(1.5 + 2 * strength, 3)
        gem_ranks = [5, 6, 7, 8, 9, 10]
        gem_weights = [45-30*strength, 28-3*strength, 16+11*strength, 8+12*strength, 2.5+7.5*strength, 0.5+2.5*strength]
        quality_ranks = [3, 4, 5, 6]
        quality_weights = [55-35*strength, 30+5*strength, 13+22*strength, 2+8*strength]
    else:
        band = sum(hp > boundary for boundary in [1200, 2700, 4500, 7500])
        gem_expected = [0.3, 0.55, 0.8, 1.1, 1.5][band]
        affix_expected = [0.18, 0.3, 0.45, 0.65, 0.9][band]
        if attack == 0:
            gem_expected *= 0.5
            affix_expected *= 0.5
        gem_ranks = [1+band, 2+band, 3+band]
        gem_weights = [60, 30, 10]
        quality_ranks = [1, 2, 3, 4]
        quality_weights = [45-7.5*band, 35-1.25*band, 17+5.75*band, 3+3*band]
    drops = weighted_drops('gem', GEMS, gem_ranks, gem_weights, gem_expected)
    drops += weighted_drops('prefix', PREFIX, quality_ranks, quality_weights, affix_expected * 0.6)
    drops += weighted_drops('trait', TRAITS, quality_ranks, quality_weights, affix_expected * 0.4)
    return {'monster_id': monster['id'], 'gem_expected': gem_expected, 'affix_expected': affix_expected,
            'strength_health': hp, 'strength_attack': attack, 'drops': drops}


def main():
    monsters = {row['source_audit']['index']: row for row in read('data/gameplay/glory/glory_monsters_v1.json')['definitions']}
    # Runtime overrides own the actual beginner values, not the legacy archive.
    overrides = {row['id']: row for row in read('data/gameplay/stage3/monsters_v1.json')['definitions']}
    for index, monster in list(monsters.items()):
        if monster['id'] in overrides:
            monsters[index] = overrides[monster['id']]
    definitions, mapping = [], {}
    for index, parent in PARENTS.items():
        base = monsters[parent]
        mutant = {**monsters[index], 'stats': {**monsters[index]['stats'],
                  'max_health': base['stats']['max_health'] * 15,
                  'base_attack': base['stats']['base_attack'] * 3}}
        mapping[mutant['id']] = base['id']
        definitions.append(reward_row(mutant))
    definitions += [reward_row(monsters[index], True) for index in BOSSES]
    write('data/gameplay/clothing_enhancement_items_v1.json', {'schema_version': 1, 'definitions': item_definitions()})
    write('data/gameplay/enhancement_monsters_v1.json', {
        'schema_version': 1, 'mutant_parents': mapping,
        'health_multiplier': 15, 'attack_multiplier': 3, 'defense_multiplier': 3,
        'unresponsive_species': ['glory_monster_070'], 'boss_species': [monsters[i]['id'] for i in BOSSES],
        'mutant_per_parent': 2, 'mutant_interval_seconds': 600, 'boss_per_map': 2, 'boss_interval_seconds': 1800,
        'definitions': definitions})
    print(f'Compiled {len(item_definitions())} stone definitions and {len(definitions)} enhancement drop tables')


if __name__ == '__main__':
    main()
