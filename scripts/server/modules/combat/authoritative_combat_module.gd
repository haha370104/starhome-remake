class_name AuthoritativeCombatModule
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const MonsterLifecycleScript := preload("res://scripts/domain/combat/monster_lifecycle.gd")
const VehicleCombatStateScript := preload("res://scripts/domain/combat/vehicle_combat_state.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")

var simulation_hz := 20
var current_tick := 0
var working_energy_regen_factor := 1.0
var actors: Dictionary = {}
var monsters: Dictionary = {}
var combat_events: Array[Dictionary] = []
var death_events: Array[Dictionary] = []
var respawn_events: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()


## Configures deterministic tick and random state for the authoritative combat world.
## [param requested_simulation_hz] Fixed ticks per second used by cooldown and respawn timing.
## [param random_seed] Explicit seed ensuring repeatable damage rolls in simulation tests.
## [param regen_factor] Working-energy restoration per available output-power unit per second.
## Returns this module on success or a validation failure.
func configure(
	requested_simulation_hz: int,
	random_seed: int,
	regen_factor: float = 1.0,
) -> DomainResult:
	if requested_simulation_hz <= 0 or regen_factor < 0.0:
		return DomainResult.failure(&"combat.invalid_module_config", "tick rate and regeneration factor are invalid")
	simulation_hz = requested_simulation_hz
	current_tick = 0
	working_energy_regen_factor = regen_factor
	_random.seed = random_seed
	actors.clear()
	monsters.clear()
	combat_events.clear()
	death_events.clear()
	respawn_events.clear()
	return DomainResult.ok(self)


## Registers one server-owned vehicle combatant in [param map_instance_id] at [param position].
## [param actor_id] Authenticated entity identity supplied by the server session layer.
## [param map_instance_id] Current authoritative map instance used to scope ability targets.
## [param position] Current authoritative foot point used for range validation.
## [param assembly] Calculated vehicle statistics used to initialize mutable resources.
## [param weapons_by_ability] Injected energy-cannon definitions keyed by stable ability ID.
## Returns the initialized `VehicleCombatState` or a validation failure.
func register_vehicle(
	actor_id: String,
	map_instance_id: String,
	position: Vector2,
	assembly: Dictionary,
	weapons_by_ability: Dictionary,
) -> DomainResult:
	if actor_id.is_empty() or map_instance_id.is_empty() or actors.has(actor_id) or not position.is_finite():
		return DomainResult.failure(&"combat.invalid_actor", "actor/map identity must be unique and position finite")
	var normalized_weapons: Dictionary = {}
	for raw_slot: Variant in weapons_by_ability.keys():
		var slot_id := String(raw_slot)
		if slot_id.is_empty() or not weapons_by_ability[raw_slot] is Dictionary:
			return DomainResult.failure(&"combat.invalid_weapon_definition", "weapon slot or definition is invalid")
		var weapon_result := _normalize_energy_cannon(weapons_by_ability[raw_slot])
		if not weapon_result.is_ok:
			return weapon_result
		normalized_weapons[slot_id] = weapon_result.value
	var vehicle_state: VehicleCombatState = VehicleCombatStateScript.new()
	var state_result := vehicle_state.configure(assembly)
	if not state_result.is_ok:
		return state_result
	actors[actor_id] = {
		"map_instance_id": map_instance_id,
		"position": position,
		"vehicle_state": vehicle_state,
		"weapons": normalized_weapons,
		"cooldown_ready_ticks": {},
		"last_command_sequence": -1,
	}
	return DomainResult.ok(vehicle_state)


## Registers one injected monster [param definition] under server lifecycle control.
## [param definition] Monster identity, position, combat health and respawn-seconds fixture/definition.
## Returns the initialized `MonsterLifecycle` or a validation failure.
func register_monster(definition: Dictionary) -> DomainResult:
	var lifecycle: MonsterLifecycle = MonsterLifecycleScript.new()
	var result := lifecycle.configure(definition, simulation_hz)
	if not result.is_ok:
		return result
	if monsters.has(lifecycle.monster_id):
		return DomainResult.failure(&"combat.duplicate_monster", "monster identity is already registered")
	monsters[lifecycle.monster_id] = lifecycle
	return DomainResult.ok(lifecycle)


