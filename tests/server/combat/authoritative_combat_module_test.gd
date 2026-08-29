extends SceneTree

const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const VehicleAssemblyCalculator := preload("res://scripts/domain/combat/vehicle_assembly_calculator.gd")
const VehicleCombatStateScript := preload("res://scripts/domain/combat/vehicle_combat_state.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")
const MAP_INSTANCE_ID := "field.instance.1"
const ABILITY_ID := "energy_cannon.primary"

var failures: Array[String] = []
var assertions := 0


## 初始化当前模块或独立测试夹具。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _initialize() -> void:
	_test_vehicle_assembly_and_energy_domains()
	_test_energy_cannon_authority_state_machine()
	_test_single_death_and_thirty_second_respawn()
	_test_seeded_damage_is_reproducible()
	_test_three_engagement_policies()
	_test_five_second_wander_interval()
	_test_authoritative_ground_loot_lifecycle()
	_test_authoritative_self_repair_cycles()
	_test_monster_projectile_timing()
	_test_monster_projectile_can_be_dodged()
	if failures.is_empty():
		print("AUTHORITATIVE_COMBAT_MODULE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 执行 `test_vehicle_assembly_and_energy_domains` 对应的模块操作。
func _test_vehicle_assembly_and_energy_domains() -> void:
	var assembly_result: Variant = _assembly_result()
	_expect(assembly_result.is_ok, "injected rookie vehicle assembly should calculate")
	if not assembly_result.is_ok:
		return
	var assembly: Dictionary = assembly_result.value
	_expect(int(assembly["total_weight"]) == 200, "chassis and component weights should aggregate")
	_expect(is_equal_approx(assembly["effective_propulsion"], 10.0), "underqualified driver should receive scaled propulsion")
	_expect(is_equal_approx(assembly["movement_speed"], 75.0), "weight and propulsion should determine capped speed")
	_expect(int(assembly["max_health"]) == 70, "only chassis health should define vehicle combat health")
	_expect(not assembly.has("max_durability"), "equipment hardiness must not leak into vehicle combat health")
	_expect(is_equal_approx(assembly["reserve_energy_capacity"], 100.0), "reserve capacity should remain independent")
	_expect(is_equal_approx(assembly["working_energy_capacity"], 50.0), "working capacity should remain independent")
	_expect(is_equal_approx(assembly["power_output"], 30.0), "output power should remain a budget")
	_expect(is_equal_approx(assembly["passive_power_load"], 7.0), "continuous component load should aggregate")
	_expect(is_equal_approx(assembly["available_power_output"], 23.0), "available output should subtract passive load")
	var state: VehicleCombatState = VehicleCombatStateScript.new()
	_expect(state.configure(assembly).is_ok, "calculated assembly should initialize mutable vehicle state")
	_expect(state.max_health == 70 and state.health == 70, "vehicle state should initialize only chassis combat health")
	var vehicle_damage := state.apply_damage(10)
	_expect(vehicle_damage.is_ok and int(vehicle_damage.value["health"]) == 60, "vehicle damage should reduce health rather than equipment hardiness")
	_expect(not state.to_dictionary().has("durability"), "vehicle snapshots must not reuse durability for combat health")
	_expect(state.consume_working_energy(10.0).is_ok, "weapon cost should consume working energy")
	_expect(is_equal_approx(state.working_energy, 40.0), "working energy should decrease by exact cost")
	_expect(is_equal_approx(state.reserve_energy, 100.0), "weapon cost must not consume reserve energy")
	var restored := state.regenerate_working_energy(1.0, 1.0)
	_expect(restored.is_ok and is_equal_approx(restored.value, 10.0), "output-driven regeneration should fill missing working energy")
	_expect(is_equal_approx(state.working_energy, 50.0), "working energy should refill to capacity")
	_expect(is_equal_approx(state.reserve_energy, 90.0), "regeneration should drain reserve one-for-one")
	_expect(is_equal_approx(state.power_output, 30.0), "regeneration must not consume output power")
	var invalid_component: Array[Dictionary] = [{"weight": -1}]
	_expect(
		not VehicleAssemblyCalculator.calculate(
			_chassis_definition(), invalid_component, 5, _movement_config()
		).is_ok,
		"negative injected component stats should be rejected",
	)


## 执行 `test_energy_cannon_authority_state_machine` 对应的模块操作。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _test_energy_cannon_authority_state_machine() -> void:
	var module := _new_module(12345)
	var assembly: Dictionary = _assembly_result().value
	_expect(
		module.register_vehicle("player.a", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _weapon_definition()}).is_ok,
		"player A vehicle should register",
	)
	_expect(
		module.register_vehicle("player.b", MAP_INSTANCE_ID, Vector2(10.0, 0.0), assembly, {ABILITY_ID: _weapon_definition()}).is_ok,
		"player B vehicle should register",
	)
	_expect(module.register_monster(_monster_definition("monster.front", 30, Vector2(100.0, 0.0))).is_ok, "front target should register")
	_expect(module.register_monster(_monster_definition("monster.back", 30, Vector2(180.0, 0.0))).is_ok, "back target should register")
	var state_a: VehicleCombatState = module.vehicle_state_for("player.a")
	var forged := _attack_intent(Vector2(250.0, 0.0), 1)
	forged["damage"] = 999999
	var before_energy := state_a.working_energy
	var before_health := module.monster_for("monster.front").health
	var forged_result := module.handle_energy_cannon_attack("player.a", forged)
	_expect(not forged_result.is_ok and forged_result.error_code == &"network.invalid_payload", "client damage field should be rejected by shared intent contract")
	_expect(is_equal_approx(state_a.working_energy, before_energy), "forged damage should consume no working energy")
	_expect(module.monster_for("monster.front").health == before_health, "forged damage should mutate no target health")
	var first_shot := module.handle_energy_cannon_attack("player.a", _attack_intent(Vector2(250.0, 0.0), 1))
	_expect(first_shot.is_ok, "valid coordinate-only energy-cannon attack should spawn")
	_expect(String(first_shot.value["target_entity_id"]) == "monster.front", "first intersecting monster should catch the shot")
	_expect(int(first_shot.value["impact_tick"]) > module.current_tick, "spawn should schedule a future impact tick")
	_expect(module.monster_for("monster.front").health == before_health, "firing must not deduct health before projectile arrival")
	_expect(is_equal_approx(state_a.working_energy, 40.0), "successful shot should reserve exact working energy")
	var cooldown_energy := state_a.working_energy
	var cooldown := module.handle_energy_cannon_attack("player.a", _attack_intent(Vector2(250.0, 0.0), 2))
	_expect(not cooldown.is_ok and cooldown.error_code == &"combat.weapon_cooldown", "second immediate shot should be cooling down")
	_expect(is_equal_approx(state_a.working_energy, cooldown_energy), "cooldown rejection should consume no energy")
	var ticks_until_impact := int(first_shot.value["impact_tick"]) - module.current_tick
	module.advance_ticks(ticks_until_impact - 1)
	_expect(module.monster_for("monster.front").health == before_health, "health should remain unchanged one tick before arrival")
	module.advance_ticks(1)
	_expect(module.monster_for("monster.front").health < before_health, "damage should apply exactly when the projectile arrives")
	_expect(module.monster_for("monster.back").health == 30, "monster behind the first collision should remain untouched")
	var last_event: Dictionary = module.combat_events[-1]
	_expect(StringName(last_event["event_type"]) == &"energy_cannon_hit", "arrival should emit the authoritative hit event")
	module.advance_ticks(20 - module.current_tick)
	var empty_shot := module.handle_energy_cannon_attack("player.a", _attack_intent(Vector2(0.0, 250.0), 3))
	_expect(empty_shot.is_ok and String(empty_shot.value["target_entity_id"]).is_empty(), "shooting empty space should still create a clamped projectile")
	_settle_all_projectiles(module)
	_expect(StringName(module.combat_events[-1]["event_type"]) == &"energy_cannon_projectile_expired", "empty shot should expire without damage")
	state_a.working_energy = 5.0
	module.advance_ticks(20)
	var insufficient := module.handle_energy_cannon_attack("player.a", _attack_intent(Vector2(250.0, 0.0), 4))
	_expect(not insufficient.is_ok and insufficient.error_code == &"combat.insufficient_working_energy", "insufficient working energy should prevent firing")
	var overloaded := assembly.duplicate(true)
	overloaded["power_overloaded"] = true
	overloaded["passive_power_load"] = 40.0
	overloaded["available_power_output"] = 0.0
	_expect(module.register_vehicle("player.overloaded", MAP_INSTANCE_ID, Vector2.ZERO, overloaded, {ABILITY_ID: _weapon_definition()}).is_ok, "overloaded fixture should remain inspectable")
	var power_rejected := module.handle_energy_cannon_attack("player.overloaded", _attack_intent(Vector2(250.0, 0.0), 1))
	_expect(not power_rejected.is_ok and power_rejected.error_code == &"combat.insufficient_power_output", "overloaded output budget should prevent activation")


