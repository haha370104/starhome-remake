#!/usr/bin/env python3
"""Audit Stage 3 gameplay definitions against the Glory source evidence."""

from __future__ import annotations

import csv
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[1]
CATALOG_PATH = PROJECT_ROOT / "data/gameplay/stage3/catalog_v1.json"
GLORY_RAW_ROOT = PROJECT_ROOT.parent / "starhome_lz_ry_full/raw"
ALLOWED_EVIDENCE_STATUSES = {
    "client_confirmed",
    "client_derived",
    "not_applicable",
    "remake_rule",
    "reconstructed_default",
    "unknown",
}
SEMANTIC_ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
FORBIDDEN_RUNTIME_PATTERNS = (
    re.compile(r"(?:^|[/\\])pic(?:2|3)?(?:[/\\]|$)", re.IGNORECASE),
    re.compile(r"\.ale(?:$|[^a-z])", re.IGNORECASE),
    re.compile(r"\b\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}_\d+\b"),
    re.compile(r"\bNpc(?:ChengChong|YouChong|LightBall|Slm)\d\b"),
)


class AuditFailure(RuntimeError):
    """Represent a deterministic Stage 3 content-audit failure."""


def load_json(path: Path) -> dict[str, Any]:
    """Load one UTF-8 JSON object.

    Args:
        path: JSON file to read.

    Returns:
        Parsed JSON object.
    """

    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise AuditFailure(f"JSON root must be an object: {path}")
    return value


def sha256_file(path: Path) -> str:
    """Calculate the lowercase SHA-256 digest of a file.

    Args:
        path: File whose bytes should be hashed.

    Returns:
        Lowercase hexadecimal SHA-256 digest.
    """

    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_project_reference(reference: str) -> Path:
    """Resolve a project resource path or project-relative audit path.

    Args:
        reference: ``res://`` resource path or a path relative to the project root.

    Returns:
        Absolute filesystem path.
    """

    if reference.startswith("res://"):
        return PROJECT_ROOT / reference.removeprefix("res://")
    return (PROJECT_ROOT / reference).resolve()


def assert_equal(actual: Any, expected: Any, label: str) -> None:
    """Require two audit values to be equal.

    Args:
        actual: Value obtained from the repository or source evidence.
        expected: Expected immutable value.
        label: Human-readable assertion label.

    Returns:
        None.
    """

    if actual != expected:
        raise AuditFailure(f"{label}: expected {expected!r}, got {actual!r}")


def canonical_csv_row(path: Path, selector: dict[str, str]) -> tuple[dict[str, str], str]:
    """Find and hash exactly one CSV row using stable canonical JSON.

    Args:
        path: UTF-8 CSV source catalog.
        selector: Field/value pairs that uniquely identify the row.

    Returns:
        Tuple containing the selected row and its canonical SHA-256 digest.
    """

    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        matches = [
            row
            for row in csv.DictReader(stream)
            if all(row.get(key) == str(value) for key, value in selector.items())
        ]
    if len(matches) != 1:
        raise AuditFailure(f"selector {selector!r} matched {len(matches)} rows in {path}")
    row = matches[0]
    encoded = json.dumps(
        row, ensure_ascii=False, sort_keys=True, separators=(",", ":")
    ).encode("utf-8")
    return row, hashlib.sha256(encoded).hexdigest()


def iter_runtime_strings(value: Any, path: str = "root") -> Iterable[tuple[str, str]]:
    """Yield strings outside evidence-only ``source_audit`` subtrees.

    Args:
        value: JSON-compatible value to traverse.
        path: Diagnostic path for the current value.

    Returns:
        Iterable of diagnostic paths and runtime string values.
    """

    if isinstance(value, dict):
        for key, child in value.items():
            if key == "source_audit":
                continue
            yield from iter_runtime_strings(child, f"{path}.{key}")
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from iter_runtime_strings(child, f"{path}[{index}]")
    elif isinstance(value, str):
        yield path, value


