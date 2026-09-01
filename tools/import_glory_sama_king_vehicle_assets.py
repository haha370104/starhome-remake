#!/usr/bin/env python3
"""按需导入撒玛王战车及天神之怒的业务化世界表现资源。"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any

from import_glory_starter_combat_assets import (
    TARGET_ROOT,
    _action,
    _atomic_json,
    _export_asset,
)


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_MANIFEST = TARGET_ROOT / "combat_visual_manifest.json"
SOURCE_MANIFEST = TARGET_ROOT / "sama_king_combat_vehicle" / "source_manifest.json"
CHASSIS_DEFINITION_ID = "glory_equipment_tank1000_27ae5e8059"
WEAPON_DEFINITION_ID = "glory_equipment_gun1000_c4c24e2500"
ACTOR_ID = "sama_king_combat_vehicle"

SOURCES: dict[str, dict[str, Any]] = {
    "sama_king_vehicle_chassis": {
        "display_name": "撒玛王战车",
        "source_logical_path": "pic3/equip/body/tank5.ale",
        "target": "sama_king_combat_vehicle/chassis/locomotion",
        "expected_frames": 32,
        "direction_mode": "eight_way",
        "frames_per_direction": 4,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_tank1000_world_source",
    },
    "sama_king_vehicle_shadow": {
        "display_name": "撒玛王战车阴影",
        "source_logical_path": "pic3/equip/tank5shadow.ale",
        "target": "sama_king_combat_vehicle/chassis/shadow",
        "expected_frames": 8,
        "direction_mode": "eight_way",
        "frames_per_direction": 1,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_tank_shadow_mapping",
    },
    "divine_wrath_energy_cannon": {
        "display_name": "天神之怒",
        "source_logical_path": "pic3/equip/body/gun1.ale",
        "target": "sama_king_combat_vehicle/weapon/aiming",
        "expected_frames": 8,
        "direction_mode": "eight_way",
        "frames_per_direction": 1,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_gun1000_world_source",
    },
}


def _resource(asset_id: str) -> str:
    """返回指定业务素材生成后的 Godot SpriteFrames 路径。"""
    return "res://assets/equipment_world/" + str(SOURCES[asset_id]["target"]) + "/animation_frames.tres"


def _actor(source_by_id: dict[str, dict[str, Any]], existing: dict[str, Any]) -> dict[str, Any]:
    """组装撒玛王底盘、阴影、主炮，并复用已经导入的通用副武器层。"""
    chassis_offset = list(source_by_id["sama_king_vehicle_chassis"]["coordinate_bounds"][:2])
    shadow_offset = list(source_by_id["sama_king_vehicle_shadow"]["coordinate_bounds"][:2])
    weapon_offset = list(source_by_id["divine_wrath_energy_cannon"]["coordinate_bounds"][:2])
    layers: list[dict[str, Any]] = [
        {
            "id": "shadow",
            "z_index": -1,
            "actions": {
                action: _action(
                    _resource("sama_king_vehicle_shadow"), 1, loop=False,
                    offset=shadow_offset, fps=0.0,
                )
                for action in ("idle", "move", "attack")
            },
        },
        {
            "id": "chassis",
            "z_index": 0,
            "actions": {
                "idle": _action(
                    _resource("sama_king_vehicle_chassis"), 4, loop=False,
                    offset=chassis_offset, fps=0.0,
                ),
                "move": _action(
                    _resource("sama_king_vehicle_chassis"), 4, offset=chassis_offset
                ),
            },
        },
        {
            "id": "primary_weapon",
            "z_index": 1,
            "actions": {
                action: _action(
                    _resource("divine_wrath_energy_cannon"), 1,
                    loop=action != "attack", offset=weapon_offset,
                )
                for action in ("idle", "move", "attack")
            },
        },
    ]
    starter_actor = existing.get("actors", {}).get("starter_combat_vehicle", {})
    for layer in starter_actor.get("layers", []):
        if layer.get("id") in {"rocket_weapon", "missile_weapon"}:
            layers.append(copy.deepcopy(layer))
    return {
        "display_name": "撒玛王战车",
        "default_action": "idle",
        "animation_evidence": {
            "directional_coverage": "source_confirmed_eight_way",
            "move_cycle": "source_confirmed_four_frames_per_direction",
            "idle_cycle": "reconstructed_directional_first_frame",
            "equipment_source": "current_player_fixed_vehicle_loadout",
        },
        "layers": layers,
        "installed_components": [
            "sama_king_vehicle_chassis",
            "divine_wrath_energy_cannon",
        ],
    }


def migrate() -> None:
    """生成按需资源并把实际底盘到 actor 的关系写入运行时清单。"""
    exported = {
        asset_id: _export_asset(asset_id, specification)
        for asset_id, specification in SOURCES.items()
    }
    _atomic_json(
        SOURCE_MANIFEST,
        {
            "schema_version": 1,
            "source_release": "starhome_lz_ry",
            "assets": exported,
        },
    )
    manifest = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    starter_actor = manifest.get("actors", {}).get("starter_combat_vehicle", {})
    starter_shadow_action: dict[str, Any] = {}
    for layer in starter_actor.get("layers", []):
        if layer.get("id") == "shadow":
            starter_shadow_action = copy.deepcopy(layer.get("actions", {}).get("idle", {}))
            break
    if starter_shadow_action:
        manifest.setdefault("components", {})["recruit_tank_shadow"] = {
            "render_policy": "world_layer",
            "action": starter_shadow_action,
        }
    manifest.setdefault("components", {}).update(
        {
            "sama_king_vehicle_chassis": {
                "render_policy": "world_layer",
                "action": _action(
                    _resource("sama_king_vehicle_chassis"), 4,
                    offset=list(exported["sama_king_vehicle_chassis"]["coordinate_bounds"][:2]),
                ),
            },
            "divine_wrath_energy_cannon": {
                "render_policy": "world_layer",
                "action": _action(
                    _resource("divine_wrath_energy_cannon"), 1,
                    offset=list(exported["divine_wrath_energy_cannon"]["coordinate_bounds"][:2]),
                ),
            },
            "sama_king_vehicle_shadow": {
                "render_policy": "world_layer",
                "action": _action(
                    _resource("sama_king_vehicle_shadow"), 1, loop=False,
                    offset=list(exported["sama_king_vehicle_shadow"]["coordinate_bounds"][:2]),
                    fps=0.0,
                ),
            },
        }
    )
    manifest.setdefault("actors", {})[ACTOR_ID] = _actor(exported, manifest)
    manifest["vehicle_actor_by_chassis_definition"] = {
        "recruit_tank": "starter_combat_vehicle",
        CHASSIS_DEFINITION_ID: ACTOR_ID,
    }
    manifest["vehicle_component_by_equipment_definition"] = {
        "recruit_tank": "recruit_tank",
        "recruit_energy_cannon": "recruit_energy_cannon",
        CHASSIS_DEFINITION_ID: "sama_king_vehicle_chassis",
        WEAPON_DEFINITION_ID: "divine_wrath_energy_cannon",
    }
    manifest["vehicle_shadow_component_by_chassis_definition"] = {
        "recruit_tank": "recruit_tank_shadow",
        CHASSIS_DEFINITION_ID: "sama_king_vehicle_shadow",
    }
    _atomic_json(RUNTIME_MANIFEST, manifest)


def audit() -> list[str]:
    """校验业务资源、实际底盘映射和三层 actor 均已生成。"""
    errors: list[str] = []
    if not RUNTIME_MANIFEST.is_file() or not SOURCE_MANIFEST.is_file():
        return ["撒玛王战车清单尚未生成"]
    manifest = json.loads(RUNTIME_MANIFEST.read_text(encoding="utf-8"))
    actor = manifest.get("actors", {}).get(ACTOR_ID, {})
    if manifest.get("vehicle_actor_by_chassis_definition", {}).get(CHASSIS_DEFINITION_ID) != ACTOR_ID:
        errors.append("撒玛王底盘未映射到实际战车 actor")
    layer_ids = {layer.get("id") for layer in actor.get("layers", [])}
    if not {"shadow", "chassis", "primary_weapon"}.issubset(layer_ids):
        errors.append("撒玛王战车缺少底盘、阴影或主炮图层")
    for specification in SOURCES.values():
        target = TARGET_ROOT / str(specification["target"])
        if not (target / "animation_frames.tres").is_file() or not (target / "frames.png").is_file():
            errors.append(f"业务资源缺失：{specification['target']}")
    return errors


def main() -> int:
    """按参数生成资源，并始终执行只读审计。"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--migrate", action="store_true")
    arguments = parser.parse_args()
    if arguments.migrate:
        migrate()
    errors = audit()
    print(json.dumps({"actor": ACTOR_ID, "errors": errors}, ensure_ascii=False, indent=2))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
