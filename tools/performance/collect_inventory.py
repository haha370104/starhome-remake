#!/usr/bin/env python3
"""Create the stage-0 test, runtime-resource, and cache inventories."""

from __future__ import annotations

import argparse
from collections import defaultdict
from datetime import date
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT_DIR = ROOT / ".godot" / "performance"
SCENARIO_FILE = Path(__file__).with_name("baseline_scenarios.json")
RES_PATH_PATTERN = re.compile(r"res://([^\"']+)")


def tree_stats(path: Path) -> dict[str, int | bool]:
    if not path.exists():
        return {"exists": False, "files": 0, "bytes": 0}
    if path.is_file():
        return {"exists": True, "files": 1, "bytes": path.stat().st_size}
    files = [item for item in path.rglob("*") if item.is_file()]
    return {"exists": True, "files": len(files), "bytes": sum(item.stat().st_size for item in files)}


def parse_registered_tests() -> set[str]:
    registered: set[str] = set()
    for source_path in (ROOT / "tools" / "run_project_checks.ps1", ROOT / "tools" / "run_client_checks.py"):
        if not source_path.exists():
            continue
        text = source_path.read_text(encoding="utf-8", errors="replace")
        for match in re.finditer(r"(?:res://)?tests/([^\"'\s,)]+\.gd)", text):
            registered.add("tests/" + match.group(1).replace("\\", "/"))
    return registered


def find_missing_resource_references(test_path: Path) -> list[str]:
    missing: list[str] = []
    text = test_path.read_text(encoding="utf-8", errors="replace")
    for reference in RES_PATH_PATTERN.findall(text):
        if not reference.startswith(("tests/", "scripts/", "data/", "assets/", "scenes/")):
            continue
        if not (ROOT / reference).exists():
            missing.append(reference)
    return sorted(set(missing))


def build_inventory() -> tuple[dict, str]:
    test_paths = sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "tests").rglob("*.gd")
        if path.is_file()
    )
    registered = parse_registered_tests()
    uid_only = sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "tests").rglob("*.gd.uid")
        if path.is_file() and not path.with_suffix("").exists()
    )
    by_name: dict[str, list[str]] = defaultdict(list)
    for path in test_paths:
        by_name[Path(path).name].append(path)
    duplicate_basenames = {
        name: paths for name, paths in sorted(by_name.items()) if len(paths) > 1
    }
    invalid_candidates = {}
    for path in test_paths:
        missing = find_missing_resource_references(ROOT / path)
        if missing:
            invalid_candidates[path] = missing
    scenarios = json.loads(SCENARIO_FILE.read_text(encoding="utf-8"))["scenarios"]
    all_test_text = "\n".join(
        (ROOT / path).read_text(encoding="utf-8", errors="replace") for path in test_paths
    ).lower()
    uncovered = []
    scenario_terms = {
        "standing": ("standing", "idle", "静止"),
        "moving": ("movement", "moving", "移动"),
        "firing": ("firing", "combat", "开火"),
        "mining": ("mining", "采矿"),
        "spawning": ("population", "spawn", "刷怪"),
        "autosave_due": ("autosave", "存档"),
    }
    for scenario in scenarios:
        if not any(term in all_test_text for term in scenario_terms[scenario["id"]]):
            uncovered.append(scenario)
    inventory = {
        "schema_version": 1,
        "generated_on": date.today().isoformat(),
        "tests": {
            "all_sources": test_paths,
            "registered_in_default_gates": sorted(registered),
            "not_registered_in_default_gates": sorted(set(test_paths) - registered),
            "uid_without_source": uid_only,
            "duplicate_basenames": duplicate_basenames,
            "static_invalid_reference_candidates": invalid_candidates,
            "runtime_status": "not_run_by_inventory_tool",
        },
        "performance_scenario_gaps": uncovered,
    }
    markdown = render_markdown(inventory)
    return inventory, markdown