def audit_runtime_names(documents: Iterable[tuple[str, dict[str, Any]]]) -> int:
    """Reject legacy source naming from runtime-facing fields.

    Args:
        documents: Pairs of document labels and parsed JSON objects.

    Returns:
        Number of runtime string values checked.
    """

    checked = 0
    for label, document in documents:
        for field_path, value in iter_runtime_strings(document, label):
            checked += 1
            for pattern in FORBIDDEN_RUNTIME_PATTERNS:
                if pattern.search(value):
                    raise AuditFailure(
                        f"legacy runtime name matched {pattern.pattern!r} at {field_path}: {value!r}"
                    )
    return checked


def audit_evidence_map(definition: dict[str, Any], paths: Iterable[str]) -> int:
    """Require evidence metadata for runtime fields in one definition.

    Args:
        definition: Equipment or monster definition containing an evidence map.
        paths: Runtime field paths that must have evidence entries.

    Returns:
        Number of evidence entries checked.
    """

    evidence = definition.get("evidence", {})
    checked = 0
    for field_path in paths:
        item = evidence.get(field_path)
        if not isinstance(item, dict):
            raise AuditFailure(f"{definition['id']} lacks evidence for {field_path}")
        status = item.get("status")
        if status not in ALLOWED_EVIDENCE_STATUSES:
            raise AuditFailure(
                f"{definition['id']} has invalid evidence status {status!r} for {field_path}"
            )
        if status == "unknown" and not item.get("reason"):
            raise AuditFailure(f"{definition['id']} unknown {field_path} lacks a reason")
        if status == "reconstructed_default" and not item.get("reason"):
            raise AuditFailure(
                f"{definition['id']} reconstructed {field_path} lacks a reason"
            )
        checked += 1
    return checked


def audit_source_assets(definition: dict[str, Any]) -> int:
    """Verify hashed Glory source assets for one equipment definition.

    Args:
        definition: Equipment definition with ``source_audit.source_assets``.

    Returns:
        Number of source assets checked.
    """

    checked = 0
    for asset in definition["source_audit"].get("source_assets", []):
        path = GLORY_RAW_ROOT / asset["path"]
        if not path.is_file():
            raise AuditFailure(f"missing Glory source asset: {path}")
        assert_equal(sha256_file(path), asset["sha256"], f"source asset hash {path}")
        checked += 1
    return checked


def audit_equipment(document: dict[str, Any]) -> tuple[int, int]:
    """Audit starter equipment rows, evidence, and source assets.

    Args:
        document: Parsed starter-loadout definition document.

    Returns:
        Tuple containing evidence-entry and source-asset counts.
    """

    catalog_audited_ids = {"recruit_tank", "beginner_engine", "recruit_energy_cannon"}
    secondary_weapon_ids = {"starter_rocket_launcher", "starter_missile"}
    expected_ids = catalog_audited_ids | secondary_weapon_ids
    definitions = document.get("definitions", [])
    assert_equal({item.get("id") for item in definitions}, expected_ids, "starter ids")
    evidence_count = 0
    asset_count = 0
    for definition in definitions:
        if not SEMANTIC_ID_RE.fullmatch(definition["id"]):
            raise AuditFailure(f"non-semantic equipment id: {definition['id']!r}")
        if definition["id"] in secondary_weapon_ids:
            if not definition.get("stats"):
                raise AuditFailure(f"secondary weapon has no runtime stats: {definition['id']}")
            resources = definition.get("presentation", {}).get("resources", {})
            if not resources:
                raise AuditFailure(f"secondary weapon has no presentation resources: {definition['id']}")
            for resource in resources.values():
                if not resolve_project_reference(str(resource)).is_file():
                    raise AuditFailure(
                        f"secondary weapon presentation resource is missing: {resource}"
                    )
            audit = definition.get("source_audit", {})
            if audit.get("source_release") != "starhome_lz_ry" or not audit.get("source_file"):
                raise AuditFailure(f"secondary weapon source audit is incomplete: {definition['id']}")
            continue
        required_evidence = [f"stats.{key}" for key in definition["stats"]]
        required_evidence.extend(f"unknowns.{key}" for key in definition["unknowns"])
        required_evidence.append("presentation.resources")
        evidence_count += audit_evidence_map(definition, required_evidence)
        audit = definition["source_audit"]
        source_path = resolve_project_reference(audit["catalog"])
        _, row_hash = canonical_csv_row(source_path, audit["row_selector"])
        assert_equal(row_hash, audit["row_sha256"], f"equipment row hash {definition['id']}")
        asset_count += audit_source_assets(definition)
    return evidence_count, asset_count


