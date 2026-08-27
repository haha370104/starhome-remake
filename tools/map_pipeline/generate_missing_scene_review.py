#!/usr/bin/env python3
"""Generate a human-review package for maps with unresolved scene objects.

The reconstructed composite is intentionally left unchanged.  A separate full-size
image marks every unresolved AddImg/AddImgEx anchor so missing artwork can be
reviewed without guessing a replacement.
"""

from __future__ import annotations

import argparse
import csv
import html
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


Image.MAX_IMAGE_PIXELS = None


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )


def rel_url(path: Path, base: Path) -> str:
    return path.resolve().relative_to(base.resolve()).as_posix()


def marker_color(kinds: set[str]) -> tuple[int, int, int, int]:
    if kinds == {"AddImgEx"}:
        return (255, 190, 0, 255)
    if kinds == {"AddImg"}:
        return (255, 45, 45, 255)
    return (255, 50, 220, 255)


def draw_marker(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    radius: int,
    color: tuple[int, int, int, int],
) -> None:
    # A dark halo keeps the marker readable over bright floor tiles.
    draw.ellipse(
        (x - radius - 2, y - radius - 2, x + radius + 2, y + radius + 2),
        outline=(0, 0, 0, 230),
        width=5,
    )
    draw.ellipse(
        (x - radius, y - radius, x + radius, y + radius), outline=color, width=4
    )
    draw.line((x - radius, y, x + radius, y), fill=(0, 0, 0, 230), width=6)
    draw.line((x, y - radius, x, y + radius), fill=(0, 0, 0, 230), width=6)
    draw.line((x - radius, y, x + radius, y), fill=color, width=3)
    draw.line((x, y - radius, x, y + radius), fill=color, width=3)


def render_map(
    map_record: dict[str, Any], maps_root: Path, review_root: Path
) -> dict[str, Any]:
    output = map_record["output"]
    source_dir = maps_root / output
    scene_path = source_dir / "scene_objects.json"
    composite_path = source_dir / "composite.png"
    scene = read_json(scene_path)
    missing = [obj for obj in scene.get("objects", []) if obj.get("status") != "ok"]

    by_anchor: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    by_resource: dict[str, list[dict[str, Any]]] = defaultdict(list)
    by_kind: Counter[str] = Counter()
    for obj in missing:
        x, y = (int(value) for value in obj["anchor"])
        by_anchor[(x, y)].append(obj)
        by_resource[str(obj.get("source_ale", ""))].append(obj)
        by_kind[str(obj.get("kind", "unknown"))] += 1

    destination_dir = review_root / output
    destination_dir.mkdir(parents=True, exist_ok=True)
    marked_path = destination_dir / "missing_marked.png"
    thumbnail_path = destination_dir / "thumbnail.jpg"
    detail_path = destination_dir / "missing_scene_objects.json"

    with Image.open(composite_path) as source:
        marked = source.convert("RGBA")
    draw = ImageDraw.Draw(marked)
    radius = max(10, round(max(marked.size) / 400))
    out_of_bounds = 0
    for (x, y), objects in sorted(by_anchor.items()):
        if not (0 <= x < marked.width and 0 <= y < marked.height):
            out_of_bounds += len(objects)
            continue
        draw_marker(draw, x, y, radius, marker_color({str(o.get("kind")) for o in objects}))

    marked.save(marked_path, compress_level=3)
    thumbnail = marked.convert("RGB")
    thumbnail.thumbnail((520, 390), Image.Resampling.LANCZOS)
    thumbnail.save(thumbnail_path, quality=88, optimize=True)
    thumbnail.close()
    marked.close()

    grouped_resources = []
    for resource, objects in sorted(by_resource.items()):
        grouped_resources.append(
            {
                "source_ale": resource,
                "placements": len(objects),
                "kinds": dict(sorted(Counter(str(o.get("kind")) for o in objects).items())),
                "anchors": [o.get("anchor") for o in objects],
                "object_indices": [o.get("index") for o in objects],
            }
        )

    result = {
        "map_code": map_record.get("map_code"),
        "map_name": map_record.get("map_name"),
        "category": map_record.get("category"),
        "source_branches": map_record.get("source_branches", []),
        "output": output,
        "map_pixel_size": map_record.get("map_pixel_size"),
        "scene_objects": {
            "count": scene.get("count", len(scene.get("objects", []))),
            "resolved": scene.get("resolved"),
            "missing": len(missing),
            "unique_missing_resources": len(by_resource),
            "unique_missing_anchors": len(by_anchor),
            "missing_by_kind": dict(sorted(by_kind.items())),
            "out_of_bounds_placements": out_of_bounds,
        },
        "files": {
            "missing_marked": rel_url(marked_path, review_root),
            "thumbnail": rel_url(thumbnail_path, review_root),
            "details": rel_url(detail_path, review_root),
            "source_composite": str(composite_path.resolve()),
            "source_scene_objects": str(scene_path.resolve()),
        },
        "missing_resources": grouped_resources,
    }
    write_json(detail_path, result)
    return result


