"""Run isolated, sequential D04 CPU scenarios; never open the everyday save."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--scenarios', nargs='+', default=['standing', 'moving', 'firing', 'mining', 'replenishment'],
                        choices=['standing', 'moving', 'firing', 'mining', 'replenishment'])
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve() / time.strftime('%Y%m%d-%H%M%S')
    output.mkdir(parents=True, exist_ok=False)
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    dirty = bool(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root, text=True).strip())
    results = []
    for scenario in args.scenarios:
        profile = output / ('profile-' + scenario)
        profile.mkdir()
        report = output / (scenario + '.json')
        env = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile), XDG_DATA_HOME=str(profile),
                   XDG_CONFIG_HOME=str(profile), STARHOME_COMBAT_TRACE='0', STARHOME_PERFORMANCE='0',
                   STARHOME_BENCHMARK_ISOLATED='1', STARHOME_PERFORMANCE_SCENARIO=scenario,
                   STARHOME_PERFORMANCE_OUTPUT=str(report), STARHOME_BENCHMARK_REVISION=revision,
                   STARHOME_BENCHMARK_DIRTY='1' if dirty else '0')
        run = subprocess.run([args.godot, '--headless', '--path', str(root), '--log-file',
                              str(output / (scenario + '.engine.log')), '--script',
                              'res://tools/performance/server_scenarios.gd'], cwd=root, env=env,
                             capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=180)
        text = run.stdout + run.stderr
        (output / (scenario + '.log')).write_text(text, encoding='utf-8')
        errors = [line for line in text.splitlines() if ('SCRIPT ERROR:' in line or line.startswith('ERROR:'))
                  and 'Failed to read the root certificate store' not in line]
        result = {'scenario': scenario, 'exit': run.returncode, 'errors': errors, 'report': str(report)}
        results.append(result)
        print(json.dumps(result, ensure_ascii=False), flush=True)
    (output / 'runs.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
    return int(any(row['exit'] or row['errors'] or not Path(row['report']).is_file() for row in results))


if __name__ == '__main__':
    raise SystemExit(main())
