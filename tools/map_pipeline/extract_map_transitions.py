#!/usr/bin/env python3
"""Extract branch-aware map transitions from FancyBoxII map FCC metadata."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


MAP_NAME_RE = re.compile(rb"\bm_sMapName\s*=\s*\"([^\"]*)\"", re.I)
CHECK_NAME_RE = re.compile(rb"\bm_sNameForCheck\s*=\s*\"([^\"]*)\"", re.I)
TRANSPORT_RE = re.compile(
    rb"(?mi)^[ \t]*(?P<slashes>/+)?[ \t]*"
    rb"AddImgEx\s*\(\s*['\"]transport['\"]\s*,\s*"
    rb"(?:\$\+\s*)?['\"](?P<ale>[^'\"]+\.ale)['\"]\s*,\s*"
    rb"(?P<x>-?\d+)\s*,\s*(?P<y>-?\d+)\s*,\s*"
    rb"(?P<mode>-?\d+)\s*,\s*(?P<priority>-?\d+)\s*,\s*"
    rb"['\"](?P<payload>[^'\"]+)['\"]\s*\)\s*;"
)
TRANSPORT2_RE = re.compile(
    rb"(?mi)^[ \t]*(?P<slashes>/+)?[ \t]*"
    rb"AddImgEx\s*\(\s*['\"]transport2['\"]\s*,\s*"
    rb"(?:\$\+\s*)?['\"](?P<ale>[^'\"]+\.ale)['\"]\s*,\s*"
    rb"(?P<x>-?\d+)\s*,\s*(?P<y>-?\d+)\s*,\s*"
    rb"(?P<mode>-?\d+)\s*,\s*(?P<priority>-?\d+)\s*,\s*"
    rb"(?P<payload_expression>.*?)\)\s*;",
    re.S,
)


def decode_client_text(raw: bytes | None, fallback: str = "") -> str:
    if raw is None:
        return fallback
    for encoding in ("gb18030", "utf-8"):
        try:
            value = raw.decode(encoding).strip()
            if value:
                return value
        except UnicodeDecodeError:
            pass
    return raw.decode("gb18030", errors="replace").strip() or fallback


def first_group(pattern: re.Pattern[bytes], content: bytes) -> bytes | None:
    match = pattern.search(content)
    return match.group(1) if match else None


def payload_fields(payload: str) -> dict[str, Any]:
    tokens = payload.split()
    if not tokens:
        return {
            "destination_map_code": "",
            "label": "",
            "approach_point": None,
            "destination_entry_number": 0,
            "parameters": [],
            "payload_status": "empty",
        }
    destination = tokens[0]
    numeric_tail: list[int] = []
    index = len(tokens) - 1
    while index >= 1 and re.fullmatch(r"-?\d+", tokens[index]):
        numeric_tail.append(int(tokens[index]))
        index -= 1
    numeric_tail.reverse()
    return {
        "destination_map_code": destination,
        "label": " ".join(tokens[1 : index + 1]),
        "approach_point": numeric_tail[:2] if len(numeric_tail) >= 2 else None,
        "destination_entry_number": numeric_tail[2] if len(numeric_tail) > 2 else 0,
        "parameters": numeric_tail[3:] if len(numeric_tail) > 3 else [],
        "payload_status": "ok" if len(numeric_tail) >= 2 else "missing_approach_point",
    }


def source_state(slashes: bytes | None) -> tuple[str, bool]:
    slash_count = len(slashes or b"")
    if slash_count == 0:
        return "active_call", True
    if slash_count == 2:
        return "metadata_enabled", True
    if slash_count >= 4:
        return "metadata_disabled", False
    return "unknown_comment_form", False


def unquote_argument(value: bytes) -> str:
    value = value.strip()
    if len(value) >= 2 and value[:1] in {b"'", b'"'} and value[-1:] == value[:1]:
        value = value[1:-1]
    return decode_client_text(value)


def parse_int_argument(value: bytes) -> int | None:
    value = value.strip()
    return int(value) if re.fullmatch(rb"-?\d+", value) else None


def extract_ag_transitions(
    expanded_root: Path,
    output_by_code: dict[str, str],
) -> list[dict[str, Any]]:
    script = expanded_root / "client_include" / "client_include.fcc.cab"
    if not script.is_file():
        return []
    content = script.read_bytes()
    function_start = content.find(b"void CreateAGTransLine")
    if function_start < 0:
        return []
    switch_match = re.search(
        rb"switch\s*\(\s*pid\.m_sSvrName\s*\)\s*\{",
        content[function_start:],
    )
    if not switch_match:
        return []
    switch_start = function_start + switch_match.end()
    default_match = re.search(rb"\bdefault\s*:", content[switch_start:])
    if not default_match:
        return []
    switch_body = content[switch_start : switch_start + default_match.start()]
    case_pattern = re.compile(
        rb"case\s+\"(?P<source>[^\"]+)\"\s*:(?P<body>.*?)(?=\bcase\s+\"|\Z)",
        re.S,
    )
    constructor_pattern = re.compile(
        rb"new\s+(?P<kind>AGTransLine|AGTransPoint)\s*\((?P<args>.*?)\)\s*;",
        re.S,
    )
    script_hash = hashlib.sha256(content).hexdigest()
    relative_script = script.relative_to(expanded_root).as_posix()
    rows = []
    for case_match in case_pattern.finditer(switch_body):
        source_code = decode_client_text(case_match.group("source"))
        case_absolute_start = switch_start + case_match.start("body")
        for constructor in constructor_pattern.finditer(case_match.group("body")):
            arguments = [part.strip() for part in constructor.group("args").split(b",")]
            kind = constructor.group("kind").decode("ascii")
            absolute_start = case_absolute_start + constructor.start()
            line_number = content.count(b"\n", 0, absolute_start) + 1
            if kind == "AGTransLine" and len(arguments) == 10:
                destination = unquote_argument(arguments[8])
                direction = unquote_argument(arguments[7])
                handler = unquote_argument(arguments[5])
                begin = parse_int_argument(arguments[9])
                boundary = [argument.decode("ascii", errors="replace") for argument in arguments[:4]]
                x = parse_int_argument(arguments[0])
                y = parse_int_argument(arguments[1])
                rows.append(
                    {
                        "enabled": True,
                        "source_state": "active_client_rule",
                        "branch": "GLOBAL",
                        "source_map_code": source_code,
                        "source_map_name": source_code,
                        "source_map_output": output_by_code.get(source_code.lower(), ""),
                        "source_script_sha256": script_hash,
                        "source_script": relative_script,
                        "source_line": line_number,
                        "transport_kind": "ag_line",
                        "choice_index": 0,
                        "icon_ale": "",
                        "icon_anchor": [x or 0, y or 0],
                        "mode": 0,
                        "priority": 0,
                        "payload": f"{destination} {direction} {begin}",
                        "destination_map_code": destination,
                        "label": direction,
                        "approach_point": None,
                        "destination_entry_number": 0,
                        "parameters": [],
                        "payload_status": "ok",
                        "source_boundary": boundary,
                        "destination_landing_point": None,
                        "destination_landing_rule": {
                            "handler": handler,
                            "direction": direction,
                            "begin": begin,
                            "rule": "preserve crossing-axis offset; opposite edge is 500 or 3800",
                        },
                    }
                )
            elif kind == "AGTransPoint" and len(arguments) == 7:
                x = parse_int_argument(arguments[0])
                y = parse_int_argument(arguments[1])
                radius = parse_int_argument(arguments[2])
                destination = unquote_argument(arguments[3])
                destination_x = parse_int_argument(arguments[4])
                destination_y = parse_int_argument(arguments[5])
                can_click = parse_int_argument(arguments[6])
                rows.append(
                    {
                        "enabled": True,
                        "source_state": "active_client_rule",
                        "branch": "GLOBAL",
                        "source_map_code": source_code,
                        "source_map_name": source_code,
                        "source_map_output": output_by_code.get(source_code.lower(), ""),
                        "source_script_sha256": script_hash,
                        "source_script": relative_script,
                        "source_line": line_number,
                        "transport_kind": "ag_point",
                        "choice_index": 0,
                        "icon_ale": "",
                        "icon_anchor": [x or 0, y or 0],
                        "mode": 0,
                        "priority": 0,
                        "payload": f"{destination} {destination_x} {destination_y}",
                        "destination_map_code": destination,
                        "label": "定点传送",
                        "approach_point": [x or 0, y or 0],
                        "destination_entry_number": 0,
                        "parameters": [radius or 0, can_click or 0],
                        "payload_status": "ok",
                        "source_radius": radius,
                        "can_click": bool(can_click),
                        "destination_landing_point": [destination_x or 0, destination_y or 0],
                        "destination_landing_rule": None,
                    }
                )
    return rows


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fields = [
        "enabled",
        "source_state",
        "branch",
        "source_map_code",
        "source_map_name",
        "source_map_output",
        "transport_kind",
        "choice_index",
        "destination_map_code",
        "destination_present_in_branch",
        "reciprocal_in_branch",
        "icon_anchor_x",
        "icon_anchor_y",
        "approach_x",
        "approach_y",
        "destination_entry_number",
        "parameters",
        "label",
        "icon_ale",
        "mode",
        "priority",
        "source_script",
        "source_line",
        "payload",
    ]
    with path.open("w", encoding="utf-8-sig", newline="") as csv_file:
        writer = csv.DictWriter(csv_file, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            approach = row.get("approach_point") or ["", ""]
            writer.writerow(
                {
                    "enabled": row["enabled"],
                    "source_state": row["source_state"],
                    "branch": row["branch"],
                    "source_map_code": row["source_map_code"],
                    "source_map_name": row["source_map_name"],
                    "source_map_output": row.get("source_map_output", ""),
                    "transport_kind": row["transport_kind"],
                    "choice_index": row["choice_index"],
                    "destination_map_code": row["destination_map_code"],
                    "destination_present_in_branch": row["destination_present_in_branch"],
                    "reciprocal_in_branch": row["reciprocal_in_branch"],
                    "icon_anchor_x": row["icon_anchor"][0],
                    "icon_anchor_y": row["icon_anchor"][1],
                    "approach_x": approach[0],
                    "approach_y": approach[1],
                    "destination_entry_number": row["destination_entry_number"],
                    "parameters": " ".join(str(value) for value in row["parameters"]),
                    "label": row["label"],
                    "icon_ale": row["icon_ale"],
                    "mode": row["mode"],
                    "priority": row["priority"],
                    "source_script": row["source_script"],
                    "source_line": row["source_line"],
                    "payload": row["payload"],
                }
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("expanded_root", type=Path)
    parser.add_argument("map_output_root", type=Path)
    args = parser.parse_args()

    map_results_path = args.map_output_root / "unique_maps.json"
    map_results = (
        json.loads(map_results_path.read_text(encoding="utf-8"))
        if map_results_path.is_file()
        else []
    )
    output_by_hash = {
        row["script_sha256"]: row.get("output", "") for row in map_results
    }
    output_by_code: dict[str, str] = {}
    destination_outputs_by_branch_and_code: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in map_results:
        for value in (row.get("map_code", ""), row.get("map_name", "")):
            if value:
                output_by_code.setdefault(value.lower(), row.get("output", ""))
        for branch in row.get("source_branches", []):
            destination_outputs_by_branch_and_code[
                (branch.lower(), row.get("map_code", "").lower())
            ].add(row.get("output", ""))

    scripts = sorted(args.expanded_root.glob("NFT_*/map/**/*.cab"))
    rows: list[dict[str, Any]] = []
    source_transport_calls = 0
    branch_codes: dict[str, set[str]] = defaultdict(set)
    script_records = []
    for script in scripts:
        content = script.read_bytes()
        relative = script.relative_to(args.expanded_root)
        if len(relative.parts) < 4:
            continue
        branch = relative.parts[0]
        fallback_code = script.parent.name
        map_code = decode_client_text(
            first_group(CHECK_NAME_RE, content), fallback_code
        )
        map_name = decode_client_text(first_group(MAP_NAME_RE, content), map_code)
        script_hash = hashlib.sha256(content).hexdigest()
        aliases = {
            map_code.lower(),
            fallback_code.lower(),
            script.stem.removesuffix(".fcc").lower(),
        }
        branch_codes[branch].update(aliases)
        script_records.append((script, relative, content, branch, map_code, map_name, script_hash))

    for script, relative, content, branch, map_code, map_name, script_hash in script_records:
        for match in TRANSPORT_RE.finditer(content):
            source_transport_calls += 1
            state, enabled = source_state(match.group("slashes"))
            payload = decode_client_text(match.group("payload"))
            parsed_payload = payload_fields(payload)
            line_number = content.count(b"\n", 0, match.start()) + 1
            rows.append(
                {
                    "enabled": enabled,
                    "source_state": state,
                    "branch": branch,
                    "source_map_code": map_code,
                    "source_map_name": map_name,
                    "source_map_output": output_by_hash.get(script_hash, ""),
                    "source_script_sha256": script_hash,
                    "source_script": relative.as_posix(),
                    "source_line": line_number,
                    "transport_kind": "transport",
                    "choice_index": 0,
                    "icon_ale": decode_client_text(match.group("ale")),
                    "icon_anchor": [int(match.group("x")), int(match.group("y"))],
                    "mode": int(match.group("mode")),
                    "priority": int(match.group("priority")),
                    "payload": payload,
                    **parsed_payload,
                }
            )
        for match in TRANSPORT2_RE.finditer(content):
            source_transport_calls += 1
            state, enabled = source_state(match.group("slashes"))
            payload = "".join(
                decode_client_text(part)
                for part in re.findall(rb"['\"]([^'\"]*)['\"]", match.group("payload_expression"))
            )
            choices = [choice.strip() for choice in payload.split(";") if choice.strip()]
            line_number = content.count(b"\n", 0, match.start()) + 1
            for choice_index, choice in enumerate(choices):
                rows.append(
                    {
                        "enabled": enabled,
                        "source_state": state,
                        "branch": branch,
                        "source_map_code": map_code,
                        "source_map_name": map_name,
                        "source_map_output": output_by_hash.get(script_hash, ""),
                        "source_script_sha256": script_hash,
                        "source_script": relative.as_posix(),
                        "source_line": line_number,
                        "transport_kind": "transport2",
                        "choice_index": choice_index,
                        "icon_ale": decode_client_text(match.group("ale")),
                        "icon_anchor": [int(match.group("x")), int(match.group("y"))],
                        "mode": int(match.group("mode")),
                        "priority": int(match.group("priority")),
                        "payload": choice,
                        **payload_fields(choice),
                    }
                )

    ag_rows = extract_ag_transitions(args.expanded_root, output_by_code)
    rows.extend(ag_rows)
    if ag_rows:
        branch_codes["GLOBAL"] = {
            code for codes in branch_codes.values() for code in codes
        }
        branch_codes["GLOBAL"].update(output_by_code)

    enabled_edges = [row for row in rows if row["enabled"]]
    edge_lookup = {
        (row["branch"].lower(), row["source_map_code"].lower(), row["destination_map_code"].lower())
        for row in enabled_edges
    }
    for row in rows:
        destination = row["destination_map_code"].lower()
        row["destination_present_in_branch"] = destination in branch_codes[row["branch"]]
        if row["branch"] == "GLOBAL":
            row["destination_map_outputs"] = sorted(
                {
                    output
                    for (branch, code), outputs in destination_outputs_by_branch_and_code.items()
                    if code == destination
                    for output in outputs
                    if output
                }
            )
        else:
            row["destination_map_outputs"] = sorted(
                output
                for output in destination_outputs_by_branch_and_code.get(
                    (row["branch"].lower(), destination), set()
                )
                if output
            )
        row["reciprocal_in_branch"] = (
            row["branch"].lower(),
            destination,
            row["source_map_code"].lower(),
        ) in edge_lookup

    groups: dict[tuple, dict[str, Any]] = {}
    for row in rows:
        key = (
            row["source_script_sha256"],
            row["source_map_code"].lower(),
            row["enabled"],
            row["transport_kind"],
            tuple(row["icon_anchor"]),
            row["destination_map_code"].lower(),
            tuple(row["approach_point"] or []),
            row["destination_entry_number"],
            tuple(row["parameters"]),
        )
        group = groups.setdefault(
            key,
            {
                **{name: value for name, value in row.items() if name != "branch"},
                "source_branches": [],
            },
        )
        group["source_branches"].append(row["branch"])
        group["destination_map_outputs"] = sorted(
            set(group.get("destination_map_outputs", []))
            | set(row.get("destination_map_outputs", []))
        )
    unique_transitions = list(groups.values())
    unique_transitions.sort(
        key=lambda row: (
            row["source_map_code"].lower(),
            not row["enabled"],
            row["destination_map_code"].lower(),
            row["icon_anchor"],
        )
    )
    for row in unique_transitions:
        row["source_branches"] = sorted(set(row["source_branches"]))

    enabled_unique = [row for row in unique_transitions if row["enabled"]]
    disabled_unique = [row for row in unique_transitions if not row["enabled"]]
    unresolved_targets = [
        row
        for row in enabled_unique
        if not row["destination_present_in_branch"]
    ]
    malformed = [
        row for row in unique_transitions if row["payload_status"] != "ok"
    ]
    summary = {
        "source_scripts": len(script_records),
        "source_transport_calls": source_transport_calls,
        "ag_transition_rules": len(ag_rows),
        "source_transition_edges": len(rows),
        "unique_transitions": len(unique_transitions),
        "unique_enabled_transitions": len(enabled_unique),
        "unique_disabled_transitions": len(disabled_unique),
        "maps_with_enabled_transitions": len(
            {
                (row["source_script_sha256"], row["source_map_code"].lower())
                for row in enabled_unique
            }
        ),
        "parsed_map_outputs_with_enabled_transitions": len(
            {row["source_map_output"] for row in enabled_unique if row.get("source_map_output")}
        ),
        "enabled_edges_without_parsed_source_output": sum(
            not row.get("source_map_output") for row in enabled_unique
        ),
        "enabled_target_missing_in_same_branch": len(unresolved_targets),
        "malformed_payloads": len(malformed),
        "source_state_counts": dict(
            sorted(Counter(row["source_state"] for row in rows).items())
        ),
        "transport_kind_counts": dict(
            sorted(Counter(row["transport_kind"] for row in rows).items())
        ),
        "coordinate_note": (
            "approach_point is local to the source map because it is adjacent to icon_anchor; "
            "transport.OnCreate stores the optional fifth token as destination_entry_number and "
            "calls ChangeSvr(destination_map_code, destination_entry_number). The destination "
            "landing coordinate is selected by the server and is not present in this metadata. "
            "Later AGTransPoint rules do contain an exact destination_landing_point, while "
            "AGTransLine rules calculate it from the crossed boundary."
        ),
    }

    args.map_output_root.mkdir(parents=True, exist_ok=True)
    (args.map_output_root / "map_transitions.json").write_text(
        json.dumps(
            {
                "summary": summary,
                "unique_transitions": unique_transitions,
                "source_transitions": rows,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    write_csv(args.map_output_root / "map_transitions.csv", rows)
    write_csv(args.map_output_root / "map_transitions_enabled.csv", enabled_edges)
    unique_csv_rows = [
        {**row, "branch": " | ".join(row["source_branches"])}
        for row in unique_transitions
    ]
    write_csv(args.map_output_root / "map_transitions_unique.csv", unique_csv_rows)
    write_csv(
        args.map_output_root / "map_transitions_unique_enabled.csv",
        [row for row in unique_csv_rows if row["enabled"]],
    )
    (args.map_output_root / "map_transition_issues.json").write_text(
        json.dumps(
            {
                "unresolved_targets": unresolved_targets,
                "malformed_payloads": malformed,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    g08 = [
        row
        for row in unique_transitions
        if row["source_map_code"].lower() == "g08"
    ]
    (args.map_output_root / "map_transitions_g08.json").write_text(
        json.dumps(g08, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    catalog_nodes = [
        {
            "id": row.get("output", ""),
            "node_kind": "parsed_map",
            "map_code": row.get("map_code", ""),
            "map_name": row.get("map_name", ""),
            "source_branches": row.get("source_branches", []),
            "status": row.get("status", ""),
        }
        for row in map_results
    ]
    external_nodes: dict[str, dict[str, Any]] = {}
    graph_edges = []
    for row in enabled_unique:
        source_id = row.get("source_map_output") or (
            "unresolved:" + row["source_map_code"].lower()
        )
        if not row.get("source_map_output"):
            node = external_nodes.setdefault(
                source_id,
                {
                    "id": source_id,
                    "node_kind": "external_reference",
                    "map_code": row["source_map_code"],
                    "map_name": row.get("source_map_name") or row["source_map_code"],
                    "source_branches": row.get("source_branches", []),
                    "status": "not_in_parsed_catalog",
                    "roles": [],
                },
            )
            node["roles"] = sorted(set(node.get("roles", [])) | {"transition_source"})
        destination_ids = list(row.get("destination_map_outputs", []))
        if not destination_ids:
            destination_id = "unresolved:" + row["destination_map_code"].lower()
            destination_ids = [destination_id]
            node = external_nodes.setdefault(
                destination_id,
                {
                    "id": destination_id,
                    "node_kind": "external_reference",
                    "map_code": row["destination_map_code"],
                    "map_name": row.get("label") or row["destination_map_code"],
                    "source_branches": row.get("source_branches", []),
                    "status": "not_in_parsed_catalog",
                    "roles": [],
                },
            )
            node["roles"] = sorted(set(node.get("roles", [])) | {"transition_target"})
        graph_edges.append(
            {
                **row,
                "source_node_id": source_id,
                "destination_node_ids": destination_ids,
            }
        )
    graph = {
        "schema": "starhome_remake_map_transition_graph_v1",
        "summary": {
            **summary,
            "parsed_map_nodes": len(catalog_nodes),
            "external_reference_nodes": len(external_nodes),
        },
        "nodes": catalog_nodes + sorted(external_nodes.values(), key=lambda node: node["id"]),
        "edges": graph_edges,
    }
    (args.map_output_root / "map_transition_graph.json").write_text(
        json.dumps(graph, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    transitions_by_output: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in unique_transitions:
        if row.get("source_map_output"):
            transitions_by_output[row["source_map_output"]].append(row)
    for map_result in map_results:
        output = map_result.get("output", "")
        if not output:
            continue
        map_transitions = transitions_by_output.get(output, [])
        per_map = {
            "schema": "starhome_remake_map_transitions_v1",
            "map_code": map_result.get("map_code", ""),
            "map_name": map_result.get("map_name", ""),
            "source_branches": map_result.get("source_branches", []),
            "output": output,
            "enabled": [row for row in map_transitions if row["enabled"]],
            "disabled_legacy": [row for row in map_transitions if not row["enabled"]],
            "notes": {
                "approach_point": "本地图中用于自动走近传送对象的坐标",
                "destination_entry_number": "普通传送由服务器用入口号选择目标出生点",
                "destination_landing_point": "仅 AGTransPoint 等新式客户端规则会直接给出",
            },
        }
        map_dir = args.map_output_root / output
        map_dir.mkdir(parents=True, exist_ok=True)
        (map_dir / "transitions.json").write_text(
            json.dumps(per_map, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    print(json.dumps(summary, ensure_ascii=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