## Updates authoritative [param actor_id] position without accepting a client coordinate in attack payloads.
## [param actor_id] Registered server-owned vehicle entity.
## [param position] Position already validated by the movement/map module.
## Returns success after mutation or an actor/position validation failure.
func update_actor_position(actor_id: String, position: Vector2) -> DomainResult:
	if not actors.has(actor_id):
		return DomainResult.failure(&"combat.unknown_actor", "actor is not registered")
	if not position.is_finite():
		return DomainResult.failure(&"combat.invalid_position", "actor position must be finite")
	actors[actor_id]["position"] = position
	return DomainResult.ok(position)


## Validates and resolves one energy-cannon attack from authenticated [param actor_id].
## [param actor_id] Server-authenticated attacker; this identity is absent from client-controlled intent.
## [param raw_intent] Shared `UseAbilityIntent` shape: map, ability, target and monotonic sequence.
## Returns authoritative energy, cooldown, damage and optional death facts.
## Design: Damage, range, position, energy and hit outcome never come from the client payload.
func handle_energy_cannon_attack(actor_id: String, raw_intent: Variant) -> DomainResult:
	if not actors.has(actor_id):
		return DomainResult.failure(&"combat.unknown_actor", "authenticated actor is not registered")
	var intent_result = UseAbilityIntentContract.from_dictionary(raw_intent)
	if not intent_result.is_ok:
		return intent_result
	var intent: UseAbilityIntent = intent_result.value
	var map_instance_id := intent.map_instance_id
	var ability_id := intent.ability_id
	var target_id := intent.target_entity_id
	var command_sequence := intent.input_sequence
	var actor: Dictionary = actors[actor_id]
	if command_sequence < 0 or command_sequence <= int(actor["last_command_sequence"]):
		return DomainResult.failure(&"combat.stale_command", "attack command sequence is stale")
	actor["last_command_sequence"] = command_sequence
	if map_instance_id != String(actor["map_instance_id"]):
		return DomainResult.failure(&"combat.map_instance_mismatch", "ability intent targets another map instance")
	if not actor["weapons"].has(ability_id):
		return DomainResult.failure(&"combat.weapon_not_equipped", "energy-cannon ability is not equipped")
	if not monsters.has(target_id):
		return DomainResult.failure(&"combat.unknown_target", "target monster is not registered")
	var monster: MonsterLifecycle = monsters[target_id]
	if monster.map_instance_id != map_instance_id:
		return DomainResult.failure(&"combat.target_map_mismatch", "target is not in the attacker's map instance")
	if not monster.is_alive():
		return DomainResult.failure(&"combat.target_already_dead", "target monster is already dead")
	var weapon: Dictionary = actor["weapons"][ability_id]
	var ready_tick := int(actor["cooldown_ready_ticks"].get(ability_id, 0))
	if current_tick < ready_tick:
		return DomainResult.failure(&"combat.weapon_cooldown", "energy cannon is cooling down")
	var actor_position: Vector2 = actor["position"]
	var attack_distance := actor_position.distance_to(monster.position)
	if attack_distance > float(weapon["range"]) + 0.000001:
		return DomainResult.failure(&"combat.target_out_of_range", "target is beyond energy-cannon range")
	var vehicle_state: VehicleCombatState = actor["vehicle_state"]
	if weapon["activation_power"] != null \
		and not vehicle_state.supports_activation_power(float(weapon["activation_power"])):
		return DomainResult.failure(&"combat.insufficient_power_output", "vehicle output budget cannot activate weapon")
	var energy_result := vehicle_state.consume_working_energy(float(weapon["working_energy_cost"]))
	if not energy_result.is_ok:
		return energy_result
	actor["cooldown_ready_ticks"][ability_id] = current_tick + int(weapon["cooldown_ticks"])
	var damage := _random.randi_range(int(weapon["minimum_damage"]), int(weapon["maximum_damage"]))
	var damage_result := monster.apply_damage(damage, actor_id, current_tick)
	if not damage_result.is_ok:
		return damage_result
	var event := {
		"event_type": &"energy_cannon_hit",
		"server_tick": current_tick,
		"attacker_id": actor_id,
		"target_entity_id": target_id,
		"weapon_id": weapon["weapon_id"],
		"damage": damage_result.value["applied_damage"],
		"target_health": damage_result.value["health"],
		"working_energy": vehicle_state.working_energy,
		"cooldown_ready_tick": actor["cooldown_ready_ticks"][ability_id],
	}
	combat_events.append(event)
	if bool(damage_result.value["died"]):
		var death_event := {
			"event_type": &"monster_died",
			"server_tick": current_tick,
			"monster_id": target_id,
			"killer_id": actor_id,
			"death_generation": damage_result.value["death_generation"],
			"respawn_at_tick": damage_result.value["respawn_at_tick"],
		}
		death_events.append(death_event)
		event["death"] = death_event.duplicate(true)
	return DomainResult.ok(event)