def audit_monsters(document: dict[str, Any]) -> tuple[int, int, int]:
    """Audit monster values, evidence, animation references, and source rows.

    Args:
        document: Parsed monster definition document.

    Returns:
        Tuple containing evidence-entry, presentation-resource, and runtime-drop counts.
    """

    expected_ids = {"om_adult", "om_larva", "photosensitive_orb", "toxic_gel"}
    definitions = document.get("definitions", [])
    assert_equal({item.get("id") for item in definitions}, expected_ids, "monster ids")
    evidence_count = 0
    resource_count = 0
    drop_count = 0
    for definition in definitions:
        if not SEMANTIC_ID_RE.fullmatch(definition["id"]):
            raise AuditFailure(f"non-semantic monster id: {definition['id']!r}")
        required_evidence = [f"stats.{key}" for key in definition["stats"]]
        required_evidence.extend(f"combat.{key}" for key in definition["combat"])
        required_evidence.extend(("drops", "rewards", "presentation"))
        evidence_count += audit_evidence_map(definition, required_evidence)
        drops = definition["drops"]
        if not isinstance(drops, list) or not drops:
            raise AuditFailure(f"runtime drops must be configured: {definition['id']}")
        for drop in drops:
            if (
                not isinstance(drop, dict)
                or not SEMANTIC_ID_RE.fullmatch(str(drop.get("item_definition_id", "")))
                or int(drop.get("minimum_quantity", 0)) <= 0
                or int(drop.get("maximum_quantity", 0)) < int(drop.get("minimum_quantity", 0))
                or not 0.0 <= float(drop.get("chance", -1.0)) <= 1.0
            ):
                raise AuditFailure(f"invalid runtime drop entry: {definition['id']}")
            drop_count += 1
        audit = definition["source_audit"]
        source_path = resolve_project_reference(audit["catalog"])
        row, row_hash = canonical_csv_row(source_path, audit["row_selector"])
        assert_equal(row_hash, audit["row_sha256"], f"monster row hash {definition['id']}")
        assert_equal(
            row["produce_obj"],
            audit["untrusted_drop_candidate"],
            f"untrusted drop evidence {definition['id']}",
        )
        assert_equal(audit["runtime_drop_imported"], False, "runtime drop gate")
        for resource in definition["presentation"].values():
            resource_path = resolve_project_reference(resource)
            if not resource_path.is_file():
                raise AuditFailure(f"missing monster presentation resource: {resource_path}")
            resource_count += 1
    return evidence_count, resource_count, drop_count


