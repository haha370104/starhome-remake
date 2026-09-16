#!/usr/bin/env python3
"""Import the Glory starter rocket and missile effects with semantic paths."""

from __future__ import annotations

from import_glory_starter_combat_assets import _atomic_json, _export_asset


SOURCES = {
    "starter_rocket_launcher_world": {
        "display_name": "初级火箭场景装备",
        "source_logical_path": "pic3/equip/body/CHN_2005_06_28_19_11_48_1153.ale",
        "target": "starter_secondary_weapons/rocket/equipment/aiming",
        "expected_frames": 1,
        "direction_mode": "shared",
        "frames_per_direction": 1,
        "world_visible": False,
        "relationship_evidence": "client_confirmed_FireGun1_m_sMoveSrc",
    },
    "starter_rocket_projectile": {
        "display_name": "初级火箭弹体",
        "source_logical_path": "pic3/bullet/daodan1.ale",
        "target": "starter_secondary_weapons/rocket/projectile/flight",
        "expected_frames": 4,
        "direction_mode": "shared_rotated",
        "frames_per_direction": 4,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_FireGun1_m_sbulletfile",
    },
    "starter_rocket_smoke": {
        "display_name": "初级火箭发射烟雾",
        "source_logical_path": "pic3/effect/yanwu.ale",
        "target": "starter_secondary_weapons/rocket/impact/smoke",
        "expected_frames": 10,
        "direction_mode": "shared",
        "frames_per_direction": 10,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_FireGunBase_Action",
    },
    "starter_rocket_impact": {
        "display_name": "初级火箭爆炸",
        "source_logical_path": "pic3/effect/CHN_2005_06_28_19_11_54_1154.ale",
        "target": "starter_secondary_weapons/rocket/impact/explosion",
        "expected_frames": 10,
        "direction_mode": "shared",
        "frames_per_direction": 10,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_m_szBulletAvi_index_3",
    },
    "starter_missile_projectile": {
        "display_name": "初级导弹弹体",
        "source_logical_path": "pic3/bullet/missile.ale",
        "target": "starter_secondary_weapons/missile/projectile/flight",
        "expected_frames": 1,
        "direction_mode": "shared_rotated",
        "frames_per_direction": 1,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_Missile1_m_sbulletfile",
    },
    "starter_missile_world": {
        "display_name": "初级导弹场景装备",
        "source_logical_path": "pic3/equip/body/CHN_2005_06_28_18_32_39_754.ale",
        "target": "starter_secondary_weapons/missile/equipment/aiming",
        "expected_frames": 1,
        "direction_mode": "shared",
        "frames_per_direction": 1,
        "world_visible": False,
        "relationship_evidence": "client_confirmed_Missile1_m_sMoveSrc",
    },
    "starter_missile_impact": {
        "display_name": "初级导弹爆炸",
        "source_logical_path": "pic3/effect/chn_2005_06_28_18_32_33_753.ale",
        "target": "starter_secondary_weapons/missile/impact/explosion",
        "expected_frames": 8,
        "direction_mode": "shared",
        "frames_per_direction": 8,
        "world_visible": True,
        "relationship_evidence": "client_confirmed_Missile1_m_nBulletAvi_4",
    },
}


def main() -> None:
    audit = {asset_id: _export_asset(asset_id, spec) for asset_id, spec in SOURCES.items()}
    from import_glory_starter_combat_assets import TARGET_ROOT

    _atomic_json(
        TARGET_ROOT / "starter_secondary_weapons" / "source_manifest.json",
        {
            "schema_version": 1,
            "source_release": "starhome_lz_ry",
            "assets": audit,
        },
    )
    print(f"IMPORTED_GLORY_SECONDARY_WEAPONS ({len(audit)} assets)")


if __name__ == "__main__":
    main()
