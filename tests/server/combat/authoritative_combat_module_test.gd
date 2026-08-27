extends SceneTree

const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const VehicleAssemblyCalculator := preload("res://scripts/domain/combat/vehicle_assembly_calculator.gd")
const VehicleCombatStateScript := preload("res://scripts/domain/combat/vehicle_combat_state.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")
const MAP_INSTANCE_ID := "field.instance.1"
const ABILITY_ID := "energy_cannon.primary"

var failures: Array[String] = []
var assertions := 0


## Runs deterministic vehicle, energy-cannon and monster-lifecycle server tests.
## Design: Every gameplay definition is an explicit fixture until formal Glory definitions are imported.
func _initialize() -> void:
	_test_vehicle_assembly_and_energy_domains()
	_test_energy_cannon_authority_state_machine()
	_test_single_death_and_thirty_second_respawn()
	_test_seeded_damage_is_reproducible()
	if failures.is_empty():
		print("AUTHORITATIVE_COMBAT_MODULE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## Verifies injected assembly aggregation and separation of reserve, working and output-power state.
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


## Verifies server-owned attack validation, energy reservation, damage and cooldown transitions.
## Design: Forged client damage is rejected before any energy, sequence or target mutation.
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
	_expect(module.register_monster(_monster_definition("monster.cooldown", 30, Vector2(100.0, 0.0))).is_ok, "cooldown target should register")
	var state_a: VehicleCombatState = module.vehicle_state_for("player.a")
	var forged := _attack_intent("monster.cooldown", 1)
	forged["damage"] = 999999
	var before_energy := state_a.working_energy
	var before_health := module.monster_for("monster.cooldown").health
	var forged_result := module.handle_energy_cannon_attack("player.a", forged)
	_expect(not forged_result.is_ok and forged_result.error_code == &"network.invalid_payload", "client damage field should be rejected by shared intent contract")
	_expect(is_equal_approx(state_a.working_energy, before_energy), "forged damage should consume no working energy")
	_expect(module.monster_for("monster.cooldown").health == before_health, "forged damage should mutate no target health")
	var first_hit := module.handle_energy_cannon_attack("player.a", _attack_intent("monster.cooldown", 1))
	_expect(first_hit.is_ok, "valid energy-cannon attack should resolve")
	_expect(int(first_hit.value["damage"]) >= 7 and int(first_hit.value["damage"]) <= 9, "damage should come from server weapon definition")
	_expect(is_equal_approx(state_a.working_energy, 40.0), "successful shot should reserve exact working energy")
	var cooldown_energy := state_a.working_energy
	var cooldown_hp := module.monster_for("monster.cooldown").health
	var cooldown := module.handle_energy_cannon_attack("player.a", _attack_intent("monster.cooldown", 2))
	_expect(not cooldown.is_ok and cooldown.error_code == &"combat.weapon_cooldown", "second immediate shot should be cooling down")
	_expect(is_equal_approx(state_a.working_energy, cooldown_energy), "cooldown rejection should consume no energy")
	_expect(module.monster_for("monster.cooldown").health == cooldown_hp, "cooldown rejection should deal no damage")
	_expect(module.advance_ticks(20).is_ok, "one-second cooldown should advance on fixed ticks")
	var cooled_hit := module.handle_energy_cannon_attack("player.a", _attack_intent("monster.cooldown", 3))
	_expect(cooled_hit.is_ok, "weapon should fire at its exact ready tick")
	state_a.working_energy = 5.0
	_expect(module.register_monster(_monster_definition("monster.energy", 30, Vector2(100.0, 0.0))).is_ok, "energy target should register")
	module.advance_ticks(20)
	var insufficient := module.handle_energy_cannon_attack("player.a", _attack_intent("monster.energy", 4))
	_expect(not insufficient.is_ok and insufficient.error_code == &"combat.insufficient_working_energy", "insufficient working energy should prevent firing")
	_expect(module.update_actor_position("player.a", Vector2(351.0, 0.0)).is_ok, "server movement should update combat position")
	state_a.working_energy = 50.0
	var out_of_range := module.handle_energy_cannon_attack("player.a", _attack_intent("monster.energy", 5))
	_expect(not out_of_range.is_ok and out_of_range.error_code == &"combat.target_out_of_range", "current range 250 should reject distance 251")
	_expect(module.register_vehicle("player.edge", MAP_INSTANCE_ID, Vector2(350.0, 0.0), assembly, {ABILITY_ID: _weapon_definition()}).is_ok, "range-edge actor should register")
	var edge_hit := module.handle_energy_cannon_attack("player.edge", _attack_intent("monster.energy", 1))
	_expect(edge_hit.is_ok, "current range 250 should allow distance 250")
	var overloaded := assembly.duplicate(true)
	overloaded["power_overloaded"] = true
	overloaded["passive_power_load"] = 40.0
	overloaded["available_power_output"] = 0.0
	_expect(module.register_vehicle("player.overloaded", MAP_INSTANCE_ID, Vector2.ZERO, overloaded, {ABILITY_ID: _weapon_definition()}).is_ok, "overloaded fixture should remain inspectable")
	var power_rejected := module.handle_energy_cannon_attack("player.overloaded", _attack_intent("monster.energy", 1))
	_expect(not power_rejected.is_ok and power_rejected.error_code == &"combat.insufficient_power_output", "overloaded output budget should prevent activation")


## Verifies two attackers cannot settle one monster death twice and respawn occurs after exactly 30 seconds.
func _test_single_death_and_thirty_second_respawn() -> void:
	var module := _new_module(77)
	var assembly: Dictionary = _assembly_result().value
	module.register_vehicle("player.a", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(7)})
	module.register_vehicle("player.b", MAP_INSTANCE_ID, Vector2.ZERO, assembly, {ABILITY_ID: _fixed_damage_weapon(7)})
	module.register_monster(_monster_definition("monster.shared", 7, Vector2(100.0, 0.0)))
	var killing_hit := module.handle_energy_cannon_attack("player.a", _attack_intent("monster.shared", 1))
	_expect(killing_hit.is_ok and killing_hit.value.has("death"), "first authoritative lethal hit should settle death")
	var duplicate_hit := module.handle_energy_cannon_attack("player.b", _attack_intent("monster.shared", 1))
	_expect(not duplicate_hit.is_ok and duplicate_hit.error_code == &"combat.target_already_dead", "second attacker should not settle dead monster again")
	_expect(module.death_events.size() == 1, "one monster generation should emit exactly one death event")
	var monster: MonsterLifecycle = module.monster_for("monster.shared")
	_expect(monster.death_generation == 1 and monster.last_killer_id == "player.a", "first killer should own the settled generation")
	_expect(monster.respawn_at_tick == 600, "30 seconds at 20 Hz should schedule tick 600")
	module.advance_ticks(599)
	_expect(not monster.is_alive() and module.respawn_events.is_empty(), "monster should remain dead before tick 600")
	var respawns := module.advance_ticks(1)
	_expect(respawns.is_ok and respawns.value.size() == 1, "monster should respawn exactly at tick 600")
	_expect(monster.is_alive() and monster.health == monster.max_health, "respawn should restore full health")
	_expect(module.death_events.size() == 1 and module.respawn_events.size() == 1, "respawn should not duplicate prior death settlement")