## 执行 `test_single_death_and_thirty_second_respawn` 对应的模块操作。
func _test_single_death_and_thirty_second_respawn() -> void:
	var module := _new_module(77)
	var assembly: Dictionary = _assembly_result().value
	module.register_vehicle("player.a", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(7)})
	module.register_vehicle("player.b", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(7)})
	module.register_monster(_monster_definition("monster.shared", 7, Vector2(100.0, 0.0)))
	var first_shot := module.handle_energy_cannon_attack("player.a", _attack_intent(Vector2(100.0, 0.0), 1))
	var second_shot := module.handle_energy_cannon_attack("player.b", _attack_intent(Vector2(100.0, 0.0), 1))
	_expect(first_shot.is_ok and second_shot.is_ok, "simultaneous shots may be in flight before either death is settled")
	_settle_all_projectiles(module)
	_expect(module.death_events.size() == 1, "one monster generation should emit exactly one death event")
	var monster: MonsterLifecycle = module.monster_for("monster.shared")
	_expect(monster.death_generation == 1 and monster.last_killer_id == "player.a", "first killer should own the settled generation")
	var expected_respawn_tick := module.current_tick + 600
	_expect(monster.respawn_at_tick == expected_respawn_tick, "30 seconds at 20 Hz should schedule 600 ticks after impact")
	module.advance_ticks(599)
	_expect(not monster.is_alive() and module.respawn_events.is_empty(), "monster should remain dead before its scheduled respawn tick")
	var respawns := module.advance_ticks(1)
	_expect(respawns.is_ok and respawns.value.size() == 1, "monster should respawn exactly 600 ticks after impact")
	_expect(monster.is_alive() and monster.health == monster.max_health, "respawn should restore full health")
	_expect(module.death_events.size() == 1 and module.respawn_events.size() == 1, "respawn should not duplicate prior death settlement")


