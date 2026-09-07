"""按商人白名单导入荣耀地面采掘臂，保留八向帧与脚点锚点。"""
import json
import re
from import_glory_starter_combat_assets import PROJECT_ROOT, GLORY_PARSED, TARGET_ROOT, _export_asset, _action, _atomic_json


def main():
    """从统一定义读取采掘臂来源；仅修改主装置组件映射，不覆盖其他已导入组件。"""
    catalog = json.loads((PROJECT_ROOT / 'data/gameplay/glory/glory_items_v1.json').read_text(encoding='utf-8'))
    definitions = {item['id']: item for item in catalog['definitions']}
    merchant = json.loads((PROJECT_ROOT / 'data/gameplay/commerce/weapon_merchant_v1.json').read_text(encoding='utf-8'))
    manifest_path = TARGET_ROOT / 'combat_visual_manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    audit = []
    for item_id in merchant['merchant']['official_whitelist_ids']['mining_arm']:
        definition = definitions[item_id]
        legacy = definition['stats']['legacy_properties']
        if int(legacy['m_nEquipKind2']) != 4:
            raise ValueError('Only ground mining arms are allowed')
        logical = ''.join(re.findall(r'"([^\"]*)"', legacy['m_sMoveSrc'])).removeprefix('../')
        metadata = json.loads((GLORY_PARSED / logical).with_suffix('').joinpath('frames.json').read_text(encoding='utf-8'))
        count = metadata['frame_count']
        if count % 8:
            raise ValueError('Mining arm must have eight directions')
        level = int(definition['stats']['required_skill_level'])
        component_id = f'mining_arm_level_{level}'
        target = f'mining_arms/level_{level}/working'
        exported = _export_asset(component_id, {
            'display_name': definition['display_name'], 'source_logical_path': logical,
            'target': target, 'expected_frames': count, 'direction_mode': 'eight_way',
            'frames_per_direction': count // 8, 'world_visible': True,
            'relationship_evidence': 'Glory CollecTor Location=1 and EquipKind2=4; subclass m_sMoveSrc',
        })
        audit.append(exported)
        manifest.setdefault('components', {})[component_id] = {
            'render_policy': 'world_layer',
            'action': _action(exported['runtime_resource'], count // 8, offset=exported['coordinate_bounds'][:2]),
        }
        manifest.setdefault('vehicle_component_by_equipment_definition', {})[item_id] = component_id
    _atomic_json(TARGET_ROOT / 'mining_arms/source_manifest.json', {'schema_version': 1, 'source_release': 'starhome_lz_ry', 'assets': audit})
    _atomic_json(manifest_path, manifest)


if __name__ == '__main__':
    main()
