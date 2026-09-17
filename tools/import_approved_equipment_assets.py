"""Import user-approved free-release chassis and the three explicit differing equipment choices."""
from pathlib import Path
import copy
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
OUTPUTS = ROOT.parent
SPECS = [
    ('tanlang_chassis', 'FinalTank', ['FinalTank', 'FinalTank_Warrior', 'FinalTank_Warrior_1'], ['finaltank'] * 3),
    ('monarch_chassis', 'MonarchFinalTank', ['MonarchFinalTank'], ['monarchtank'] * 3),
    ('christmas_chassis', 'Xmastank', ['Xmastank'], ['xmastank'] * 3),
    ('dragon_recruit_chassis', 'tankDragon', ['tankDragon'], ['btankdragon', 'dtankdragon', 'mtankdragon']),
]


def write_json(path, value, compact=False):
    """Write generated metadata deterministically; large frame arrays use compact machine-owned JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=None if compact else 2,
                              separators=(',', ':') if compact else None) + '\n', encoding='utf-8')


def main():
    """Preserve source frames and pivots, recording each explicit cross-release replacement."""
    items = json.loads((ROOT/'data/gameplay/glory/glory_items_v1.json').read_text(encoding='utf-8'))['definitions']
    by_class = {d.get('source_class'): d for d in items}
    index = {'schema_version': 1, 'content_version': 'approved-recovered-sprites-v1', 'sprites': []}
    overrides = {'schema_version': 1, 'definitions': {}}
    for slug, main_class, classes, source_names in SPECS:
        folder = ROOT/'assets/recovered/vehicles'/slug
        evidence = {'schema_version': 1, 'source_release': 'starhome_lz_fr',
                    'authorization': '2026-09-17 user approved four previewed free-release chassis as replacements, including their matching inventory/dialog views',
                    'source_classes': classes, 'assets': []}
        for mode, source_role, target_role, stem in zip(['inventory','dialog','world'], ['bag','dlg','body'], ['inventory','equipment_panel','locomotion'], source_names):
            source_ref = 'pic2/equip/' + source_role + '/' + stem + '.ale'
            raw = OUTPUTS/'starhome_lz_fr_full/raw'/source_ref
            decoded = OUTPUTS/'starhome_lz_fr_full_parsed/ale_sprites'/source_ref.removesuffix('.ale')
            assert raw.is_file() and (decoded/'frames.json').is_file(), source_ref
            metadata = json.loads((decoded/'frames.json').read_text(encoding='utf-8'))
            target = folder/target_role
            target.mkdir(parents=True,exist_ok=True)
            pages=[]
            for n, page in enumerate(metadata['pages']):
                name = 'atlas.png' if n==0 else f'atlas_{n}.png'
                shutil.copy2(decoded/page,target/name)
                pages.append(name)
            metadata['pages'] = pages
            metadata['source'] = 'starhome_lz_fr/raw/' + source_ref
            metadata['source_release'] = 'starhome_lz_fr'
            write_json(target/'frames.json',metadata,compact=True)
            original = by_class[main_class]['presentation'][mode]['ale_reference']
            logical = original.removeprefix('../').removesuffix('.ale').lower()
            resource = 'res://' + target.relative_to(ROOT).as_posix()
            index['sprites'].append({'logical_id':logical,'frames_path':resource+'/frames.json','page_paths':[resource+'/'+p for p in pages],
                'frame_count':metadata['frame_count'],'source_release':'starhome_lz_fr','source_logical_path':source_ref,
                'source_replaced_reference':original,'source_sha256':hashlib.sha256(raw.read_bytes()).hexdigest()})
            evidence['assets'].append(copy.deepcopy(index['sprites'][-1]))
            for cls in classes:
                item = by_class[cls]
                presentation = copy.deepcopy(item['presentation'][mode])
                presentation['asset_status']='recovered_from_user_approved_release'
                presentation['source_release']='starhome_lz_fr'
                overrides['definitions'].setdefault(item['id'],{})[mode]=presentation
        write_json(folder/'source_manifest.json',evidence)
    # User explicitly chose the free edition for A310/A311/A370/A371 on 2026-09-17.
    extra = [
        ('nano_front_armor', 'inventory', 'pic2/equip/armor/frontarmor8b.ale'),
        ('nano_front_armor', 'dialog', 'pic2/equip/armor/frontarmor8.ale'),
        ('monarch_energy_cannon', 'dialog', 'pic2/equip/dlg/monarchgun.ale'),
    ]
    manifests = {}
    for slug, mode, source_ref in extra:
        role = 'inventory' if mode == 'inventory' else 'equipment_panel'
        folder = ROOT/'assets/recovered/equipment'/slug
        target = folder/role
        target.mkdir(parents=True, exist_ok=True)
        raw = OUTPUTS/'starhome_lz_fr_full/raw'/source_ref
        decoded = OUTPUTS/'starhome_lz_fr_full_parsed/ale_sprites'/source_ref.removesuffix('.ale')
        metadata = json.loads((decoded/'frames.json').read_text(encoding='utf-8'))
        assert metadata['pages'] == ['sheet.png'], source_ref
        shutil.copy2(decoded/'sheet.png', target/'atlas.png')
        metadata.update(pages=['atlas.png'], source='starhome_lz_fr/raw/'+source_ref, source_release='starhome_lz_fr')
        write_json(target/'frames.json',metadata,compact=True)
        resource = 'res://' + target.relative_to(ROOT).as_posix()
        row = {'logical_id':source_ref.removesuffix('.ale'),'frames_path':resource+'/frames.json','page_paths':[resource+'/atlas.png'],
               'frame_count':metadata['frame_count'],'source_release':'starhome_lz_fr','source_logical_path':source_ref,
               'source_replaced_reference':source_ref,'source_sha256':hashlib.sha256(raw.read_bytes()).hexdigest()}
        index['sprites'].append(row)
        manifests.setdefault(folder,[]).append(row)
        for item in items:
            presentation = item.get('presentation',{}).get(mode,{})
            if presentation.get('ale_reference','').removeprefix('../').lower() == source_ref:
                restored = copy.deepcopy(presentation)
                restored.update(asset_status='recovered_from_user_approved_release',source_release='starhome_lz_fr')
                overrides['definitions'].setdefault(item['id'],{})[mode] = restored
    for folder, rows in manifests.items():
        write_json(folder/'source_manifest.json',{'schema_version':1,'source_release':'starhome_lz_fr',
            'authorization':'2026-09-17 user explicitly selected free-release nano armor, monarch cannon and monarch chassis previews over jz alternatives','assets':rows})
    write_json(ROOT/'data/content/recovered_sprite_runtime_index_v1.json',index)
    write_json(ROOT/'data/presentation/recovered_equipment_v1.json',overrides)
    print('APPROVED_EQUIPMENT assets=%d definitions=%d' % (len(index['sprites']),len(overrides['definitions'])))


if __name__=='__main__':
    main()