## 执行 `test_seeded_damage_is_reproducible` 对应的模块操作。
func _test_seeded_damage_is_reproducible() -> void:
	var first := _new_seeded_attack_world(987654)
	var second := _new_seeded_attack_world(987654)
	first.handle_energy_cannon_attack("player.seed", _attack_intent(Vector2(100.0, 0.0), 1))
	second.handle_energy_cannon_attack("player.seed", _attack_intent(Vector2(100.0, 0.0), 1))
	_settle_all_projectiles(first)
	_settle_all_projectiles(second)
	var first_damage: int = 100 - first.monster_for("monster.seed").health
	var second_damage: int = 100 - second.monster_for("monster.seed").health
	_expect(first_damage == second_damage, "same fixed seed should reproduce the same damage roll")


## 执行 `test_three_engagement_policies` 对应的模块操作。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _test_three_engagement_policies() -> void:
	var assembly: Dictionary = _assembly_result().value
	var passive := _new_module(101)
	passive.register_vehicle("player.policy", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(1)})
	passive.register_monster(_behavior_monster_definition("monster.passive", &"unresponsive"))
	passive.advance_ticks(40)
	_expect(passive.vehicle_state_for("player.policy").health == 70, "unresponsive monster never initiates")
	passive.handle_energy_cannon_attack("player.policy", _attack_intent(Vector2(20.0, 0.0), 1))
	_settle_all_projectiles(passive)
	passive.advance_ticks(40)
	_expect(passive.vehicle_state_for("player.policy").health == 70, "unresponsive monster never retaliates")

	var retaliatory := _new_module(102)
	retaliatory.register_vehicle("player.policy", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(1)})
	retaliatory.register_monster(_behavior_monster_definition("monster.retaliatory", &"retaliatory"))
	retaliatory.advance_ticks(40)
	_expect(retaliatory.vehicle_state_for("player.policy").health == 70, "retaliatory monster does not initiate")
	retaliatory.handle_energy_cannon_attack("player.policy", _attack_intent(Vector2(20.0, 0.0), 1))
	_settle_all_projectiles(retaliatory)
	_expect(retaliatory.vehicle_state_for("player.policy").health == 67, "retaliatory monster attacks after being hit")

	var aggressive := _new_module(103)
	aggressive.register_vehicle("player.policy", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(1)})
	aggressive.register_monster(_behavior_monster_definition("monster.aggressive", &"aggressive"))
	aggressive.advance_ticks(1)
	_expect(aggressive.vehicle_state_for("player.policy").health == 67, "aggressive monster initiates inside aggro radius")
	var snapshot: Dictionary = aggressive.snapshot_for_actor("player.policy")
	_expect(String(snapshot.get("local_entity_id", "")) == "player.policy", "snapshot identifies local damage target")
	_expect((snapshot.get("recent_events", []) as Array).size() == 2, "snapshot includes deduplicatable attack-start and damage events")


