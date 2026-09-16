"""List configured versus unconfigured loot, using the initialized authority catalog."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def load(path):
    return json.loads((ROOT / path).read_text("utf-8-sig"))


def main():
    runtime = load(".godot/content-audit-runtime.json")
    encounters = {row["map_id"]: row for row in load("data/gameplay/glory/glory_monster_encounters_v1.json")["encounters"]}
    starter = load("data/gameplay/stage3/d04_encounters_v1.json")
    encounters[starter["map_id"]] = starter
    spawned = {group["monster_id"] for encounter in encounters.values() if encounter.get("enabled", False)
               for group in encounter["spawn_groups"] if group.get("weight", 1) > 0}
    missing = {sid: row for sid, row in runtime["monsters"].items()
               if not any(drop["chance"] > 0 for drop in row.get("drops") or [])}
    active_missing = set(missing) & spawned
    lines = ["# 怪物物品掉落覆盖审计", "", "2026-09-16，使用初始化后的权威目录（含新手覆盖及材料补充表）。", "",
             f"启用刷新物种 {len(spawned)} 种，其中 {len(active_missing)} 种没有物品掉落表；",
             f"另外 {len(missing) - len(active_missing)} 种未投放物种也没有掉落表。外观变体共享物种掉落。", "",
             "原客户端 `source_drop_candidates` 仅是来源证据，不等于实际运行的 `drops`。",
             "原版候选按drop_expectation_policy_v1.json编译期望；原始权重仅保留作为证据。接合器碎片遵循此前用户限定。", "",
             "## D03 与隐形掉落修复", "",
             "低温毒胶：低级类胶75%出1～3（期望1.5）、中级类胶50%出1～2（期望0.75）、低级能量包25%出2～4。",
             "低温感光质的两档催化剂采用相同分布；其低级能量包仍为25%出2～4。",
             "两者过去只有掉落规则，没有地面表现，导致客户端拒绝创建视图。",
             "全部79种候选已具备地面/背包表现；重复行仅抽一次，数量和概率按期望策略覆盖，其余保留原范围。",
             "表中未投放怪物虽已配置掉落，仍需要以后开放刷新地图才能获得其专属物品。", ""]
    for title, keys in [("已投放但无物品掉落", active_missing),
                        ("未投放且无物品掉落", set(missing) - spawned)]:
        lines += [f"## {title}", "", "| 物种 | 名称 | 原客户端候选条数 |", "| --- | --- | ---: |"]
        for sid in sorted(keys):
            row = missing[sid]
            lines.append(f"| {sid} | {row['display_name']} | {len(row.get('source_drop_candidates', []))} |")
        lines.append("")
    ids = {drop["item_definition_id"] for row in runtime["monsters"].values() for drop in row.get("drops") or []}
    invisible = []
    for item_id in sorted(ids):
        item = runtime["items"][item_id]
        presentation = item.get("presentation", {}).get("world", {})
        texture = presentation.get("texture", "")
        if not texture.startswith("res://") or not (ROOT / texture[6:]).is_file():
            invisible.append(item["display_name"])
    lines += ["## 表现完整性", "", f"当前 {len(ids)} 种实际掉落物中，缺地面纹理 {len(invisible)} 种。",
              "", "复核命令：先运行 `tools/export_content_supply_audit.gd`，再运行 `python -X utf8 tools/audit_monster_loot_coverage.py`。", ""]
    (ROOT / "docs/monster_loot_coverage.md").write_text("\n".join(lines), encoding="utf-8")
    print(f"MONSTER_LOOT_AUDIT active={len(spawned)} missing={len(active_missing)} dormant_missing={len(missing)-len(active_missing)} invisible={invisible}")
    assert not invisible, "实际掉落物仍缺地面图像"


if __name__ == "__main__":
    main()
