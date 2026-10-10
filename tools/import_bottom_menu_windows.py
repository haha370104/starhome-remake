"""按旧版帧元数据导入用户明确指定的底栏及任务、商城、系统窗口素材。"""
import hashlib
import json
from pathlib import Path
from PIL import Image
from recovery.source_workspace import RawSpriteWorkspace
from import_free_hud_assets import BOTTOM_MENU_BUTTONS, ImportSession, export_bottom_highlights

ROOT = Path(__file__).resolve().parents[1]
RAW_ROOT = ROOT / '../starhome_lz_fr_full' / 'raw'
DEST = ROOT / 'assets/ui/windows/navigation'
FRAME_BORDERS = ('top', 'buttom', 'left', 'right', 'lefttop', 'righttop',
                 'leftbutton', 'rightbuttom', 'maxform12', 'maxform13', 'maxform14')
SYSTEM_BUTTONS = ('font', 'setcolor', 'sethotkey', 'lookleaverword', 'music',
                  'help', 'speed', 'letter', 'exitsys')


def frame(workspace, audit, logical, index=0):
    """读取指定 ALE 帧及其原始锚点，记录可追溯来源。"""
    source_ref = logical + '.ale'
    directory, meta = workspace.decode(source_ref)
    row = meta['frames'][index]
    path = directory / meta['pages'][row['page']]
    with Image.open(path) as image:
        result = image.convert('RGBA').crop((row['x'], row['y'], row['x'] + row['width'], row['y'] + row['height']))
    audit.append({'source_release': 'starhome_lz_fr', 'source_logical_path': source_ref,
                  'source_frame': index, 'source_sha256': hashlib.sha256(workspace.source(source_ref).read_bytes()).hexdigest()})
    return result, (row.get('origin_x', 0), row.get('origin_y', 0))


def form(workspace, audit, name, width, height):
    """按 FormStyleMax 的边框坐标拼接固定像素通用窗口，不缩放角落素材。"""
    canvas = Image.new('RGBA', (width, height), (0, 0, 0, 245))
    def tile(asset, rect):
        image, _ = frame(workspace, audit, 'pic2/frompic/' + asset)
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
        image, _ = frame(workspace, audit, 'pic2/frompic/' + asset)
        canvas.alpha_composite(image, point)
    image, _ = frame(workspace, audit, 'pic2/frompic/maxform12')
    x = width//3
    canvas.alpha_composite(image, (x, 0))
    x += image.width
    tile('maxform14', (x, 0, width//3-37, 13))
    image, _ = frame(workspace, audit, 'pic2/frompic/maxform13')
    canvas.alpha_composite(image, (x + width//3-37, 0))
    canvas.save(DEST / (name + '.png'))


def build(workspace):
    """输出业务命名素材、布局清单及来源审计；不导入任何商城商品。"""
    audit = []
    assets = {}
    def record(name, start):
        sources = {(row['source_logical_path'], row['source_frame']): row for row in audit[start:]}
        assets[name] = {'texture': f'res://assets/ui/windows/navigation/{name}.png',
                        'sources': [sources[key] for key in sorted(sources)]}
    DEST.mkdir(parents=True, exist_ok=True)
    start = len(audit)
    form(workspace, audit, 'scene_players', 320, 450)
    record('scene_players', start)
    start = len(audit)
    form(workspace, audit, 'mission_journal', 250, 350)
    record('mission_journal', start)
    start = len(audit)
    form(workspace, audit, 'shop_confirmation', 300, 150)
    record('shop_confirmation', start)
    start = len(audit)
    image, origin = frame(workspace, audit, 'pic2/adornshopping/adorn_bg')
    image.save(DEST / 'premium_shop.png')
    record('premium_shop', start)
    start = len(audit)
    image, _ = frame(workspace, audit, 'pic2/ctrlpad/system_btn/newback')
    system = Image.new('RGBA', image.size)
    system.alpha_composite(image)
    for index, label in enumerate(SYSTEM_BUTTONS):
        image, offset = frame(workspace, audit, 'pic2/ctrlpad/system_btn/btn_' + label)
        system.alpha_composite(image, (9 + offset[0], 5 + index * 18 + offset[1]))
    system.save(DEST / 'system_menu.png')
    record('system_menu', start)
    hud_path = ROOT / 'data/ui/free_hud_assets.json'
    hud = json.loads(hud_path.read_text(encoding='utf-8'))
    buttons = {name: {'available': True, 'position': position} for name, position in BOTTOM_MENU_BUTTONS.items()}
    session = ImportSession(workspace)
    buttons['premium_shop'] = export_bottom_highlights(session)
    audit.extend({'source_release': 'starhome_lz_fr', 'source_logical_path': source['source_logical_path'],
                  'source_frame': index, 'source_sha256': source['source_ale_sha256']}
                 for source in session.sources.values() for index in range(source['source_frame_count']))
    hud['bottom_main']['menu_buttons'] = buttons
    hud_path.write_text(json.dumps(hud, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (ROOT / 'assets/ui/source_audit/bottom_menu_windows.json').write_text(json.dumps({
        'schema_version': 1, 'source_approval': '用户于 2026-09-07 指定免费版任务日志、商城和底栏系统交互；通用窗边框荣耀本地未找到，使用免费版回退',
        'shop_background_origin': origin, 'sources': audit,
    }, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (DEST / 'source_manifest.json').write_text(json.dumps({
        'schema_version': 1, 'assets': assets,
    }, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def main():
    required = [f'pic2/frompic/{name}.ale' for name in FRAME_BORDERS]
    required.extend(f'pic2/ctrlpad/system_btn/btn_{name}.ale' for name in SYSTEM_BUTTONS)
    required.extend(('pic2/adornshopping/adorn_bg.ale',
                     'pic2/ctrlpad/system_btn/newback.ale', 'pic2/ctrlpad/shopping.ale'))
    with RawSpriteWorkspace(RAW_ROOT) as workspace:
        workspace.require(required)
        build(workspace)


if __name__ == '__main__':
    main()
