"""按旧版帧元数据导入用户明确指定的底栏及任务、商城、系统窗口素材。"""
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'starhome_lz_fr_full_parsed' / 'ale_sprites'
DEST = ROOT / 'assets/ui/windows/navigation'
AUDIT = []


def frame(logical, index=0):
    """读取指定 ALE 帧及其原始锚点，记录可追溯来源。"""
    directory = SOURCE / logical
    meta = json.loads((directory / 'frames.json').read_text(encoding='utf-8'))
    row = meta['frames'][index]
    path = directory / meta['pages'][row['page']]
    with Image.open(path) as image:
        result = image.convert('RGBA').crop((row['x'], row['y'], row['x'] + row['width'], row['y'] + row['height']))
    AUDIT.append({'source_release': 'starhome_lz_fr', 'source_logical_path': logical + '.ale',
                  'source_frame': index, 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    return result, (row.get('origin_x', 0), row.get('origin_y', 0))


def form(name, width, height):
    """按 FormStyleMax 的边框坐标拼接固定像素通用窗口，不缩放角落素材。"""
    canvas = Image.new('RGBA', (width, height), (0, 0, 0, 245))
    def tile(asset, rect):
        image, _ = frame('pic2/frompic/' + asset)
        x, y, w, h = rect
        patch = Image.new('RGBA', (w, h))
        for px in range(0, w, image.width):
            for py in range(0, h, image.height):
                patch.alpha_composite(image, (px, py))
        canvas.alpha_composite(patch, (x, y))
    for asset, rect in [('top', (28, 0, width-50, 12)), ('buttom', (28, height-8, width-45, 8)),
                        ('left', (0, 10, 8, height-30)), ('right', (width-9, 20, 8, height-30))]:
        tile(asset, rect)
    for asset, point in [('lefttop', (0, 0)), ('righttop', (width-30, 0)),
                         ('leftbutton', (0, height-28)), ('rightbuttom', (width-30, height-28))]:
        image, _ = frame('pic2/frompic/' + asset)
        canvas.alpha_composite(image, point)
    image, _ = frame('pic2/frompic/maxform12')
    x = width//3
    canvas.alpha_composite(image, (x, 0))
    x += image.width
    tile('maxform14', (x, 0, width//3-37, 13))
    image, _ = frame('pic2/frompic/maxform13')
    canvas.alpha_composite(image, (x + width//3-37, 0))
    canvas.save(DEST / (name + '.png'))


def main():
    """输出业务命名素材、布局清单及来源审计；不导入任何商城商品。"""
    DEST.mkdir(parents=True, exist_ok=True)
    form('scene_players', 320, 450)
    form('mission_journal', 250, 350)
    form('shop_confirmation', 300, 150)
    image, origin = frame('pic2/adornshopping/adorn_bg')
    image.save(DEST / 'premium_shop.png')
    image, _ = frame('pic2/ctrlpad/system_btn/newback')
    system = Image.new('RGBA', image.size)
    system.alpha_composite(image)
    labels = ['font', 'setcolor', 'sethotkey', 'lookleaverword', 'music', 'help', 'speed', 'letter', 'exitsys']
    for index, label in enumerate(labels):
        image, offset = frame('pic2/ctrlpad/system_btn/btn_' + label)
        system.alpha_composite(image, (9 + offset[0], 5 + index * 18 + offset[1]))
    system.save(DEST / 'system_menu.png')
    hud_path = ROOT / 'data/ui/free_hud_assets.json'
    hud = json.loads(hud_path.read_text(encoding='utf-8'))
    buttons = hud['bottom_main']['menu_buttons']
    buttons.pop('star_map', None)
    states, origins, sizes = {}, {}, {}
    for index, state in enumerate(['normal', 'hover', 'pressed']):
        image, point = frame('pic2/ctrlpad/shopping', index)
        path = ROOT / 'assets/ui/free_hud/bottom_main/menu_buttons/premium_shop' / (state + '.png')
        path.parent.mkdir(parents=True, exist_ok=True)
        image.save(path)
        states[state] = 'res://' + path.relative_to(ROOT).as_posix()
        origins[state], sizes[state] = list(point), list(image.size)
    buttons['premium_shop'] = {'available': True, 'states': states, 'state_origins': origins, 'state_sizes': sizes}
    buttons['achievements'] = {
        'available': True,
        'states': {state: 'res://assets/ui/free_hud/bottom_main/menu_buttons/achievement_icon.tres' for state in states},
        'state_origins': {state: [0, 0] for state in states},
        'state_sizes': {state: [31, 29] for state in states},
    }
    for index, key in enumerate(['character', 'inventory', 'vehicle_equipment', 'friends', 'scene_players', 'missions', 'system', 'achievements', 'premium_shop']):
        buttons[key]['position'] = [519 + index * 38, 0]
    hud_path.write_text(json.dumps(hud, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (ROOT / 'assets/ui/source_audit/bottom_menu_windows.json').write_text(json.dumps({
        'schema_version': 1, 'source_approval': '用户于 2026-09-07 指定免费版任务日志、商城和底栏系统交互；通用窗边框荣耀本地未找到，使用免费版回退',
        'shop_background_origin': origin, 'sources': AUDIT,
    }, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


if __name__ == '__main__':
    main()
