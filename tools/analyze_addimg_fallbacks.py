import csv
import json
from collections import Counter, defaultdict
from pathlib import Path


def normalize_ale_reference(value: str) -> str:
    normalized = value.replace("\\", "/").strip()
    while normalized.startswith("../"):
        normalized = normalized[3:]
    normalized = normalized.removeprefix("./").lstrip("/")
    map_index = normalized.lower().find("map/")
    if map_index >= 0:
        normalized = normalized[map_index:]
    elif normalized.lower().startswith("mapimg/"):
        normalized = "map/" + normalized
    if normalized.lower().endswith(".ale"):
        normalized = normalized[:-4]
    return normalized.lower()


def index_library(root: Path) -> tuple[dict[str, Path], dict[str, list[Path]]]:
    exact: dict[str, Path] = {}
    basenames: dict[str, list[Path]] = defaultdict(list)
    for manifest in root.rglob("frames.json"):
        folder = manifest.parent
        logical = folder.relative_to(root).as_posix().lower()
        exact[logical] = folder
        basenames[folder.name.lower()].append(folder)
    return exact, basenames


def candidate_json(folder: Path, root: Path, match: str) -> dict:
    manifest = json.loads((folder / "frames.json").read_text(encoding="utf-8"))
    return {
        "match": match,
        "logical_path": folder.relative_to(root).as_posix(),
        "folder": str(folder),
        "frames": len(manifest.get("frames", [])),
        "pages": len(manifest.get("pages", [])),
    }


