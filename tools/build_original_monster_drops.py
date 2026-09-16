"""Import every original candidate; keep source evidence separate from remake probability."""
import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / "starhome_lz_ry_fcc_source"
RAW = ROOT.parent / "starhome_lz_ry_full/raw"
CRAWLERS = {"glory_monster_046", "glory_monster_114"}
FRAGMENT = "接合器升级碎片"
ALIASES = {
    "低级类胶": "low_grade_gel", "低级生物硅": "low_grade_biosilicon",
    "低级四足甲的壳": "low_grade_quadruped_shell", "低级能量催化剂": "low_grade_energy_catalyst",
    "低级能量包": "low_grade_energy_pack",
}
SEMANTIC = {
    "Activator2": "density_solvent", "ColourfulCrystal": "five_color_crystal",
    "DCProtecter": "electromagnetic_protector", "DJBJJ": "electric_wave_crystal",
    "DJBXP": "electric_wave_chip", "DJSteelChip": "frozen_steel_plate",
    "ElectronicZX": "electronic_control_chip", "HSRifling": "blackstone_rifling",
    "HongCrystal": "red_crystal_source", "LanCrystal": "blue_crystal_source",
    "LvCrystal": "green_crystal_source", "ZiCrystal": "purple_crystal_source",
    "JMCFQ_G91": "g91_precision_trigger", "MorColourfulCrystal": "seven_color_crystal",
    "NewJointImpactChip": "impact_crystal", "QuantumElement": "quantum_element",
    "RYRimeFragment": "socket_crystal_fragment", "TGSteelChip": "iron_hook_steel_plate",
    "TLPHSuspension": "gyroscopic_suspension", "TZNLY_G91": "g91_energy_source",
    "TZNLY_G92": "g92_energy_source", "TurbineWDQ": "turbine_stabilizer",
    "WXSteelChip": "five_element_steel_plate", "XingCiCrystal": "stellar_magnetic_crystal",
    "XingGuangCrystal": "starlight_crystal", "XingHuiCrystal": "stellar_radiance_crystal",
    "XingYaoCrystal": "stellar_brilliance_crystal", "XingYuanCrystal": "stellar_source_crystal",
    "YHOfInterstellar": "crystal_moon_mark", "YHOfInterstellar_Frag": "crystal_moon_fragment",
    "ZNGJTimeCard15": "assistant_time_card_15min", "ZWFibar": "megawatt_fiber",
    "new002": "thermal_crystal", "new003": "corrosive_crystal", "new004": "magnetic_crystal",
    "new005": "thermal_chip", "new006": "corrosive_chip", "new007": "magnetic_chip",
    "中级能量包": "middle_grade_energy_pack", "传感器": "sensor", "动力板": "power_board",
    "变接器": "adapter", "扩充器": "capacity_expander", "扩流器1": "flow_expander",
    "撒玛合金5": "sama_upgrade_alloy", "火力元件": "firepower_component",
    "热敏电阻": "thermistor", "聚能晶片5": "energy_focusing_chip", "超磁体1": "super_magnet",
}
for source, semantic in list(SEMANTIC.items()):
    if source in ["HongCrystal", "LanCrystal", "LvCrystal", "ZiCrystal"]:
        SEMANTIC["Top" + source] = "high_grade_" + semantic
for index, kind in enumerate(["firepower", "health", "defense", "guidance", "critical", "rocket"], 1001):
    SEMANTIC[f"RYRime:0 {index} 0"] = f"flawed_{kind}_crystal"
for index in range(1, 4):
    SEMANTIC[f"JiJiaFuShuJingTi{index}"] = f"mech_auxiliary_crystal_{index}"
    SEMANTIC[f"JiJiaYueHuiJingTi{index}"] = f"mech_moonlight_crystal_{index}"


def read(path):
    return json.loads((ROOT / path).read_text("utf-8-sig"))


def write(path, data):
    (ROOT / path).write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def item_ids():
    result = {row["display_name"]: row["id"] for row in read("data/gameplay/glory/glory_items_v1.json")["definitions"]}
    result.update(ALIASES)
    return result


