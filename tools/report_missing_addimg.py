import csv
import json
from collections import Counter
from pathlib import Path


def main() -> None:
    output_root = Path(__file__).resolve().parents[2] / "starhome_lz_ry_maps_parsed"
    index = json.loads((output_root / "unique_maps.json").read_text(encoding="utf-8"))
    rows = index.get("maps", index) if isinstance(index, dict) else index

    report: list[dict] = []
    global_resources: Counter[str] = Counter()
    status_counts: Counter[str] = Counter()
    kind_counts: Counter[str] = Counter()

    for row in rows:
        scene_path = output_root / row["output"] / "scene_objects.json"
        if not scene_path.exists():
            continue

        scene = json.loads(scene_path.read_text(encoding="utf-8"))
        unresolved = [obj for obj in scene.get("objects", []) if obj.get("status") != "ok"]
        if not unresolved:
            continue

        resources: Counter[tuple[str, str, str]] = Counter()
        for obj in unresolved:
            source = obj.get("source_ale") or obj.get("ale") or "<unknown>"
            status = obj.get("status", "unknown")
            kind = obj.get("kind", "unknown")
            resources[(source, status, kind)] += 1
            global_resources[source] += 1
            status_counts[status] += 1
            kind_counts[kind] += 1

        missing_resources = [
            {
                "source_ale": source,
                "status": status,
                "kind": kind,
                "placements": count,
            }
            for (source, status, kind), count in sorted(
                resources.items(), key=lambda item: (-item[1], item[0][0])
            )
        ]
        scene_summary = row.get("scene_objects", {})
        report.append(
            {
                "map_name": row.get("map_name", ""),
                "map_code": row.get("map_code", ""),
                "source_branches": row.get("source_branches", []),
                "output": row.get("output", ""),
                "addimg_total": scene_summary.get(
                    "count", scene.get("count", len(scene.get("objects", [])))
                ),
                "resolved_placements": scene_summary.get(
                    "resolved", scene.get("resolved", 0)
                ),
                "missing_placements": len(unresolved),
                "unique_missing_resources": len({item[0] for item in resources}),
                "missing_resources": missing_resources,
            }
        )

    report.sort(
        key=lambda item: (
            -item["missing_placements"],
            item["map_name"],
            item["map_code"],
            item["output"],
        )
    )
    summary = {
        "unique_map_products_with_unresolved_addimg": len(report),
        "unresolved_addimg_placements": sum(
            item["missing_placements"] for item in report
        ),
        "unique_unresolved_ale_paths": len(global_resources),
        "status_counts": dict(sorted(status_counts.items())),
        "kind_counts": dict(sorted(kind_counts.items())),
        "note": (
            "按去重后的唯一地图产物统计；NFT 分支中内容完全相同的副本不重复列出。"
            "同名但内容不同的地图变体分别保留。"
        ),
    }

    json_path = output_root / "maps_missing_addimg.json"
    json_path.write_text(
        json.dumps({"summary": summary, "maps": report}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    csv_path = output_root / "maps_missing_addimg.csv"
    with csv_path.open("w", encoding="utf-8-sig", newline="") as csv_file:
        fieldnames = [
            "map_name",
            "map_code",
            "source_branches",
            "output",
            "addimg_total",
            "resolved_placements",
            "missing_placements",
            "unique_missing_resources",
            "missing_ale_paths",
        ]
        writer = csv.DictWriter(csv_file, fieldnames=fieldnames)
        writer.writeheader()
        for item in report:
            writer.writerow(
                {
                    "map_name": item["map_name"],
                    "map_code": item["map_code"],
                    "source_branches": " | ".join(item["source_branches"]),
                    "output": item["output"],
                    "addimg_total": item["addimg_total"],
                    "resolved_placements": item["resolved_placements"],
                    "missing_placements": item["missing_placements"],
                    "unique_missing_resources": item["unique_missing_resources"],
                    "missing_ale_paths": " | ".join(
                        (
                            f"{resource['source_ale']} x{resource['placements']} "
                            f"[{resource['status']}/{resource['kind']}]"
                        )
                        for resource in item["missing_resources"]
                    ),
                }
            )

    md_path = output_root / "maps_missing_addimg.md"
    lines = [
        "# 缺少或无法解析 AddImg 场景物件的地图",
        "",
        f"- 唯一地图产物：{len(report)}",
        f"- 缺失/未解析摆放记录：{summary['unresolved_addimg_placements']}",
        f"- 涉及 ALE 路径：{summary['unique_unresolved_ale_paths']}",
        "- 统计口径：完全相同的 NFT 分支副本仅列一次；同名但内容不同的变体分别列出。",
        "",
        "| 地图名 | 内部代码 | 来源分支 | 缺失/总摆放 | 缺失 ALE 种数 | 输出目录 |",
        "|---|---|---|---:|---:|---|",
    ]
    for item in report:
        name = str(item["map_name"]).replace("|", "\\|")
        branches = ", ".join(item["source_branches"]).replace("|", "\\|")
        lines.append(
            f"| {name} | `{item['map_code']}` | {branches} | "
            f"{item['missing_placements']}/{item['addimg_total']} | "
            f"{item['unique_missing_resources']} | `{item['output']}` |"
        )
    lines.extend(
        [
            "",
            "逐项 ALE 路径与摆放次数见 `maps_missing_addimg.json`，"
            "或 CSV 的 `missing_ale_paths` 列。",
            "",
        ]
    )
    md_path.write_text("\n".join(lines), encoding="utf-8")

    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print("top_maps")
    for item in report[:20]:
        print(
            f"{item['missing_placements']:4d}/{item['addimg_total']:<4d}  "
            f"{item['map_name']}  [{item['map_code']}]  {item['output']}"
        )
    print("outputs")
    print(md_path)
    print(csv_path)
    print(json_path)


if __name__ == "__main__":
    main()