def world_to_cell(position: list[int], cell_size: tuple[float, float]) -> tuple[int, int]:
    """Convert a world position using the reconstructed FancyBoxII diamond transform.

    Args:
        position: Two-element world-space coordinate.
        cell_size: Navigation-cell width and vertical step.

    Returns:
        Integer navigation-grid coordinate.
    """

    world_x, world_y = position
    cell_x_size, cell_y_size = cell_size
    projected_y = world_y * cell_x_size / (2.0 * cell_y_size) + cell_x_size * 0.5
    positive_diagonal = int((projected_y + world_x) // cell_x_size)
    negative_diagonal = int((projected_y - world_x) // cell_x_size)
    return ((positive_diagonal - negative_diagonal) // 2, positive_diagonal + negative_diagonal)


def audit_encounters(document: dict[str, Any], monster_ids: set[str]) -> int:
    """Audit reconstructed D04 spawn policy against the Glory navigation grid.

    Args:
        document: Parsed D04 encounter definition.
        monster_ids: Valid semantic monster identifiers.

    Returns:
        Number of spawn groups checked.
    """

    assert_equal(document.get("map_id"), "d04_field_zone", "encounter map id")
    navigation_path = resolve_project_reference(document["source_audit"]["navigation"])
    assert_equal(
        sha256_file(navigation_path),
        document["source_audit"]["navigation_sha256"],
        "D04 navigation hash",
    )
    navigation = navigation_path.read_bytes()
    grid_width, grid_height = 101, 800
    assert_equal(len(navigation), grid_width * grid_height, "D04 navigation size")
    policy = document.get("population_policy", {})
    distribution = policy.get("spawn_distribution", "fixed_anchors")
    if distribution == "full_walkable_map":
        if not any(navigation):
            raise AuditFailure("full-map spawn policy requires walkable navigation cells")
        if int(policy.get("maximum_population", 0)) <= 0:
            raise AuditFailure("full-map spawn policy requires a positive population cap")
        if float(policy.get("minimum_spawn_separation", 0.0)) <= 0.0:
            raise AuditFailure("full-map spawn policy requires a positive entity separation")
    for group in document["spawn_groups"]:
        if group["monster_id"] not in monster_ids:
            raise AuditFailure(f"unknown encounter monster id: {group['monster_id']}")
        if distribution == "full_walkable_map":
            if float(group.get("weight", 0.0)) <= 0.0:
                raise AuditFailure(f"full-map spawn group requires a positive weight: {group['group_id']}")
            continue
        cell_x, cell_y = world_to_cell(group["anchor"], (48.0, 12.0))
        for neighbor_y in range(cell_y - 4, cell_y + 5):
            for neighbor_x in range(cell_x - 4, cell_x + 5):
                inside = 0 <= neighbor_x < grid_width and 0 <= neighbor_y < grid_height
                if not inside or navigation[neighbor_y * grid_width + neighbor_x] == 0:
                    raise AuditFailure(
                        f"spawn anchor lacks a clear navigation neighborhood: {group['group_id']}"
                    )
    evidence = document.get("evidence", {})
    for key in ("map_id", "spawn_groups", "authoritative_spawn_data"):
        status = evidence.get(key, {}).get("status")
        if status not in ALLOWED_EVIDENCE_STATUSES:
            raise AuditFailure(f"invalid encounter evidence status for {key}: {status!r}")
    return len(document["spawn_groups"])


def main() -> int:
    """Run the complete Stage 3 content and source-evidence audit.

    Args:
        None.

    Returns:
        Process exit code, zero when all checks pass.
    """

    try:
        catalog = load_json(CATALOG_PATH)
        documents: dict[str, dict[str, Any]] = {}
        expected_versions = {
            "starter_loadout": "stage3_v1",
            "monsters": "stage3_v1",
            "d04_encounters": "stage3_v1",
            "glory_monsters": "glory-runtime-v1",
            "glory_encounters": "glory-runtime-v1",
        }
        for key, reference in catalog["definitions"].items():
            path = resolve_project_reference(reference)
            if not path.is_file():
                raise AuditFailure(f"missing catalog definition {key}: {path}")
            documents[key] = load_json(path)
            assert_equal(
                documents[key]["content_version"], expected_versions[key], f"{key} version"
            )
        for source_key in ("equipment_catalog", "monster_catalog"):
            source_path = resolve_project_reference(catalog["source_audit"][source_key])
            expected_hash = catalog["source_audit"][f"{source_key}_sha256"]
            assert_equal(sha256_file(source_path), expected_hash, f"{source_key} hash")
        equipment_evidence, equipment_assets = audit_equipment(
            documents["starter_loadout"]
        )
        monster_evidence, monster_resources, runtime_drops = audit_monsters(
            documents["monsters"]
        )
        monster_ids = {item["id"] for item in documents["monsters"]["definitions"]}
        encounter_groups = audit_encounters(documents["d04_encounters"], monster_ids)
        runtime_strings = audit_runtime_names(
            [
                ("catalog", catalog),
                ("starter_loadout", documents["starter_loadout"]),
                ("monsters", documents["monsters"]),
                ("d04_encounters", documents["d04_encounters"]),
            ]
        )
    except (AuditFailure, KeyError, TypeError, ValueError) as error:
        print(f"STAGE3 AUDIT FAILED: {error}", file=sys.stderr)
        return 1

    print(
        "STAGE3 AUDIT PASSED: "
        f"equipment=5 source_assets={equipment_assets} equipment_evidence={equipment_evidence} "
        f"monsters=4 monster_resources={monster_resources} monster_evidence={monster_evidence} "
        f"encounter_groups={encounter_groups} runtime_strings={runtime_strings} "
        f"runtime_drops={runtime_drops} source_drop_grammar_imported=0"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