def build_drops():
    """One independent roll per species/item; original weight is deliberately not interpreted."""
    ids = item_ids()
    rows = []
    for monster in read("data/gameplay/glory/glory_monsters_v1.json")["definitions"]:
        grouped = {}
        for candidate in monster["source_drop_candidates"]:
            name = candidate["display_name"]
            if name == FRAGMENT:
                continue
            item_id = ids[name]
            entry = grouped.setdefault(item_id, dict(item_definition_id=item_id,
                minimum_quantity=candidate["minimum_quantity"], maximum_quantity=candidate["maximum_quantity"], chance=0.25))
            entry["minimum_quantity"] = min(entry["minimum_quantity"], candidate["minimum_quantity"])
            entry["maximum_quantity"] = max(entry["maximum_quantity"], candidate["maximum_quantity"])
        if monster["id"] in CRAWLERS:
            grouped[ids[FRAGMENT]] = dict(item_definition_id=ids[FRAGMENT], minimum_quantity=1, maximum_quantity=3, chance=0.75)
        rows.append(dict(monster_id=monster["id"], display_name=monster["display_name"], drops=list(grouped.values())))
    document = dict(schema_version=1, content_version="original-monster-drops-v1", mode="replace",
        source_audit=dict(source_release="starhome_lz_ry", source_catalog="glory/glory_monsters_v1.json",
            policy="2026-09-16 user approved all candidates with uniform remake 25% probability; original raw_weight unconfirmed",
            duplicate_policy="one roll per species/item; min/max envelope of original quantities",
            fragment_policy="only crawler 046 and forgotten crawler 114 plus variants; uniform 0..3, E=1.5"), definitions=rows)
    # Generated records stay one drop per line, so reviewers can compare each relationship directly.
    header = json.dumps({k: v for k, v in document.items() if k != "definitions"}, ensure_ascii=False, indent=2)[:-2]
    lines = [header + ',', '  "definitions": [']
    for index, row in enumerate(rows):
        lines += ['    {', f'      "monster_id": "{row["monster_id"]}", "display_name": '
                  + json.dumps(row['display_name'], ensure_ascii=False) + ',', '      "drops": [']
        lines += ['        ' + json.dumps(drop, ensure_ascii=False) + (',' if i < len(row['drops'])-1 else '')
                  for i, drop in enumerate(row['drops'])]
        lines += ['      ]', '    }' + (',' if index < len(rows)-1 else '')]
    lines += ['  ]', '}']
    (ROOT / "data/gameplay/original_monster_drops_v1.json").write_text('\n'.join(lines) + '\n', encoding='utf-8')
    assert read("data/gameplay/original_monster_drops_v1.json") == document
    print(f"ORIGINAL_DROPS_BUILT species={len(rows)} relationships={sum(len(r['drops']) for r in rows)}")


def source_classes():
    """Read source as text only; no original code is evaluated."""
    classes, strings = {}, {}
    for path in sorted(SOURCE.rglob("*.fcc")):
        text = path.read_text("utf-8-sig")
        strings.update(re.findall(r'^\s*#define\s+(\w+)\s+"([^"\n]*)"', text, re.M))
        matches = list(re.finditer(r'^\s*class\s+(\w+)\s*:\s*(\w+)', text, re.M))
        for index, match in enumerate(matches):
            body = text[match.end():matches[index+1].start() if index+1 < len(matches) else len(text)]
            body = re.sub(r'/\*.*?\*/|//[^\n]*', '', body, flags=re.S)
            classes.setdefault(match[1], []).append(dict(parent=match[2], body=body,
                source_file=path.relative_to(SOURCE).as_posix(), source_line=text[:match.start()].count('\n')+1))
    return classes, strings