def render_markdown(inventory: dict) -> str:
    tests = inventory["tests"]
    lines = [
        "# 阶段 0 测试清单",
        "",
        f"生成日期：`{inventory['generated_on']}`。本清单是静态盘点，不把历史通过记录当作当前通过。",
        "",
        "## 汇总",
        f"- 测试源码：`{len(tests['all_sources'])}`",
        f"- 已列入默认门禁：`{len(tests['registered_in_default_gates'])}`（本次未执行）",
        f"- 未列入默认门禁：`{len(tests['not_registered_in_default_gates'])}`",
        f"- 只有 `.uid` 没有源码：`{len(tests['uid_without_source'])}`",
        f"- 重复文件名组：`{len(tests['duplicate_basenames'])}`",
        f"- 静态失效引用候选：`{len(tests['static_invalid_reference_candidates'])}`",
        "",
        "## 默认门禁条目",
        "以下条目被默认检查脚本引用，但本清单不宣称它们本次运行通过：",
    ]
    lines.extend(f"- `{path}`" for path in tests["registered_in_default_gates"])
    lines.extend(["", "## 未注册条目"])
    lines.extend(f"- `{path}`" for path in tests["not_registered_in_default_gates"])
    lines.extend(["", "## 静态失效候选"])
    if tests["static_invalid_reference_candidates"]:
        for path, references in tests["static_invalid_reference_candidates"].items():
            lines.append(f"- `{path}`：缺失引用 `{', '.join(references)}`")
    else:
        lines.append("- 未发现缺失 `res://` 引用；仍需运行时验证。")
    lines.extend(["", "## 重复覆盖候选"])
    if tests["duplicate_basenames"]:
        for name, paths in tests["duplicate_basenames"].items():
            lines.append(f"- `{name}`：" + "、".join(f"`{path}`" for path in paths))
    else:
        lines.append("- 未发现重复文件名。")
    lines.extend(["", "## 阶段 0 场景未覆盖候选"])
    if inventory["performance_scenario_gaps"]:
        lines.extend(f"- `{item['id']}`：{item['label']}" for item in inventory["performance_scenario_gaps"])
    else:
        lines.append("- 静态文本中均有相关词；仍需固定基准入口实测。")
    lines.extend(["", "## 状态定义", "- `registered`：被默认门禁引用，不等于本次已通过。", "- `static_invalid_reference_candidate`：仅依据源码引用缺失推断，需单独复现。", "- `duplicate`：文件名重复，不能据此认定行为重复。", "- `uncovered`：未发现现有测试文本覆盖，需在性能基准或后续阶段补齐。"])
    return "\n".join(lines) + "\n"


def build_resource_manifest() -> dict:
    runtime_manifest = ROOT / "data" / "content" / "content_materialization_manifest_v1.json"
    catalogs = sorted(
        path.relative_to(ROOT).as_posix()
        for path in (ROOT / "data" / "content").glob("*.json")
        if path.is_file()
    )
    cache_paths = [
        ROOT / ".godot",
        ROOT / ".godot" / "imported",
        ROOT / ".godot" / "editor",
        ROOT / ".godot" / "uid_cache.bin",
    ]
    return {
        "schema_version": 1,
        "generated_on": date.today().isoformat(),
        "runtime_namespace": "res://assets/",
        "runtime_content": tree_stats(ROOT / "assets"),
        "godot_cache": tree_stats(ROOT / ".godot"),
        "runtime_manifest": {
            "path": runtime_manifest.relative_to(ROOT).as_posix(),
            "stats": tree_stats(runtime_manifest),
        },
        "runtime_catalogs": [{"path": path, "stats": tree_stats(ROOT / path)} for path in catalogs],
        "cache_subtrees": [{"path": path.relative_to(ROOT).as_posix(), "stats": tree_stats(path)} for path in cache_paths],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    args = parser.parse_args()
    output_dir = args.output_dir if args.output_dir.is_absolute() else ROOT / args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    stamp = date.today().isoformat()
    inventory, markdown = build_inventory()
    (output_dir / f"test_inventory_{stamp}.json").write_text(
        json.dumps(inventory, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    (output_dir / f"test_inventory_{stamp}.md").write_text(markdown, encoding="utf-8")
    resource_manifest = build_resource_manifest()
    (output_dir / f"resource_manifest_{stamp}.json").write_text(
        json.dumps(resource_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(output_dir / f"test_inventory_{stamp}.md")
    print(output_dir / f"resource_manifest_{stamp}.json")


if __name__ == "__main__":
    main()
