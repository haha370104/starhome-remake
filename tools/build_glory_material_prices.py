#!/usr/bin/env python3
"""Extract NPC material prices from workspace-local Glory client FCC sources."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path

from recovery.fcc_workspace import PROJECT_ROOT, RawFccWorkspace


SOURCES = ("cltobj/stuffclt.fcc", "cltobj/stuffclt2.fcc", "ven/stuffclt2_ven.fcc")
OUTPUT = PROJECT_ROOT / "data/gameplay/commerce/glory_material_prices_v1.json"
FIELDS = ("m_nWorth", "m_nSell")


def classes_in(text: str, source_file: str) -> dict[str, dict]:
    mask = re.sub(
        r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|//[^\n]*|/\*.*?\*/',
        lambda match: re.sub(r"[^\n]", " ", match.group()), text, flags=re.S,
    )
    result = {}
    for match in re.finditer(r"(?m)^[ \t]*class\s+([^\s:({]+)\s*:\s*([^\s{]+)", mask):
        start = mask.find("{", match.end())
        depth, end = 1, start + 1
        while end < len(mask) and depth:
            depth += (mask[end] == "{") - (mask[end] == "}")
            end += 1
        if start < 0 or depth:
            raise ValueError(f"unclosed class {match[1]} in {source_file}")
        body = mask[start + 1:end - 1]
        fields, dynamic = {}, set()
        cursor, level = 0, 1
        for assignment in re.finditer(r"\b(m_nWorth|m_nSell)\s*=\s*([^;]+);", body):
            for char in body[cursor:assignment.start()]:
                level += (char == "{") - (char == "}")
            cursor = assignment.end()
            field, value = assignment[1], assignment[2].strip()
            if level != 1 or not re.fullmatch(r"\d+", value) or field in fields:
                dynamic.add(field)
            else:
                fields[field] = int(value)
        result[match[1]] = {
            "parent": match[2].rstrip(";"), "fields": fields, "dynamic": dynamic,
            "source_file": source_file, "source_line": text.count("\n", 0, match.start()) + 1,
        }
    return result


def inherited_price(classes: dict, class_name: str, field: str) -> tuple[int, str] | None:
    visited = set()
    while class_name in classes and class_name not in visited:
        visited.add(class_name)
        row = classes[class_name]
        if field in row["dynamic"]:
            return None
        if field in row["fields"]:
            return row["fields"][field], class_name
        class_name = row["parent"]
    return None


def material_classes(classes: dict) -> dict[str, str]:
    candidates = {}
    authored_material_ids = {
        row["display_name"]: row["id"]
        for row in json.loads((PROJECT_ROOT / "data/gameplay/material_items_v1.json").read_text(encoding="utf-8"))["definitions"]
    }
    for path in sorted((PROJECT_ROOT / "data/gameplay").rglob("*.json")):
        if not (path.name.endswith("_items_v1.json") or path.name in
                ("industrial_materials_v1.json", "original_drop_items_v1.json")):
            continue
        for row in json.loads(path.read_text(encoding="utf-8"))["definitions"]:
            if "material" not in row.get("kind", ""):
                continue
            audit = row.get("source_audit", {})
            authored_id = authored_material_ids.get(row["display_name"], "")
            if audit.get("status") == "name_only" and authored_id and authored_id != row["id"]:
                continue
            names = (row.get("source_class"), audit.get("source_class"), row["display_name"])
            class_name = next((name for name in names if name in classes), None)
            if class_name is None:
                continue
            previous = candidates.get(row["id"])
            if previous is not None and previous != class_name:
                raise ValueError(f"conflicting source classes for {row['id']}: {previous}, {class_name}")
            candidates[row["id"]] = class_name
    return candidates


def build() -> dict:
    classes, hashes, duplicate_classes = {}, {}, set()
    with RawFccWorkspace() as workspace:
        for source_file in SOURCES:
            text = workspace.text(source_file)
            hashes[source_file] = hashlib.sha256(workspace.source(source_file).read_bytes()).hexdigest()
            for class_name, row in classes_in(text, source_file).items():
                if class_name in classes:
                    duplicate_classes.add(class_name)
                else:
                    classes[class_name] = row
    for class_name in duplicate_classes:
        del classes[class_name]
    prices = {}
    for item_id, class_name in sorted(material_classes(classes).items()):
        worth = inherited_price(classes, class_name, FIELDS[0])
        sell = inherited_price(classes, class_name, FIELDS[1])
        if sell is None:
            continue
        source = classes[class_name]
        entry = {
            "sell_value": sell[0],
            "source_file": source["source_file"], "source_class": class_name,
            "source_line": source["source_line"],
            "sell_class": sell[1],
        }
        if worth is not None:
            entry["purchase_value"] = worth[0]
            entry["worth_class"] = worth[1]
        prices[item_id] = entry
    return {"schema_version": 1, "source_release": "starhome_lz_ry",
            "source_sha256": hashes, "item_prices": prices}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="compare with the committed price table")
    args = parser.parse_args()
    document = build()
    sources = json.dumps(document["source_sha256"], ensure_ascii=False, separators=(",", ":"))
    prices = document["item_prices"]
    lines = ['{', '  "schema_version": 1,', '  "source_release": "starhome_lz_ry",',
             f'  "source_sha256": {sources},', '  "item_prices": {']
    for index, (item_id, price) in enumerate(prices.items()):
        separator = "," if index < len(prices) - 1 else ""
        key = json.dumps(item_id, ensure_ascii=False)
        value = json.dumps(price, ensure_ascii=False, separators=(",", ":"))
        lines.append(f"    {key}: {value}{separator}")
    encoded = "\n".join(lines + ["  }", "}", ""])
    if args.check:
        if OUTPUT.read_text(encoding="utf-8") != encoded:
            raise SystemExit("Glory material price table is out of date")
    else:
        OUTPUT.write_text(encoded, encoding="utf-8")
    print(f"Glory material prices: {len(document['item_prices'])} exact source mappings")


if __name__ == "__main__":
    main()