def enrich_items():
    """Recover Chinese names, source icons and constructor-specific crystals for all 79 candidates."""
    from PIL import Image
    from audit_monster_asset_sources import load_decoder, decode_index_alpha, apply_palette, file_hash
    from import_glory_drop_materials import act_colors
    classes, strings = source_classes()
    ids = item_ids()
    monsters = read("data/gameplay/glory/glory_monsters_v1.json")["definitions"]
    names = sorted({drop['display_name'] for monster in monsters for drop in monster['source_drop_candidates']})
    original = {row['id']: row for row in read("data/gameplay/glory/glory_items_v1.json")['definitions']}
    presentation = read("data/presentation/ground_loot_v1.json")
    decoder = load_decoder()
    definitions, manifest, images = [], [], []

    def field(body, key):
        match = re.search(r'\b' + key + r'\s*=\s*([^;]+);', body)
        if not match:
            return ''
        value = match[1].strip()
        return strings.get(value, value)

    def clean(value):
        return re.sub(r'\\#[0-9a-fA-F]{6}', '', value.strip('"')).replace('\\r\\n', '\n')

    for raw_name in names:
        class_name = raw_name.split(':')[0]
        assert len(classes.get(class_name, [])) == 1, raw_name
        source = classes[class_name][0]
        body = source['body']
        name = clean(field(body, 'm_sObjName'))
        description = clean(field(body, 'm_sDesc'))
        sprite_expr = field(body, 'src')
        if class_name == 'RYRime':
            crystal_type = raw_name.split()[1]
            case = re.search(r'case\s+' + crystal_type + r'\s*:(.*?)(?:break;)', body, re.S)[1]
            name = clean(field(case, 'm_sObjName'))
            description = '原版镶嵌晶石。镶嵌系统尚未开放，当前可拾取并保留。'
            sprite_path = f'pic3/stuff/RYRime{crystal_type}.ale'
        else:
            sprite_path = re.search(r'"\.\./([^"\n]+\.ale)"', sprite_expr)[1]
        palette_expr = field(body, 'linkpalette')
        palette = re.search(r'"\.\./([^"\n]+\.act)"', palette_expr)[1] if palette_expr else ''
        item_id = ids[raw_name]
        audit = dict(source_release='starhome_lz_ry', source_class=raw_name,
                     source_file=source['source_file'], source_line=source['source_line'],
                     source_logical_path=sprite_path, source_sha256=file_hash(RAW / sprite_path, 'sha256'),
                     source_palette=palette, source_palette_sha256=file_hash(RAW / palette, 'sha256') if palette else '')
        if raw_name not in ALIASES and raw_name != 'NewJointImpactChip':
            old = original[item_id]
            assert old['source_audit']['status'] == 'name_only', item_id
            definitions.append(dict(id=item_id, kind='material', display_name=name, description=description,
                max_stack=old['max_stack'], replaces_name_only=True, source_class=raw_name,
                source_audit=dict(audit, status='client_confirmed')))
        existing = presentation['definitions'].get(item_id, {})
        if existing.get('world', {}).get('texture', '').endswith('.png'):
            audit['resource'] = existing['world']['texture']
        else:
            semantic = SEMANTIC[raw_name]
            ale = decoder.AleFile(RAW / sprite_path)
            frame = ale.frames[0]
            image = apply_palette(decode_index_alpha(ale, frame), act_colors(RAW / palette)) if palette else ale.decode_frame(frame)
            assert image.getbbox(), sprite_path
            crop = image.getbbox()
            image = image.crop(crop)
            resource = f'res://assets/items/materials/{semantic}/icon.tres'
            audit.update(resource=resource, source_frame=0, source_frame_count=len(ale.frames), source_crop=list(crop))
            images.append((image, resource, audit))
            presentation['definitions'][item_id] = dict(display_name=name,
                world=dict(texture=resource, native_size=list(image.size), origin=[frame.origin_x+crop[0], frame.origin_y+crop[1]]),
                inventory=dict(icon=resource, native_size=list(image.size)))
        audit.update(item_definition_id=item_id, display_name=name)
        manifest.append(audit)
    # Pack in stable batches: each atlas and its regions are independently reviewable assets.
    for batch_start in range(0, len(images), 14):
        batch = images[batch_start:batch_start+14]
        cell_w = max(image.width for image, _, _ in batch) + 4
        cell_h = max(image.height for image, _, _ in batch) + 4
        atlas = Image.new('RGBA', (cell_w * 7, cell_h * 2))
        relative = f'assets/items/materials/drop_atlases/batch_{batch_start//14 + 1}'
        atlas_path = ROOT / (relative + '.png')
        atlas_path.parent.mkdir(parents=True, exist_ok=True)
        for index, (image, resource, audit) in enumerate(batch):
            x, y = (index % 7) * cell_w + 2, (index // 7) * cell_h + 2
            atlas.paste(image, (x, y))
            target = ROOT / resource.removeprefix('res://')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                f'[ext_resource type="Texture2D" path="res://{relative}.png" id="1"]\n\n'
                f'[resource]\natlas = ExtResource("1")\nregion = Rect2({x}, {y}, {image.width}, {image.height})\n'
                'filter_clip = true\n', encoding='utf-8')
            audit['atlas_region'] = [x, y, image.width, image.height]
        atlas.save(atlas_path)
        write(relative + '.json', dict(source_release='starhome_lz_ry', definitions=[a for _, _, a in batch]))
    write('data/gameplay/original_drop_items_v1.json', dict(schema_version=1, definitions=definitions))
    write('data/presentation/ground_loot_v1.json', presentation)
    write('data/gameplay/original_drop_bindings_v1.json', dict(schema_version=1, definitions=manifest))
    print(f'ORIGINAL_DROP_ITEMS names={len(names)} enriched={len(definitions)} restored_icons={len(images)}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--items', action='store_true')
    args = parser.parse_args()
    if args.items:
        enrich_items()
    else:
        build_drops()
