#!/usr/bin/env python3
"""Compare scene-object placements between two reconstructed map variants."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw


def load_objects(path: Path) -> list[dict[str, Any]]:
    return json.loads(path.read_text(encoding="utf-8")).get("objects", [])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left_scene", type=Path)
    parser.add_argument("right_scene", type=Path)
    parser.add_argument("output_json", type=Path)
    parser.add_argument("--left-image", type=Path)
    parser.add_argument("--marked-output", type=Path)
    args = parser.parse_args()

    left = load_objects(args.left_scene)
    right = load_objects(args.right_scene)
    right_by_anchor: dict[tuple[int, int], list[dict[str, Any]]] = defaultdict(list)
    for item in right:
        right_by_anchor[tuple(item["anchor"])].append(item)

    unresolved_left = [item for item in left if item.get("status") != "ok"]
    comparisons = []
    classifications: Counter[str] = Counter()
    replacement_votes: dict[str, Counter[str]] = defaultdict(Counter)
    for item in unresolved_left:
        candidates = right_by_anchor.get(tuple(item["anchor"]), [])
        resolved_candidates = [candidate for candidate in candidates if candidate.get("status") == "ok"]
        if len(resolved_candidates) == 1:
            classification = "one_resolved_candidate"
            replacement_votes[item["source_ale"]][resolved_candidates[0]["source_ale"]] += 1
        elif len(resolved_candidates) > 1:
            classification = "multiple_resolved_candidates"
        elif candidates:
            classification = "only_unresolved_candidates"
        else:
            classification = "no_same_anchor_candidate"
        classifications[classification] += 1
        comparisons.append(
            {
                "left_index": item.get("index"),
                "left_source_ale": item.get("source_ale"),
                "anchor": item.get("anchor"),
                "classification": classification,
                "right_candidates": [
                    {
                        "index": candidate.get("index"),
                        "source_ale": candidate.get("source_ale"),
                        "status": candidate.get("status"),
                        "resolved_ale": candidate.get("resolved_ale"),
                    }
                    for candidate in candidates
                ],
            }
        )

    stable_replacements = []
    for source, votes in replacement_votes.items():
        total_missing = sum(
            1 for item in unresolved_left if item.get("source_ale") == source
        )
        if len(votes) == 1:
            replacement, aligned = next(iter(votes.items()))
            stable_replacements.append(
                {
                    "left_source_ale": source,
                    "right_source_ale": replacement,
                    "aligned_placements": aligned,
                    "left_missing_placements": total_missing,
                    "covers_all_left_occurrences": aligned == total_missing,
                }
            )
    stable_replacements.sort(
        key=lambda item: (-item["aligned_placements"], item["left_source_ale"])
    )

    result = {
        "summary": {
            "left_objects": len(left),
            "left_unresolved": len(unresolved_left),
            "right_objects": len(right),
            "right_unresolved": sum(item.get("status") != "ok" for item in right),
            "same_anchor_classifications": dict(sorted(classifications.items())),
            "stable_replacement_resources": len(stable_replacements),
            "stable_replacement_placements": sum(
                item["aligned_placements"] for item in stable_replacements
            ),
        },
        "stable_replacements": stable_replacements,
        "unresolved_comparisons": comparisons,
    }
    args.output_json.parent.mkdir(parents=True, exist_ok=True)
    args.output_json.write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    if args.left_image and args.marked_output:
        with Image.open(args.left_image) as source:
            marked = source.convert("RGBA")
        draw = ImageDraw.Draw(marked)
        radius = max(8, round(max(marked.size) / 400))
        for item in unresolved_left:
            x, y = item["anchor"]
            color = (
                (255, 190, 0, 255)
                if right_by_anchor.get((x, y))
                else (255, 40, 40, 255)
            )
            draw.ellipse((x - radius, y - radius, x + radius, y + radius), outline=color, width=3)
            draw.line((x - radius, y, x + radius, y), fill=color, width=2)
            draw.line((x, y - radius, x, y + radius), fill=color, width=2)
        args.marked_output.parent.mkdir(parents=True, exist_ok=True)
        marked.save(args.marked_output, compress_level=3)
        marked.close()

    print(json.dumps(result["summary"], ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