## 验证空闲怪物完成一次游走后等待五秒才选择下一段路径。
func _test_five_second_wander_interval() -> void:
	var module := _new_module(106)
	var definition := _monster_definition("monster.wander", 30, Vector2(200.0, 200.0))
	definition.merge({
		"runtime_move_speed": 60.0,
		"wander_radius": 80.0,
		"wander_interval_seconds": 5.0,
	}, true)
	_expect(module.register_monster(definition).is_ok, "wandering monster should register")
	var monster: MonsterLifecycle = module.monster_for("monster.wander")
	var initial_position := monster.position
	module.advance_ticks(99)
	_expect(monster.position.is_equal_approx(initial_position), "monster should remain idle before five seconds")
	module.advance_ticks(1)
	_expect(not monster.position.is_equal_approx(initial_position), "monster should begin roaming on the fifth second")
	var safety_ticks := 400
	while monster.action == &"move" and safety_ticks > 0:
		module.advance_ticks(1)
		safety_ticks -= 1
	var settled_position := monster.position
	module.advance_ticks(99)
	_expect(monster.position.is_equal_approx(settled_position), "completed roam should be followed by another five-second pause")


## 验证死亡结算生成地面掉落，并只允许附近玩家提交一次拾取。
func _test_authoritative_ground_loot_lifecycle() -> void:
	var module := _new_module(107)
	module.register_vehicle(
		"player.loot", MAP_INSTANCE_ID, Vector2.ZERO, _assembly_result().value,
		{ABILITY_ID: _fixed_damage_weapon(7)},
	)
	var definition := _monster_definition("monster.loot", 7, Vector2(40.0, 0.0))
	definition["drops"] = [{
		"item_definition_id": "low_grade_gel",
		"minimum_quantity": 2,
		"maximum_quantity": 2,
		"chance": 1.0,
	}]
	_expect(module.register_monster(definition).is_ok, "monster with a valid drop table should register")
	var shot := module.handle_energy_cannon_attack(
		"player.loot", _attack_intent(Vector2(40.0, 0.0), 1)
	)
	_expect(shot.is_ok, "loot fixture attack should spawn")
	_settle_all_projectiles(module)
	_expect(module.ground_loot.size() == 1, "one guaranteed drop should become one ground entity")
	var snapshot := module.snapshot_for_actor("player.loot")
	_expect((snapshot["ground_loot"] as Array).size() == 1, "ground loot should be included in the actor combat snapshot")
	var loot: Dictionary = snapshot["ground_loot"][0]
	_expect(loot.item_definition_id == "low_grade_gel" and loot.quantity == 2, "drop definition and rolled quantity should remain server-owned")
	var prepared := module.prepare_loot_pickup("player.loot", String(loot.loot_id))
	_expect(prepared.is_ok, "nearby authenticated player should pass pickup preflight")
	module.update_actor_position("player.loot", Vector2(165.0, 0.0))
	_expect(
		module.prepare_loot_pickup("player.loot", String(loot.loot_id)).is_ok,
		"original-client 125-pixel pickup boundary should remain inclusive",
	)
	module.update_actor_position("player.loot", Vector2(165.1, 0.0))
	_expect(
		not module.prepare_loot_pickup("player.loot", String(loot.loot_id)).is_ok,
		"pickup should be rejected immediately beyond the original 125-pixel boundary",
	)
	module.update_actor_position("player.loot", Vector2.ZERO)
	var committed := module.commit_loot_pickup("player.loot", String(loot.loot_id))
	_expect(committed.is_ok and module.ground_loot.is_empty(), "committed pickup should remove the ground entity")
	_expect(not module.commit_loot_pickup("player.loot", String(loot.loot_id)).is_ok, "the same drop must not be picked up twice")


