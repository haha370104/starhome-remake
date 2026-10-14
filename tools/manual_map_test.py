"""Launch recovered maps with a separate test profile and the real game session."""
from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def maps() -> list[dict]:
    """Read names and IDs from the audited supplement rather than duplicate them."""
    audit = json.loads((ROOT / 'data/content/glory_map_recovery_20261014.json').read_text(encoding='utf-8'))
    with zipfile.ZipFile(ROOT / 'assets/content_packs/glory_maps_recovered_20261014.zip') as archive:
        return [json.loads(archive.read(f"content/glory/map_definitions/{row['runtime_id']}.json"))
                for row in audit['maps'].values()]


def find_godot(explicit: str | None) -> Path:
    """Prefer the supplied executable or PATH; recognize a local Windows download."""
    requested = explicit or os.environ.get('GODOT_EXECUTABLE')
    if requested:
        path = Path(shutil.which(requested) or requested).expanduser()
        if not path.is_file():
            raise FileNotFoundError(f'Godot 不存在：{path}')
        return path.resolve()
    for name in ('godot', 'godot4'):
        found = shutil.which(name)
        if found:
            return Path(found)
    candidates = list((Path.home() / 'Downloads').glob('Godot_v*_win64_console.exe'))
    if len(candidates) == 1:
        return candidates[0]
    raise FileNotFoundError('请通过 --godot 指定 Godot 可执行文件；存在多个版本时不自动选择。')


def launch(godot: Path, row: dict, verify: bool, capture: bool) -> int:
    """Run a fresh disposable profile, keeping settings and player saves isolated."""
    run = ROOT / '.godot/manual-map-tests' / datetime.now().strftime('%Y%m%d-%H%M%S-%f')
    profile = run / 'profile'
    profile.mkdir(parents=True)
    env = dict(os.environ)
    for key in ('APPDATA', 'LOCALAPPDATA', 'XDG_DATA_HOME', 'XDG_CONFIG_HOME'):
        env[key] = str(profile)
    command = [str(godot), '--path', str(ROOT), '--log-file', str(run / 'engine.log')]
    if verify and not capture:
        command.append('--headless')
    command += ['--script', 'res://tools/manual_map_test.gd', '--', f"--map-id={row['map_id']}"]
    if verify:
        command.append('--verify')
    if capture:
        command.append('--capture')
    print(f"\n进入 {row['display_name']}；独立测试目录：{run}", flush=True)
    return subprocess.run(command, cwd=ROOT, env=env, check=False).returncode


def main() -> int:
    """Offer numbered maps, reopening the selector after the game closes."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', help='Godot 可执行文件路径；也可设置 GODOT_EXECUTABLE')
    parser.add_argument('--map', help='地图序号或完整 runtime_id；省略时循环选图')
    parser.add_argument('--list', action='store_true', help='只显示可测试地图')
    parser.add_argument('--verify', action='store_true', help='验证真实连接、移动、原有出口和正常退出')
    parser.add_argument('--capture', action='store_true', help='启动后截取 GPU 画面，配合 --verify 使用')
    args = parser.parse_args()
    if (args.verify or args.capture) and not args.map:
        parser.error('--verify / --capture 需要 --map')
    rows = maps()
    for index, row in enumerate(rows, 1):
        print(f"{index}. {row['display_name']} [{row['map_id']}]，出口 {len(row['transitions'])} 个")
    if args.list:
        return 0
    godot = find_godot(args.godot)
    while True:
        choice = args.map or input('\n输入地图序号（关闭游戏可再次选择，q 结束）：').strip()
        if choice.lower() == 'q':
            return 0
        selected = next((row for index, row in enumerate(rows, 1)
                         if choice in (str(index), row['map_id'])), None)
        if selected is None:
            if args.map:
                parser.error('地图不在本次补齐清单中')
            print('请选择上面列出的序号。')
            continue
        result = launch(godot, selected, args.verify, args.capture)
        if args.map:
            return result
        if result:
            print(f'本次运行异常退出（{result}），请保留上面的 engine.log。')


if __name__ == '__main__':
    try:
        raise SystemExit(main())
    except (FileNotFoundError, zipfile.BadZipFile) as error:
        raise SystemExit(f'{error}\n请确认 assets 子模块及 LFS 内容已下载完整。') from error