def main() -> None:
    outputs = Path(__file__).resolve().parents[2]
    missing_report_path = outputs / "starhome_lz_ry_maps_parsed" / "maps_missing_addimg.json"
    missing_report = json.loads(missing_report_path.read_text(encoding="utf-8"))
    map_output_root = missing_report_path.parent
    unique_maps = json.loads((map_output_root / "unique_maps.json").read_text(encoding="utf-8"))
    map_labels = {
        row["output"]: f"{row['map_name']} [{row['map_code']}]"
        for row in unique_maps
    }
    libraries = [
        ("glory", outputs / "starhome_lz_ry_full_parsed" / "ale_sprites"),
        ("free", outputs / "starhome_lz_fr_full_parsed" / "ale_sprites"),
        ("jz", outputs / "starhome_jznp_full_parsed" / "ale_sprites"),
    ]
    indexes = {
        name: (*index_library(root), root)
        for name, root in libraries
    }

    uses: dict[str, dict] = {}
    for map_row in missing_report["maps"]:
        for resource in map_row["missing_resources"]:
            source = resource["source_ale"]
            logical = normalize_ale_reference(source)
            item = uses.setdefault(
                logical,
                {
                    "source_ale": source,
                    "logical_path": logical,
                    "placements": 0,
                    "maps": set(),
                },
            )
            item["placements"] += resource["placements"]
            item["maps"].add(f"{map_row['map_name']} [{map_row['map_code']}]")

    results = []
    outcome_counts: Counter[str] = Counter()
    recovered_placements: Counter[str] = Counter()
    for logical, use in sorted(uses.items()):
        basename = Path(logical).name
        candidates: dict[str, list[dict]] = {}
        exact_editions: list[str] = []
        for edition, _ in libraries:
            exact, basenames, root = indexes[edition]
            edition_candidates: list[dict] = []
            if logical in exact:
                edition_candidates.append(candidate_json(exact[logical], root, "logical_path"))
                exact_editions.append(edition)
            else:
                basename_matches = basenames.get(basename, [])
                edition_candidates.extend(
                    candidate_json(folder, root, "basename") for folder in basename_matches
                )
            candidates[edition] = edition_candidates

        if exact_editions:
            outcome = "exact"
            selected_edition = next(
                edition for edition, _ in libraries if edition in exact_editions
            )
            selected = next(
                candidate
                for candidate in candidates[selected_edition]
                if candidate["match"] == "logical_path"
            )
        elif any(candidates.values()):
            all_basename_candidates = [
                (edition, candidate)
                for edition, _ in libraries
                for candidate in candidates[edition]
            ]
            distinct_paths = {
                candidate["logical_path"].lower()
                for _, candidate in all_basename_candidates
            }
            if len(distinct_paths) == 1:
                outcome = "unique_basename"
                selected_edition, selected = min(
                    all_basename_candidates,
                    key=lambda item: next(
                        index
                        for index, (edition, _) in enumerate(libraries)
                        if edition == item[0]
                    ),
                )
            else:
                outcome = "ambiguous_basename"
                selected_edition = None
                selected = None
        else:
            outcome = "not_found"
            selected_edition = None
            selected = None

        outcome_counts[outcome] += 1
        if selected is not None:
            recovered_placements[outcome] += use["placements"]
        results.append(
            {
                "source_ale": use["source_ale"],
                "logical_path": logical,
                "placements": use["placements"],
                "map_count": len(use["maps"]),
                "maps": sorted(use["maps"]),
                "outcome": outcome,
                "selected_edition": selected_edition,
                "selected": selected,
                "candidates": candidates,
            }
        )

    recovered: dict[tuple[str, str, str], dict] = {}
    for scene_path in map_output_root.glob("maps/**/scene_objects.json"):
        output = scene_path.parent.relative_to(map_output_root).as_posix()
        map_label = map_labels.get(output, output)
        scene = json.loads(scene_path.read_text(encoding="utf-8"))
        for obj in scene.get("objects", []):
            resolution = obj.get("resolution", "")
            if not resolution.startswith("fallback_"):
                continue
            key = (
                obj.get("source_ale", ""),
                obj.get("resolved_ale", ""),
                resolution,
            )
            item = recovered.setdefault(
                key,
                {
                    "source_ale": key[0],
                    "resolved_ale": key[1],
                    "resolution": key[2],
                    "placements": 0,
                    "maps": set(),
                    "map_outputs": set(),
                },
            )
            item["placements"] += 1
            item["maps"].add(map_label)
            item["map_outputs"].add(output)
    recovered_rows = [
        {
            **{
                key: value
                for key, value in item.items()
                if key not in {"maps", "map_outputs"}
            },
            "map_count": len(item["map_outputs"]),
            "maps": sorted(item["maps"]),
            "map_outputs": sorted(item["map_outputs"]),
        }
        for item in recovered.values()
    ]
    recovered_rows.sort(key=lambda item: (-item["placements"], item["source_ale"]))

    summary = {
        "missing_resources_checked": len(results),
        "missing_placements_checked": sum(row["placements"] for row in results),
        "resource_outcomes": dict(sorted(outcome_counts.items())),
        "recoverable_placements": sum(recovered_placements.values()),
        "recoverable_placements_by_match": dict(sorted(recovered_placements.items())),
        "already_recovered_resources": len(recovered_rows),
        "already_recovered_placements": sum(
            item["placements"] for item in recovered_rows
        ),
        "maps_using_recovered_resources": len(
            {output for item in recovered_rows for output in item["map_outputs"]}
        ),
        "selection_policy": (
            "荣耀版、免费版和激战版合并判定：优先完整逻辑路径；其次仅接受三库中"
            "所有同名候选仍指向同一逻辑路径的唯一文件名匹配。荣耀版优先，其次免费版、激战版。"
        ),
    }

    output_root = missing_report_path.parent
    json_path = output_root / "maps_missing_addimg_fallbacks.json"
    json_path.write_text(
        json.dumps(
            {
                "summary": summary,
                "already_recovered": recovered_rows,
                "resources": results,
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    csv_path = output_root / "maps_missing_addimg_fallbacks.csv"
    with csv_path.open("w", encoding="utf-8-sig", newline="") as csv_file:
        writer = csv.DictWriter(
            csv_file,
            fieldnames=[
                "source_ale",
                "placements",
                "map_count",
                "outcome",
                "selected_edition",
                "selected_path",
                "maps",
            ],
        )
        writer.writeheader()
        for row in results:
            writer.writerow(
                {
                    "source_ale": row["source_ale"],
                    "placements": row["placements"],
                    "map_count": row["map_count"],
                    "outcome": row["outcome"],
                    "selected_edition": row["selected_edition"] or "",
                    "selected_path": (
                        row["selected"]["folder"] if row["selected"] is not None else ""
                    ),
                    "maps": " | ".join(row["maps"]),
                }
            )
    recovered_csv_path = output_root / "maps_addimg_recovered_fallbacks.csv"
    with recovered_csv_path.open("w", encoding="utf-8-sig", newline="") as csv_file:
        writer = csv.DictWriter(
            csv_file,
            fieldnames=[
                "source_ale",
                "resolved_ale",
                "resolution",
                "placements",
                "map_count",
                "maps",
                "map_outputs",
            ],
        )
        writer.writeheader()
        for row in recovered_rows:
            writer.writerow(
                {
                    "source_ale": row["source_ale"],
                    "resolved_ale": row["resolved_ale"],
                    "resolution": row["resolution"],
                    "placements": row["placements"],
                    "map_count": row["map_count"],
                    "maps": " | ".join(row["maps"]),
                    "map_outputs": " | ".join(row["map_outputs"]),
                }
            )
    print(json.dumps(summary, ensure_ascii=True, indent=2))
    print(json_path)
    print(csv_path)
    print(recovered_csv_path)


if __name__ == "__main__":
    main()