## 验证自维修的三秒周期、每二十级加成、工作能耗和受击后三秒延迟。
func _test_authoritative_self_repair_cycles() -> void:
	var module := _new_module(108)
	var assembly: Dictionary = _assembly_result().value
	assembly["self_repair_base_strength"] = 5
	assembly["self_repair_energy_cost"] = 5.0
	module.register_vehicle(
		"player.repair", MAP_INSTANCE_ID, Vector2.ZERO, assembly,
		{ABILITY_ID: _fixed_damage_weapon(1)},
	)
	var state: VehicleCombatState = module.vehicle_state_for("player.repair")
	var full_health_start := module.handle_self_repair(
		"player.repair", _self_repair_intent(1), 39
	)
	_expect(
		not full_health_start.is_ok and full_health_start.error_code == &"combat.self_repair_not_needed",
		"full-health vehicle should not start a repair loop",
	)
	state.apply_damage(20)
	var started := module.handle_self_repair("player.repair", _self_repair_intent(2), 39)
	_expect(started.is_ok, "damaged vehicle should start authoritative self-repair")
	_expect(
		int(started.value["health_per_cycle"]) == 6,
		"level 39 repair should add exactly one point to base five",
	)
	module.advance_ticks(59)
	_expect(state.health == 50, "self-repair should not resolve before three seconds")
	module.advance_ticks(1)
	_expect(state.health == 56, "first three-second cycle should restore six health")
	_expect(is_equal_approx(state.working_energy, 45.0), "successful cycle should consume five working energy")
	state.apply_damage(1)
	module.advance_ticks(59)
	_expect(state.health == 55, "incoming damage should not alter the fixed repair cadence")
	module.advance_ticks(1)
	_expect(state.health == 61, "repair should resolve on schedule while the vehicle is under attack")
	var snapshot := module.snapshot_for_actor("player.repair")
	_expect(
		bool(snapshot["local_vehicle"]["self_repair_active"]),
		"combat snapshot should expose active repair presentation state",
	)

	var level_module := _new_module(109)
	level_module.register_vehicle(
		"player.level40", MAP_INSTANCE_ID, Vector2.ZERO, assembly,
		{ABILITY_ID: _fixed_damage_weapon(1)},
	)
	var level_state: VehicleCombatState = level_module.vehicle_state_for("player.level40")
	level_state.apply_damage(10)
	var level_started := level_module.handle_self_repair(
		"player.level40", _self_repair_intent(1), 40
	)
	_expect(
		level_started.is_ok and int(level_started.value["health_per_cycle"]) == 7,
		"level 40 repair should add two points to base five",
	)
	level_state.working_energy = 4.0
	level_module.advance_ticks(60)
	_expect(level_state.health == 60, "insufficient working energy should apply no healing")
	_expect(
		not bool(level_module.snapshot_for_actor("player.level40")["local_vehicle"]["self_repair_active"]),
		"insufficient energy should stop the authoritative repair loop",
	)