## Advances the authoritative combat world by [param tick_count] fixed ticks.
## [param tick_count] Number of simulation ticks to process deterministically.
## Returns newly emitted respawn events, or a validation failure.
func advance_ticks(tick_count: int) -> DomainResult:
	if tick_count < 0:
		return DomainResult.failure(&"combat.invalid_tick_count", "tick count cannot be negative")
	var emitted_respawns: Array[Dictionary] = []
	var fixed_delta := 1.0 / float(simulation_hz)
	for unused_tick: int in range(tick_count):
		current_tick += 1
		for actor_id: String in actors:
			var vehicle_state: VehicleCombatState = actors[actor_id]["vehicle_state"]
			vehicle_state.regenerate_working_energy(fixed_delta, working_energy_regen_factor)
		for monster_id: String in monsters:
			var monster: MonsterLifecycle = monsters[monster_id]
			var lifecycle_result := monster.advance_to_tick(current_tick)
			if bool(lifecycle_result.value["respawned"]):
				var respawn_event := {
					"event_type": &"monster_respawned",
					"server_tick": current_tick,
					"monster_id": monster_id,
					"death_generation": monster.death_generation,
				}
				respawn_events.append(respawn_event)
				emitted_respawns.append(respawn_event)
	return DomainResult.ok(emitted_respawns)


## Retrieves the mutable vehicle state owned by [param actor_id] for server inspection.
## [param actor_id] Registered authenticated actor identity.
## Returns the vehicle state or `null` when the actor is unknown.
func vehicle_state_for(actor_id: String) -> VehicleCombatState:
	if not actors.has(actor_id):
		return null
	return actors[actor_id]["vehicle_state"]


## Retrieves the monster lifecycle owned by [param monster_id].
## [param monster_id] Registered monster identity.
## Returns the lifecycle or `null` when absent.
func monster_for(monster_id: String) -> MonsterLifecycle:
	return monsters.get(monster_id)


## Validates and normalizes one injected energy-cannon [param definition].
## [param definition] Server definition containing damage, energy, power, range and cooldown values.
## Returns a normalized dictionary or a stable definition failure.
func _normalize_energy_cannon(definition: Dictionary) -> DomainResult:
	var weapon_id := String(definition.get("weapon_id", ""))
	var minimum_damage := int(definition.get("minimum_damage", -1))
	var maximum_damage := int(definition.get("maximum_damage", -1))
	var working_energy_cost := float(definition.get("working_energy_cost", -1.0))
	var raw_activation_power: Variant = definition.get("activation_power", null)
	var activation_power: Variant = null
	if raw_activation_power != null:
		if typeof(raw_activation_power) != TYPE_INT and typeof(raw_activation_power) != TYPE_FLOAT:
			return DomainResult.failure(&"combat.invalid_weapon_definition", "activation power must be numeric or explicitly unknown")
		activation_power = float(raw_activation_power)
	var attack_range := float(definition.get("range", 0.0))
	var upgrade_range_limit := float(definition.get("upgrade_range_limit", attack_range))
	var cooldown_ticks := int(definition.get("cooldown_ticks", 0))
	if weapon_id.is_empty() or minimum_damage < 0 or maximum_damage < minimum_damage:
		return DomainResult.failure(&"combat.invalid_weapon_definition", "energy-cannon damage definition is invalid")
	if working_energy_cost < 0.0 or (activation_power != null and float(activation_power) < 0.0) \
		or attack_range <= 0.0 or upgrade_range_limit < attack_range or cooldown_ticks <= 0:
		return DomainResult.failure(&"combat.invalid_weapon_definition", "energy-cannon resource or timing definition is invalid")
	return DomainResult.ok({
		"weapon_id": weapon_id,
		"minimum_damage": minimum_damage,
		"maximum_damage": maximum_damage,
		"working_energy_cost": working_energy_cost,
		"activation_power": activation_power,
		"range": attack_range,
		"upgrade_range_limit": upgrade_range_limit,
		"cooldown_ticks": cooldown_ticks,
	})
