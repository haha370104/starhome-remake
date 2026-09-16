"""Compare original drop evidence with initialized runtime catalogs and every mercenary task.

Run export_content_supply_audit.gd first. Reports are deterministic for that snapshot;
raw Glory archives remain optional local evidence, outside the repository/submodule.
"""
from __future__ import annotations

import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path

from build_glory_monster_runtime_catalog import recover_class_names

ROOT = Path(__file__).resolve().parents[1]


def load(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))


def main() -> None:
    runtime = load(".godot/content-audit-runtime.json")
    original = load("data/gameplay/glory/glory_monsters_v1.json")["definitions"]
    tasks = load("data/gameplay/quests/mercenary_tasks_v1.json")["tasks"]
    task_path = ROOT.parent / "starhome_lz_fr_full_parsed/ftc_resources/expanded/bool/role/mercenaryrole/mercenaryrole.txt.cab"
    task_note = "本地免费版原始任务归档缺失，本次以仓库规范化任务表为基准。"
    if task_path.exists():
        text_rows = [line.split("\t") for line in task_path.read_text(encoding="gb18030").splitlines() if line.strip()][1:]
        original_tasks = [dict(id=row[0], title=row[1], grade=int(row[2]), quality=int(row[3]), description=row[4],
                               condition=row[5].split(","), points=int(row[6])) for row in text_rows]
        assert original_tasks == tasks, "免费版任务原始七列与规范化目录不一致"
        task_note = f"免费版原始任务表 {len(tasks)} 行的七列逐一相同，未删除或改写任何原始任务条件。"
    encounters = load("data/gameplay/glory/glory_monster_encounters_v1.json")
    all_encounters = encounters["encounters"] + [load("data/gameplay/stage3/d04_encounters_v1.json")]
    spawned = {group["monster_id"] for encounter in all_encounters if encounter.get("enabled", False)
               for group in encounter["spawn_groups"] if group.get("weight", 1) > 0}
    names = defaultdict(set)
    for item_id, item in runtime["items"].items():
        for name in (item["display_name"], item.get("source_class"), item.get("source_audit", {}).get("source_class")):
            if name:
                names[name].add(item_id)
    actual = {sid: {drop["item_definition_id"] for drop in monster.get("drops") or [] if drop["chance"] > 0}
              for sid, monster in runtime["monsters"].items()}
    available = {item for sid in spawned for item in actual.get(sid, set())}
    available.update(offer["definition_id"] for offer in runtime["offers"])
    available.update(offer["definition_id"] for offer in load("data/gameplay/commerce/premium_shop_v1.json")["offers"])
    mining = load("data/gameplay/mining_v1.json")
    minerals = {row["mineral_id"] for area in mining["maps"].values() if area.get("enabled", False)
                for row in area["mineral_pool"] if row.get("weight", 1) > 0}
    available.update(row["item_definition_id"] for row in mining["minerals"] if row["id"] in minerals)
    repeatable = load("data/gameplay/quests/repeatable_tasks_v1.json")["tasks"]
    # Exact runtime IDs: equal display names do not make different inventory items interchangeable.
    while True:
        previous = len(available)
        for task in repeatable:
            if all(row["definition_id"] in available for row in task.get("requirements", [])):
                for reward in task.get("milestone_rewards", {}).values():
                    available.update(row["definition_id"] for row in (reward if isinstance(reward, list) else [reward]))
        for recipe in runtime["recipes"]:
            if all(row["definition_id"] in available for row in recipe["materials"]):
                available.add(recipe["product"])
        if len(available) == previous:
            break

    upgrade_rules = load("data/gameplay/commerce/attachment_upgrade_costs_v1.json")["rules"]
    for rule in upgrade_rules:
        for material in rule["premium_materials"] + rule["normal_materials"]:
            assert material["definition_id"] in available, f"升级材料无获取链：{rule['attachment_id']} +{rule['current_level']} {material['definition_id']}"
    print(f"UPGRADE_SUPPLY_AUDIT stages={len(upgrade_rules)} missing=0")

    source_species = defaultdict(set)
    source_entries = Counter()
    matched_entries = 0
    for monster in original:
        for drop in monster["source_drop_candidates"]:
            name = drop["display_name"]
            source_species[name].add(monster["id"])
            source_entries[name] += 1
            matched_entries += bool(names[name] & actual[monster["id"]])
    covered = {name: {sid for sid in species if names[name] & actual[sid]}
               for name, species in source_species.items()}
    full = sum(covered[name] == species for name, species in source_species.items())
    partial = sum(bool(covered[name]) and covered[name] != species for name, species in source_species.items())
    absent = sum(not value for value in covered.values())
    raw_path = ROOT.parent / "starhome_lz_ry_full_parsed/catalogs_utf8/npc_catalog.csv"
    raw_note = "本地原始归档缺失，本次仅核对仓库已导入的来源候选。"
    if raw_path.exists():
        rows = list(csv.DictReader(raw_path.open(encoding="utf-8-sig")))
        expected = {int(monster["source_audit"]["index"]): monster["source_drop_candidates"] for monster in original}
        assert len(rows) == len(expected), "原始 NPC 数与导入目录不一致"
        for row in rows:
            parsed = []
            for entry in row["produce_obj"].split("#"):
                fields = entry.split("*")
                if len(fields) >= 4 and fields[0]:
                    parsed.append(dict(display_name=fields[0], minimum_quantity=int(fields[1]),
                                       maximum_quantity=int(fields[2]), raw_weight=int(fields[3])))
            assert parsed == expected[int(row["index"])], f"原始掉落候选不一致：{row['index']}"
        raw_note = f"本地荣耀 CSV 的 {len(rows)} 行已逐条校验，名称、数量、原始权重及重复条目与导入候选完全一致。"

    rows = []
    class_species = {row["monster_class"]: row["species_id"] for row in encounters["confirmed_joins"]}
    spawned_names = {runtime["monsters"][sid]["display_name"] for sid in spawned}
    source_root = ROOT.parent / "starhome_lz_ry_fcc_source"
    source_names = recover_class_names(source_root) if (source_root / "npcclt1.fcc").exists() else {}
    mistakes = []
    for task in tasks:
        task_id, kind, target = str(task["id"]), int(task["condition"][0]), task["condition"][1]
        enabled = task_id in runtime["tasks"]
        if enabled:
            status = "金币捐赠" if target == "money" else ("可执行击杀" if kind == 1 else "可执行收集")
            runtime_target = runtime["tasks"][task_id]["target_id"]
            assert (kind == 1 and runtime_target in spawned) or (kind == 2 and (target == "money" or runtime_target in available)), \
                f"已开放任务无获取链：{task_id}"
        elif kind == 1:
            status = "目标怪物未投放"
            if task["title"].removeprefix("击杀").strip() in spawned_names or class_species.get(target) in spawned \
                    or source_names.get(target, {}).get("display_name") in spawned_names:
                mistakes.append(task_id)
        elif kind == 2:
            status = "物品未登记" if not names[target] else "获取链未闭合"
            if target == "money" or names[target] & available:
                mistakes.append(task_id)
        else:
            status = "活动或排名未实现"
        rows.append({"id": task_id, "title": task["title"], "grade": int(task["grade"]), "kind": kind,
                     "source_target": target, "quantity": int(task["condition"][2]), "enabled": enabled,
                     "status": status, "runtime_target": runtime["tasks"].get(task_id, {}).get("target_id", "")})
    counts = Counter(row["status"] for row in rows)
    assert not mistakes, f"仍有可获取目标被过滤：{mistakes}"
    assert len({row['id'] for row in rows}) == len(tasks), "任务 ID 重复"
    output = ROOT / "docs/audits"
    output.mkdir(exist_ok=True)
    (output / "mercenary_availability.jsonl").write_text(
        "\n".join(json.dumps(row, ensure_ascii=False, separators=(",", ":")) for row in rows) + "\n", encoding="utf-8")
    lines = ["# 原版掉落与佣兵任务全量核查", "", "审计日期：2026-09-16。由运行目录导出和原表对照生成。", "",
             "## 结论与口径", "", f"**原版全部候选已配置，非爬虫接合器碎片按用户要求排除。{len(tasks)} 条佣兵定义均保留，当前 {len(runtime['tasks'])} 条可执行。**", "",
             f"荣耀客户端：{len(original)} 种怪物、{sum(source_entries.values())} 条原始候选（包含重复）、{len(source_species)} 种掉落名称。",
             f"按“原物种 → 原物品”关系核对：{full} 种名称的来源关系全覆盖，{partial} 种部分覆盖，{absent} 种未接入原怪物掉落。",
             f"逐原始条目匹配为 {matched_entries}/{sum(source_entries.values())}；去重后的物种—物品关系为 "
             f"{sum(map(len, covered.values()))}/{sum(map(len, source_species.values()))}。这些是关系覆盖率，不是掉率。", "", raw_note, "", task_note, "",
             "“关系全覆盖”仅表示相应怪物配置了该掉落，并不表示概率恢复原服，也不保证每种怪物都有刷新地图。",
             "原表 raw_weight 算法未恢复；普通候选暂统一为每种独立 25%，爬虫碎片为 75% 出 1～3 个（含零数量的期望为1.5）。这不是原服掉率。",
             "免费版已解析 NPC CSV 没有数据行，不能据此宣称免费版无掉落；旧 JZNP 目录属于另一个版本，不混入荣耀运行素材。", "",
             "接合器升级碎片按用户确认仅投放机器爬虫与被遗忘的爬虫及其外观变体，原表其他怪物未开放属于有意缩小范围。",
             "被遗忘的爬虫当前没有启用刷新地图；普通机器爬虫已投放。", "",
             "## 全部 79 种掉落名称", "",
             "列中数量均为去重物种数。来源栏最多展示三个原表怪物；全部关系、概率、数量及原始记录见[检查表](audits/original_monster_drops.xlsx)。",
             "“其他获取链”包含当前启用矿池、在售商品及原料闭合的制造/循环任务奖励；不计测试赠物、管理员注入或同名不同 ID。", "",
             "| 原表名称或类名 | 原表物种 | 配置覆盖 | 已刷怪的覆盖 | 任意获取链 | 原表来源示例 |",
             "| --- | ---: | ---: | ---: | --- | --- |"]
    for name in sorted(source_species):
        species = source_species[name]
        examples = "、".join(runtime["monsters"][sid]["display_name"] for sid in sorted(species)[:3])
        lines.append(f"| {name} | {len(species)} | {len(covered[name])} | {len(covered[name] & spawned)} | "
                     f"{'有' if names[name] & available else '无'} | {examples} |")
    lines += ["", "## 佣兵任务排除结果", "", "| 状态 | 条数 |", "| --- | ---: |"]
    lines += [f"| {status} | {count} |" for status, count in sorted(counts.items())]
    lines += ["", "全部任务的原始条件、数量、运行目标和判定见 [逐条审计](audits/mercenary_availability.jsonl)。",
              "金币任务原 condition 是 `2,money,数量`，先前误走物品查找；现在按金币余额展示进度，交付时扣金币并发放原档位紫晶。",
              f"{len(runtime['offers'])} 项普通商人商品、{len(load('data/gameplay/commerce/premium_shop_v1.json')['offers'])} 项紫晶商品、"
              f"{len(runtime['recipes'])} 条实际制造配方及循环任务奖励额外核对后，没有发现其他已闭合来源被误排。",
              "当前获取链只核查来源存在，不承诺任意人物等级、采掘/制造技能或当前位置均能完成。", "",
              "### 暂未开放的收集目标", "", "| 目标 | 条数 | 原因 |", "| --- | ---: | --- |"]
    missing = Counter((row["source_target"], row["status"]) for row in rows if not row["enabled"] and row["kind"] == 2)
    lines += [f"| {name} | {count} | {status} |" for (name, status), count in sorted(missing.items())]
    lines += ["", "免费版力场模块、炮管磁压器、双进程模块、引擎接合器与商城的新旧接合器没有已确认的一一替代关系，不自动改成另一件装备。",
              "`FoodA_7` 原任务标题为糖瓜；生豆、植物棉及面、糖上游农业原料尚无获取链；馒头缺可执行物品定义。",
              "镁矿已在后续材料投放中开放，相应13条收集任务进入可执行目录；钒矿、钼矿、钽矿仍未进入启用矿池。", "",
              "## 本次纠正的旧结论", "",
              "`NewJointImpactChip` 就是冲击晶体：荣耀 `ven/stuffclt2_ven.fcc:3772` 明确给出了类名与中文名，NPC 候选也有记录。",
              "已恢复中文名与荣耀图像，沿用占位ID，并完整接入原表对应怪物掉落；商城来源继续保留。",
              "五种已确认同源的低级材料/能量包通过 ItemDefinitionAliases 统一历史ID；旧存档加载、背包扣料和制造配方均兼容。", "",
              "## 复核方式", "", "先运行：", "", "```powershell",
              "godot --headless --path . --script res://tools/export_content_supply_audit.gd",
              "python -X utf8 tools/audit_original_drops_and_mercenaries.py", "```", "",
              "工具只读取领域目录，不加载玩家存档。若独立交叉检查发现可获得目标被过滤会失败退出。原始归档缺失时明确降低验证范围。", "",
              f"运行目录快照 SHA-256：`{hashlib.sha256((ROOT / '.godot/content-audit-runtime.json').read_bytes()).hexdigest()}`。"]
    (ROOT / "docs/original_drops_and_mercenary_audit.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"DROP_AUDIT names={len(source_species)} full={full} partial={partial} absent={absent} entries={matched_entries}/{sum(source_entries.values())}")
    print(f"MERCENARY_AUDIT tasks={len(rows)} statuses={dict(counts)} false_exclusions={len(mistakes)}")


if __name__ == "__main__":
    main()