## 验证远程怪物只在权威弹体首次接触玩家受击圆时扣除生命。
func _test_monster_projectile_timing() -> void:
	var module := _new_module(104)
	var assembly: Dictionary = _assembly_result().value
	module.register_vehicle("player.projectile", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(1)})
	var definition := _behavior_monster_definition("monster.projectile", &"aggressive")
	definition["position"] = Vector2(100.0, 0.0)
	definition["attack_range"] = 120.0
	definition["attack_archetype"] = &"ranged_projectile"
	definition["combat_actor_id"] = "om_adult_standard"
	definition["runtime_projectile_speed"] = 100.0
	module.register_monster(definition)
	module.advance_ticks(1)
	_expect(module.vehicle_state_for("player.projectile").health == 70, "remote attack must not deduct health when fired")
	_expect(module.pending_monster_attacks.size() == 1, "remote attack should reserve one authoritative projectile")
	var attack: Dictionary = module.pending_monster_attacks[0]
	_expect(int(attack["impact_tick"]) > module.current_tick, "monster projectile should expose a future impact tick")
	var snapshot := module.snapshot_for_actor("player.projectile")
	var monster_snapshot: Dictionary = (snapshot["monsters"] as Array)[0]
	_expect(int(monster_snapshot["action_sequence"]) == 1, "attack start should advance the body-animation sequence")
	var ticks_until_impact := int(attack["impact_tick"]) - module.current_tick
	for unused_tick: int in range(ticks_until_impact):
		if module.pending_monster_attacks.is_empty():
			break
		module.advance_ticks(1)
	_expect(module.vehicle_state_for("player.projectile").health == 67, "monster projectile should apply damage on first swept contact")
	_expect(module.current_tick <= int(attack["impact_tick"]), "hitbox contact must not settle after the original endpoint tick")
	_expect(StringName(module.combat_events[-1]["event_type"]) == &"monster_attack_resolved", "arrival should emit the damage event")
	_expect(
		String(module.combat_events[-1].get("combat_actor_id", "")) == "om_adult_standard",
		"resolved attack should retain the monster visual identity",
	)


## 验证玩家在弹体抵达前横向离开初始瞄准线后不会受到预约伤害。
func _test_monster_projectile_can_be_dodged() -> void:
	var module := _new_module(105)
	var assembly: Dictionary = _assembly_result().value
	module.register_vehicle(
		"player.dodge",
		MAP_INSTANCE_ID,
		Vector2.ZERO,
		assembly,
		{ABILITY_ID: _fixed_damage_weapon(1)},
	)
	var definition := _behavior_monster_definition("monster.dodge", &"aggressive")
	definition["position"] = Vector2(100.0, 0.0)
	definition["attack_range"] = 120.0
	definition["attack_archetype"] = &"ranged_projectile"
	definition["combat_actor_id"] = "om_adult_standard"
	definition["runtime_projectile_speed"] = 100.0
	definition["attack_interval_seconds"] = 10.0
	module.register_monster(definition)
	module.advance_ticks(1)
	var attack: Dictionary = module.pending_monster_attacks[0]
	module.advance_ticks(8)
	module.update_actor_position("player.dodge", Vector2(0.0, 80.0))
	module.advance_ticks(int(attack["impact_tick"]) - module.current_tick)
	_expect(module.vehicle_state_for("player.dodge").health == 70, "leaving the projectile path before contact should avoid damage")
	_expect(module.pending_monster_attacks.is_empty(), "missed monster projectile should leave no pending reservation")
	_expect(StringName(module.combat_events[-1]["event_type"]) == &"monster_attack_expired", "a dodged projectile should emit a no-damage expiry event")
	_expect(String(module.combat_events[-1]["attack_id"]) == String(attack["attack_id"]), "expiry should identify the dodged projectile")


## 执行 `new_module` 对应的模块操作。
## [param seed] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _new_module(seed: int) -> AuthoritativeCombatModule:
	var module: AuthoritativeCombatModule = CombatModuleScript.new()
	var configured := module.configure(20, seed, 0.0)
	_expect(configured.is_ok, "combat module should configure")
	return module


## 执行 `new_seeded_attack_world` 对应的模块操作。
## [param seed] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _new_seeded_attack_world(seed: int) -> AuthoritativeCombatModule:
	var module := _new_module(seed)
	module.register_vehicle("player.seed", MAP_INSTANCE_ID, Vector2.ZERO, _assembly_result().value, {ABILITY_ID: _weapon_definition()})
	module.register_monster(_monster_definition("monster.seed", 100, Vector2(100.0, 0.0)))
	return module


