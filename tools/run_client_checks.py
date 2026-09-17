#!/usr/bin/env python3
"""Run isolated client regressions, rejecting script errors even on exit code zero."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
TESTS = (
    "domain/vehicle_socket_model_test.gd",
    "domain/equipment_processing_model_test.gd",
    "domain/equipment_maintenance_model_test.gd",
    "domain/equipment_usage_model_test.gd",
    "domain/equipment_ammunition_test.gd",
    "domain/extra_attribute_model_test.gd",
    "domain/equipment_strengthening_model_test.gd",
    "domain/equipment_strengthening_integration_test.gd",
    "server/commerce/equipment_strengthening_authority_test.gd",
    "ui/runtime/equipment_strengthening_panel_test.gd",
    "domain/armor_refinement_test.gd",
    "server/commerce/armor_refinement_authority_test.gd",
    "ui/runtime/armor_refinement_panel_test.gd",
    "domain/clothing_improvement_model_test.gd",
    "domain/clothing_improvement_integration_test.gd",
    "domain/fashion_hat_compatibility_test.gd",
    "server/commerce/clothing_improvement_authority_test.gd",
    "ui/runtime/clothing_improvement_panel_test.gd",
    "domain/equipment_memory_model_test.gd",
    "domain/equipment_quality_test.gd",
    "client/presentation/combat/generator_status_view_test.gd",
    "server/combat/generator_rules_test.gd",
    "domain/generator_loadout_test.gd",
    "server/combat/generator_combat_test.gd",
    "server/combat/generator_persistence_test.gd",
    "domain/equipment_forging_model_test.gd",
    "domain/equipment_forging_integration_test.gd",
    "domain/equipment_forging_actions_test.gd",
    "domain/equipment_memory_forging_test.gd",
    "server/commerce/equipment_forging_authority_test.gd",
    "ui/runtime/equipment_forging_panel_test.gd",
    "domain/equipment_dismantle_test.gd",
    "domain/personal_warehouse_test.gd",
    "server/commerce/equipment_dismantle_authority_test.gd",
    "ui/runtime/equipment_dismantle_panel_test.gd",
    "domain/equipment_memory_transfer_test.gd",
    "server/commerce/equipment_memory_authority_test.gd",
    "ui/runtime/equipment_memory_panel_test.gd",
    "domain/extra_attribute_integration_test.gd",
    "server/commerce/extra_attribute_authority_test.gd",
    "ui/runtime/extra_attribute_panel_test.gd",
    "server/combat/equipment_usage_authority_test.gd",
    "server/commerce/equipment_maintenance_authority_test.gd",
    "ui/runtime/equipment_maintenance_panel_test.gd",
    "server/commerce/equipment_processing_authority_test.gd",
    "ui/runtime/equipment_processing_panel_test.gd",
    "server/commerce/vehicle_socket_authority_test.gd",
    "ui/runtime/vehicle_socket_panel_test.gd",
    "domain/clothing_enhancement_test.gd",
    "server/commerce/clothing_enhancement_authority_test.gd",
    "content/glory_ale_sprite_repository_test.gd",
    "integration/recovered_assets_runtime_test.gd",
    "domain/reward_pipeline_test.gd",
    "server/reward_authority_test.gd",
    "server/combat/loot_pickup_authority_test.gd",
    "domain/consumable_and_stack_test.gd",
    "server/consumable_authority_test.gd",
    "ui/runtime/inventory_context_menu_test.gd",
    "server/mining/authoritative_mining_module_test.gd",
    "domain/player_rich_model_test.gd",
    "server/commerce/premium_shop_and_attachments_test.gd",
    "server/commerce/premium_upgrade_materials_test.gd",
    "server/commerce/attachment_upgrade_test.gd",
    "server/commerce/daily_activity_test.gd",
    "server/combat/upgrade_material_supply_test.gd",
    "server/combat/drop_expectations_and_upgrades_test.gd",
    "server/combat/elite_population_test.gd",
    "server/combat/enhancement_population_test.gd",
    "server/combat/clothing_stats_test.gd",
    "server/combat/clothing_traits_test.gd",
    "server/combat/glory_field_population_test.gd",
    "server/map_residency_test.gd",
    "server/combat/monster_wander_timing_test.gd",
    "server/combat/corrosive_attack_test.gd",
    "client/presentation/combat/monster_attack_effect_controller_test.gd",
    "client/presentation/combat/monster_hit_presentation_test.gd",
    "client/presentation/combat/monster_hover_name_test.gd",
    "server/manufacturing/industrial_supply_chain_test.gd",
    "server/authoritative_server_smoke_test.gd",
    "ui/runtime/daily_hud_and_assistant_test.gd",
    "ui/runtime/premium_shop_ui_test.gd",
    "ui/runtime/attachment_upgrade_ui_test.gd",
    "ui/runtime/clothing_enhancement_ui_test.gd",
    "integration/combat_click_routing_test.gd",
    "ui/runtime/map_navigation_test.gd",
    "integration/map_navigation_scene_test.gd",
    "integration/local_movement_speed_sync_test.gd",
    "domain/achievements_test.gd",
    "server/achievements_authority_test.gd",
    "ui/runtime/achievements_panel_test.gd",
    "ui/runtime/reusable_player_ui_test.gd",
    "ui/runtime/player_panels_runtime_test.gd",
    "ui/runtime/inventory_drag_gesture_test.gd",
    "ui/runtime/item_tooltip_layout_test.gd",
    "ui/runtime/hud_runtime_smoke_test.gd",
    "ui/central_system_message_feed_test.gd",
    "ui/runtime/navigation_windows_test.gd",
    "ui/runtime/weapon_merchant_runtime_test.gd",
    "ui/runtime/training_tasks_runtime_test.gd",
    "client/network/client_network_smoke_test.gd",
    "client/presentation/hall_multiplayer_presenter_smoke_test.gd",
    "client/presentation/player_error_messages_test.gd",
    "client/presentation/client_map_preloader_smoke_test.gd",
    "client/presentation/combat/weapon_attack_visual_controller_test.gd",
    "client/presentation/combat/ground_loot_world_controller_test.gd",
    "client/presentation/mining/mineral_world_controller_test.gd",
    "client/world/world_facility_interaction_test.gd",
    "integration/client_state_seam_characterization_test.gd",
    "integration/npc_action_window_handoff_test.gd",
    "integration/active_world_transition_view_smoke_test.gd",
    "integration/field_transition_presentation_test.gd",
    "integration/d04_player_vehicle_presentation_test.gd",
    "integration/equipped_weapon_presentation_test.gd",
    "server/combat/equipped_vehicle_authority_test.gd",
    "server/combat/vehicle_energy_endurance_test.gd",
    "domain/weapon_merchant_domain_test.gd",
    "integration/map_transition_scene_smoke_test.gd",
    "integration/persisted_map_startup_scene_test.gd",
    "integration/in_process_authoritative_transport_test.gd",
)


def main() -> int:
    """Preserve complete logs and a machine readable summary of this exact run."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, type=Path)
    args = parser.parse_args()
    if not args.godot.is_file():
        parser.error("Godot executable does not exist")
    for check in ("tests/test_check_client_architecture.py", "check_client_architecture.py"):
        result = subprocess.run([sys.executable, "-X", "utf8", str(ROOT / "tools" / check)], cwd=ROOT)
        if result.returncode:
            return result.returncode
    output_dir = ROOT / ".godot" / f"client-checks-{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}"
    output_dir.mkdir(parents=True)
    environment = {**os.environ, "STARHOME_COMBAT_TRACE": "0"}
    results = []
    scripts = ["res://tools/check_gdscript_warnings.gd"] + [f"res://tests/{test}" for test in TESTS]
    for script in scripts:
        name = Path(script).stem
        log_path = output_dir / f"{name}.log"
        command = [str(args.godot.resolve()), "--headless", "--path", str(ROOT), "--log-file", str(log_path), "--script", script]
        started = time.monotonic()
        try:
            process = subprocess.run(command, cwd=ROOT, env=environment, capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=120)
            output = process.stdout + process.stderr
            fatal_lines = [line for line in output.splitlines() if re.search(r"SCRIPT ERROR:|Parse Error:|Failed to load script|^ERROR:", line)
                           and line != "ERROR: Failed to read the root certificate store."]
            passed = process.returncode == 0 and not fatal_lines
            reason = "\n".join(fatal_lines) or f"exit={process.returncode}"
            # Engine output files are retained separately from captured stdout/stderr.
            log_path.with_suffix(".output.log").write_text(output, encoding="utf-8")
        except subprocess.TimeoutExpired:
            passed, reason = False, "timeout after 120s; subprocess terminated"
        result = {"script": script, "passed": passed, "reason": reason, "seconds": round(time.monotonic() - started, 2)}
        results.append(result)
        print(f"{'PASS' if passed else 'FAIL'} {name} ({result['seconds']}s)", flush=True)
        if not passed:
            print(reason, flush=True)
    report = output_dir / "summary.json"
    report.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{sum(result['passed'] for result in results)}/{len(results)} passed; report: {report}", flush=True)
    return 0 if all(result["passed"] for result in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