## Verifies equal injected seeds produce identical authoritative damage sequences.
func _test_seeded_damage_is_reproducible() -> void:
	var first := _new_seeded_attack_world(987654)
	var second := _new_seeded_attack_world(987654)
	var first_damage: int = int(first.handle_energy_cannon_attack("player.seed", _attack_intent("monster.seed", 1)).value["damage"])
	var second_damage: int = int(second.handle_energy_cannon_attack("player.seed", _attack_intent("monster.seed", 1)).value["damage"])
	_expect(first_damage == second_damage, "same fixed seed should reproduce the same damage roll")


## Builds a configured combat module using [param seed].
## [param seed] Fixed random seed supplied to deterministic damage simulation.
## Returns a newly configured authoritative module.
func _new_module(seed: int) -> AuthoritativeCombatModule:
	var module: AuthoritativeCombatModule = CombatModuleScript.new()
	var configured := module.configure(20, seed, 0.0)
	_expect(configured.is_ok, "combat module should configure")
	return module


## Builds a one-player, one-monster attack world using [param seed].
## [param seed] Fixed seed whose first damage roll is compared across worlds.
## Returns a ready authoritative combat module.
func _new_seeded_attack_world(seed: int) -> AuthoritativeCombatModule:
	var module := _new_module(seed)
	module.register_vehicle("player.seed", MAP_INSTANCE_ID, Vector2.ZERO, _assembly_result().value, {ABILITY_ID: _weapon_definition()})
	module.register_monster(_monster_definition("monster.seed", 100, Vector2(100.0, 0.0)))
	return module