## 执行 `assembly_result` 对应的模块操作。
func _assembly_result():
	var components: Array[Dictionary] = [
		{"weight": 50, "propulsion": 20, "required_driving_level": 10, "continuous_power_draw": 5},
		{"weight": 50, "max_durability": 900, "continuous_power_draw": 2},
	]
	return VehicleAssemblyCalculator.calculate(
		_chassis_definition(), components, 5, _movement_config()
	)


## 执行 `chassis_definition` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _chassis_definition() -> Dictionary:
	return {
		"weight": 100,
		"max_health": 70,
		"max_durability": 1020,
		"reserve_energy_capacity": 100,
		"working_energy_capacity": 50,
		"power_output": 30,
	}


## 执行 `movement_config` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _movement_config() -> Dictionary:
	return {"base_speed_multiplier": 1500, "base_speed_cap": 240}


## 执行 `weapon_definition` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _weapon_definition() -> Dictionary:
	return {
		"weapon_id": "rookie_energy_cannon",
		"minimum_damage": 7,
		"maximum_damage": 9,
		"working_energy_cost": 10,
		"activation_power": 10,
		"range": 250,
		"upgrade_range_limit": 400,
		"cooldown_ticks": 20,
		"projectile_speed": 100.0,
		"muzzle_offset": [0.0, 0.0],
		"muzzle_forward_offset": 0.0,
	}


## 执行 `fixed_damage_weapon` 对应的模块操作。
## [param damage] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _fixed_damage_weapon(damage: int) -> Dictionary:
	var definition := _weapon_definition()
	definition["minimum_damage"] = damage
	definition["maximum_damage"] = damage
	return definition


## 执行 `monster_definition` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param health] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _monster_definition(monster_id: String, health: int, position: Vector2) -> Dictionary:
	return {
		"monster_id": monster_id,
		"map_instance_id": MAP_INSTANCE_ID,
		"position": position,
		"max_health": health,
		"respawn_seconds": 30.0,
		"projectile_hitbox": {"offset": [0.0, 0.0], "radius": 20.0},
	}


## 执行 `behavior_monster_definition` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param engagement_policy] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _behavior_monster_definition(monster_id: String, engagement_policy: StringName) -> Dictionary:
	var definition := _monster_definition(monster_id, 30, Vector2(20.0, 0.0))
	definition.merge({
		"engagement_policy": engagement_policy,
		"base_attack": 3,
		"attack_range": 40.0,
		"aggro_radius": 200.0,
		"leash_distance": 600.0,
		"wander_radius": 0.0,
		"runtime_move_speed": 0.0,
		"attack_interval_seconds": 1.0,
	}, true)
	return definition


## 执行 `attack_intent` 对应的模块操作。
## [param aim_world_position] 瞄准世界坐标，只用于表达发射方向。
## [param sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _attack_intent(aim_world_position: Vector2, sequence: int) -> Dictionary:
	return UseAbilityIntentContract.new(
		MAP_INSTANCE_ID, ABILITY_ID, aim_world_position, sequence
	).to_dictionary()


## 构造不携带任何维修数值的自维修能力意图。
## [param sequence] 玩家能力命令的单调序号。
## 返回与正式网络相同的四字段载荷。
func _self_repair_intent(sequence: int) -> Dictionary:
	return UseAbilityIntentContract.new(
		MAP_INSTANCE_ID,
		AuthoritativeCombatModule.SELF_REPAIR_ABILITY_ID,
		Vector2.ZERO,
		sequence,
	).to_dictionary()


## 将测试模块推进到所有当前弹体的最晚权威到达 tick。
## [param module] 待推进的隔离战斗模块。
func _settle_all_projectiles(module: AuthoritativeCombatModule) -> void:
	var latest_tick := module.current_tick
	for projectile: Dictionary in module.pending_projectiles:
		latest_tick = maxi(latest_tick, int(projectile["impact_tick"]))
	module.advance_ticks(latest_tick - module.current_tick)


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