def write_csv_report(path: Path, records: list[dict[str, Any]]) -> None:
    fields = [
        "map_code",
        "map_name",
        "category",
        "source_branches",
        "output",
        "missing_placements",
        "unique_missing_resources",
        "unique_missing_anchors",
        "addimg_missing",
        "addimgex_missing",
        "out_of_bounds_placements",
        "missing_marked",
    ]
    with path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        for record in records:
            stats = record["scene_objects"]
            kinds = stats["missing_by_kind"]
            writer.writerow(
                {
                    "map_code": record["map_code"],
                    "map_name": record["map_name"],
                    "category": record["category"],
                    "source_branches": ",".join(record["source_branches"]),
                    "output": record["output"],
                    "missing_placements": stats["missing"],
                    "unique_missing_resources": stats["unique_missing_resources"],
                    "unique_missing_anchors": stats["unique_missing_anchors"],
                    "addimg_missing": kinds.get("AddImg", 0),
                    "addimgex_missing": kinds.get("AddImgEx", 0),
                    "out_of_bounds_placements": stats["out_of_bounds_placements"],
                    "missing_marked": record["files"]["missing_marked"],
                }
            )


def write_html(path: Path, maps_root: Path, records: list[dict[str, Any]], summary: dict[str, Any]) -> None:
    cards = []
    for record in records:
        stats = record["scene_objects"]
        marked = record["files"]["missing_marked"]
        thumb = record["files"]["thumbnail"]
        details = record["files"]["details"]
        source_composite = (Path("..") / maps_root.name / record["output"] / "composite.png").as_posix()
        resources = " ".join(item["source_ale"] for item in record["missing_resources"])
        search = " ".join(
            [
                str(record.get("map_code", "")),
                str(record.get("map_name", "")),
                " ".join(record.get("source_branches", [])),
                resources,
            ]
        ).lower()
        cards.append(
            f'''<article class="card" data-search="{html.escape(search, quote=True)}" data-missing="{stats['missing']}">
  <a href="{html.escape(marked, quote=True)}"><img loading="lazy" src="{html.escape(thumb, quote=True)}" alt="{html.escape(str(record.get('map_name') or record.get('map_code')))}"></a>
  <div class="body">
    <h2>{html.escape(str(record.get('map_code')))} · {html.escape(str(record.get('map_name') or '未命名'))}</h2>
    <p><b>{stats['missing']}</b> 个缺失摆放 / {stats['unique_missing_resources']} 种 ALE / {stats['unique_missing_anchors']} 个位置</p>
    <p class="muted">{html.escape('、'.join(record.get('source_branches', [])))} · {html.escape(record['output'])}</p>
    <p><a href="{html.escape(marked, quote=True)}">原尺寸标记图</a> · <a href="{html.escape(source_composite, quote=True)}">未标记复原图</a> · <a href="{html.escape(details, quote=True)}">缺失清单 JSON</a></p>
  </div>
</article>'''
        )

    path.write_text(
        f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>荣耀版地图缺失场景素材人工审计</title>
<style>
:root {{ color-scheme: dark; font-family: system-ui,"Microsoft YaHei",sans-serif; background:#11151b; color:#eaf0f7 }}
body {{ margin:0; padding:24px }} h1 {{ margin:0 0 8px }} .summary {{ color:#9fb0c3; margin-bottom:18px }}
.legend span {{ display:inline-block; margin-right:18px }} .dot {{ width:11px;height:11px;border-radius:50%;display:inline-block;margin-right:5px }}
input {{ width:min(720px,95%);box-sizing:border-box;padding:11px 14px;margin:16px 0 22px;background:#1d2530;color:#fff;border:1px solid #3a4a5d;border-radius:6px;font-size:16px }}
#grid {{ display:grid;grid-template-columns:repeat(auto-fill,minmax(320px,1fr));gap:16px }}
.card {{ background:#1a222d;border:1px solid #2f3b49;border-radius:8px;overflow:hidden }} .card img {{ width:100%;aspect-ratio:4/3;object-fit:contain;background:#090b0f;display:block }}
.body {{ padding:12px 14px }} h2 {{ font-size:17px;margin:0 0 8px }} p {{ margin:6px 0 }} .muted {{ color:#98a8ba;font-size:13px;overflow-wrap:anywhere }} a {{ color:#57c9ff }}
</style></head><body>
<h1>荣耀版地图缺失场景素材人工审计</h1>
<div class="summary">共 {summary['maps_with_missing_scene_objects']} 张地图，{summary['missing_placements']} 个缺失摆放，涉及 {summary['globally_unique_missing_resources']} 种 ALE。地图保持缺失处为空白；标记图只叠加审计标记。</div>
<div class="legend"><span><i class="dot" style="background:#ff2d2d"></i>AddImg</span><span><i class="dot" style="background:#ffbe00"></i>AddImgEx</span><span><i class="dot" style="background:#ff32dc"></i>同一点混合类型</span></div>
<input id="q" autofocus placeholder="搜索地图编号、名称、分支或缺失 ALE 路径">
<div id="grid">{''.join(cards)}</div>
<script>
const q=document.querySelector('#q'), cards=[...document.querySelectorAll('.card')];
q.addEventListener('input',()=>{{const s=q.value.trim().toLowerCase();cards.forEach(c=>c.hidden=s&&!c.dataset.search.includes(s));}});
</script></body></html>''',
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("maps_root", type=Path)
    parser.add_argument("review_root", type=Path)
    args = parser.parse_args()

    maps_root = args.maps_root.resolve()
    review_root = args.review_root.resolve()
    review_root.mkdir(parents=True, exist_ok=True)
    unique_maps = read_json(maps_root / "unique_maps.json")
    candidates = [
        record
        for record in unique_maps
        if int(record.get("scene_objects", {}).get("missing", 0)) > 0
    ]
    candidates.sort(
        key=lambda record: (
            -int(record.get("scene_objects", {}).get("missing", 0)),
            str(record.get("map_code", "")),
            str(record.get("output", "")),
        )
    )

    records: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    for index, record in enumerate(candidates, start=1):
        try:
            records.append(render_map(record, maps_root, review_root))
        except Exception as exc:  # keep the remaining review batch useful
            errors.append({"output": record.get("output", ""), "error": repr(exc)})
        if index == 1 or index % 10 == 0 or index == len(candidates):
            print(f"[{index}/{len(candidates)}] rendered={len(records)} errors={len(errors)}", flush=True)

    all_resources = {
        item["source_ale"] for record in records for item in record["missing_resources"]
    }
    summary = {
        "unique_map_outputs": len(unique_maps),
        "maps_with_missing_scene_objects": len(records),
        "missing_placements": sum(record["scene_objects"]["missing"] for record in records),
        "unique_missing_anchors": sum(record["scene_objects"]["unique_missing_anchors"] for record in records),
        "globally_unique_missing_resources": len(all_resources),
        "out_of_bounds_placements": sum(record["scene_objects"]["out_of_bounds_placements"] for record in records),
        "errors": len(errors),
        "marker_legend": {
            "AddImg": "red",
            "AddImgEx": "amber",
            "mixed_at_same_anchor": "magenta",
        },
    }
    package = {
        "schema": "starhome_remake_missing_scene_review_v1",
        "summary": summary,
        "maps": records,
        "errors": errors,
    }
    write_json(review_root / "missing_scene_review.json", package)
    write_csv_report(review_root / "missing_scene_review.csv", records)
    write_html(review_root / "index.html", maps_root, records, summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
