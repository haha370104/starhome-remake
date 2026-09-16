"""Recover confirmed higher-tier items and generate user-requested 5:1 level-150 recipes."""
import json
import re
from pathlib import Path
from build_original_monster_drops import ROOT, RAW, source_classes, item_ids, write
from audit_monster_asset_sources import load_decoder, file_hash


def build():
    classes, _ = source_classes()
    decoder = load_decoder()
    source_ids = item_ids()
    specs = [('Activator3', None, 'high_grade_density_solvent', 'Activator2', 'refining')]
    kinds = ['firepower', 'health', 'defense', 'guidance', 'critical', 'rocket']
    specs += [('RYRime', index, f'bright_{kind}_crystal', f'RYRime:0 {index-1000} 0', 'auxiliary_manufacturing')
              for index, kind in enumerate(kinds, 2001)]
    items, recipes, evidence = [], [], []
    for class_name, subtype, semantic, material, station in specs:
        assert len(classes[class_name]) == 1
        source = classes[class_name][0]
        body = source['body']
        if subtype:
            body = re.search(r'case\s+' + str(subtype) + r'\s*:(.*?)(?:break;)', body, re.S)[1]
        name = re.search(r'm_sObjName\s*=\s*"([^"\n]+)"', body)[1]
        name = re.sub(r'\\#[0-9a-fA-F]{6}', '', name)
        logical = f'pic3/stuff/RYRime{subtype}.ale' if subtype else 'pic3/stuff/Activator3.ale'
        original = decoder.AleFile(RAW / logical)
        frame = original.frames[0]
        image = original.decode_frame(frame)
        crop = image.getbbox()
        assert crop, logical
        image = image.crop(crop)
        target = ROOT / f'assets/items/materials/{semantic}/icon.png'
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
        resource = 'res://' + target.relative_to(ROOT).as_posix()
        audit = dict(source_release='starhome_lz_ry', source_class=f'RYRime:0 {subtype} 0' if subtype else class_name,
                     source_file=source['source_file'], source_line=source['source_line'],
                     source_logical_path=logical, source_sha256=file_hash(RAW / logical, 'sha256'),
                     source_crop=list(crop), source_frame=0)
        description = ('原版明亮晶石，可由5个同类有瑕疵晶石制造。镶嵌系统尚未开放。' if subtype
                       else '原版高级密度柔解剂，可由5个初级密度柔解剂提炼。装备开槽系统尚未开放。')
        items.append(dict(id=semantic, kind='material', display_name=name, description=description, max_stack=99,
            source_class=audit['source_class'], source_audit=audit,
            presentation=dict(world=dict(texture=resource, native_size=list(image.size), origin=[frame.origin_x+crop[0], frame.origin_y+crop[1]]),
                              inventory=dict(icon=resource, native_size=list(image.size)))))
        recipes.append(dict(recipe_id='material_upgrade_' + semantic, station_id=station, display_name=name,
            product_definition_id=semantic, required_skill_level=150, output_quantity=1,
            skill_id='refining' if station == 'refining' else 'manufacturing', skill_experience=40,
            materials=[dict(definition_id=source_ids[material], quantity=5)],
            source_audit=dict(source_release='starhome_lz_ry', source_file=source['source_file'], source_class=audit['source_class'],
                              rule_status='user_requested_remake', rule='5 same-type lower tier to 1 higher tier; level 150; deterministic success')))
        evidence.append(dict(audit, item_definition_id=semantic, resource=resource))
    write('data/gameplay/material_upgrade_items_v1.json', dict(schema_version=1, definitions=items))
    write('data/gameplay/material_upgrade_recipes_v1.json', dict(schema_version=1, recipes=recipes))
    write('assets/items/materials/material_upgrade_manifest.json', dict(definitions=evidence))
    print(f'MATERIAL_UPGRADES_BUILT items={len(items)} recipes={len(recipes)}')


if __name__ == '__main__':
    build()