## Calculates the common rookie-vehicle fixture used by combat tests.
## Returns a `DomainResult` containing normalized aggregate stats.
func _assembly_result():
	var components: Array[Dictionary] = [
		{"weight": 50, "propulsion": 20, "required_driving_level": 10, "continuous_power_draw": 5},
		{"weight": 50, "max_durability": 900, "continuous_power_draw": 2},
	]
	return VehicleAssemblyCalculator.calculate(
		_chassis_definition(), components, 5, _movement_config()
	)


## Builds the reconstructed rookie chassis fixture.
## Returns independent combat health, equipment hardiness, energy and output-power capacities.
func _chassis_definition() -> Dictionary:
	return {
		"weight": 100,
		"max_health": 70,
		"max_durability": 1020,
		"reserve_energy_capacity": 100,
		"working_energy_capacity": 50,
		"power_output": 30,
	}


## Builds the existing project movement-rule fixture.
## Returns speed multiplier and cap used by vehicle assembly calculation.
func _movement_config() -> Dictionary:
	return {"base_speed_multiplier": 1500, "base_speed_cap": 240}


## Builds an injected variable-damage rookie energy cannon fixture.
## Returns weapon stats owned exclusively by the server module.
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
	}


## Builds a fixed-damage energy cannon using [param damage].
## [param damage] Deterministic damage applied by every valid shot.
## Returns a server weapon fixture with all other rookie cannon constraints.
func _fixed_damage_weapon(damage: int) -> Dictionary:
	var definition := _weapon_definition()
	definition["minimum_damage"] = damage
	definition["maximum_damage"] = damage
	return definition


## Builds a monster fixture with [param monster_id], [param health] and [param position].
## [param monster_id] Stable identity for one lifecycle generation.
## [param health] Maximum authoritative combat health restored on respawn.
## [param position] Authoritative target point used for range validation.
## Returns a 30-second-respawn monster definition.
func _monster_definition(monster_id: String, health: int, position: Vector2) -> Dictionary:
	return {
		"monster_id": monster_id,
		"map_instance_id": MAP_INSTANCE_ID,
		"position": position,
		"max_health": health,
		"respawn_seconds": 30.0,
	}


## Builds a client-safe energy-cannon intent targeting [param target_id] at [param sequence].
## [param target_id] Registered monster selected by the player.
## [param sequence] Monotonic per-actor attack command sequence.
## Returns the only four fields accepted by the combat boundary.
func _attack_intent(target_id: String, sequence: int) -> Dictionary:
	return UseAbilityIntentContract.new(
		MAP_INSTANCE_ID, ABILITY_ID, target_id, sequence
	).to_dictionary()


## Records one assertion and its [param message].
## [param condition] Boolean requirement under test.
## [param message] Failure context emitted at test completion.
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
