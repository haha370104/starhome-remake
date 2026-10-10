#!/usr/bin/env python3
"""Run one explicitly selected stage-0 performance scenario."""

from __future__ import annotations

import argparse
from datetime import date
import json
import os
from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[2]
SCENARIO_PATH = Path(__file__).with_name("baseline_scenarios.json")
DEFAULT_OUTPUT_DIR = ROOT / ".godot" / "performance"


def load_scenarios() -> dict:
    return json.loads(SCENARIO_PATH.read_text(encoding="utf-8"))


def build_command(args: argparse.Namespace, total_seconds: float) -> list[str]:
    command = [args.godot]
    if args.headless:
        command.append("--headless")
    command.extend(["--path", str(ROOT)])
    command.extend(["--script", args.script] if args.script else [args.scene])
    if args.extra_arg:
        command.append("--")
        command.extend(args.extra_arg)
    return command


def run_one(args: argparse.Namespace, profile: dict, scenario: dict) -> Path:
    output_dir = args.output_dir if args.output_dir.is_absolute() else ROOT / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = date.today().isoformat()
    output_path = output_dir / f"baseline_{stamp}_{args.mode}_{scenario['id']}.json"
    log_path = output_dir / f"baseline_{stamp}_{args.mode}_{scenario['id']}.log"
    total_seconds = float(args.warmup_seconds) + float(args.sample_seconds)
    environment = os.environ.copy()
    environment.update(
        {
            "STARHOME_PERFORMANCE": "1",
            "STARHOME_PERFORMANCE_OUTPUT": str(output_path),
            "STARHOME_PERFORMANCE_SCENARIO": scenario["id"],
            "STARHOME_PERFORMANCE_MAP_ID": profile["map_id"],
            "STARHOME_PERFORMANCE_MONSTER_COUNT": str(profile["monster_count"]),
            "STARHOME_PERFORMANCE_PLAYER_COUNT": str(profile["player_count"]),
            "STARHOME_PERFORMANCE_SERVER_MODE": args.mode,
            "STARHOME_PERFORMANCE_WARMUP_SECONDS": str(args.warmup_seconds),
            "STARHOME_PERFORMANCE_SAMPLE_SECONDS": str(args.sample_seconds),
            "STARHOME_PERFORMANCE_TOTAL_SECONDS": str(total_seconds),
        }
    )
    command = build_command(args, total_seconds)
    print("+", " ".join(command))
    with log_path.open("w", encoding="utf-8") as log_file:
        completed = subprocess.run(
            command,
            cwd=ROOT,
            env=environment,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            check=False,
        )
    if completed.returncode != 0:
        raise SystemExit(f"benchmark process failed ({completed.returncode}); see {log_path}")
    if not output_path.exists():
        raise SystemExit(f"performance report was not produced; see {log_path}")
    document = json.loads(output_path.read_text(encoding="utf-8"))
    document["metadata"]["scenario_label"] = scenario["label"]
    document["metadata"]["expected_configuration"] = {
        "map_id": profile["map_id"],
        "monster_count": profile["monster_count"],
        "player_count": profile["player_count"],
    }
    output_path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(output_path)
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scenario", choices=["all"] + [item["id"] for item in load_scenarios()["scenarios"]])
    parser.add_argument("--mode", choices=["inprocess", "dedicated"])
    parser.add_argument("--godot", default="godot")
    parser.add_argument("--scene", default="scenes/main_hall.tscn")
    parser.add_argument("--script")
    parser.add_argument("--headless", action="store_true")
    parser.add_argument("--warmup-seconds", type=float, default=10.0)
    parser.add_argument("--sample-seconds", type=float, default=40.0)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--extra-arg", action="append", default=[])
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args()
    profile = load_scenarios()
    if args.list:
        for scenario in profile["scenarios"]:
            print(f"{scenario['id']}\t{scenario['label']}")
        return
    if not args.scenario or not args.mode:
        parser.error("--scenario and --mode are required unless --list is used")
    scenarios = profile["scenarios"] if args.scenario == "all" else [
        next(item for item in profile["scenarios"] if item["id"] == args.scenario)
    ]
    for scenario in scenarios:
        run_one(args, profile, scenario)


if __name__ == "__main__":
    main()
