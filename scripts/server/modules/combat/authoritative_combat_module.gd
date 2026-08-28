class_name AuthoritativeCombatModule
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const MonsterLifecycleScript := preload("res://scripts/domain/combat/monster_lifecycle.gd")
const VehicleCombatStateScript := preload("res://scripts/domain/combat/vehicle_combat_state.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")

var simulation_hz := 20
var current_tick := 0
var event_sequence := 0
var working_energy_regen_factor := 1.0
var actors: Dictionary = {}
var monsters: Dictionary = {}
var monster_runtime: Dictionary = {}
var combat_events: Array[Dictionary] = []
var death_events: Array[Dictionary] = []
var respawn_events: Array[Dictionary] = []
var _random := RandomNumberGenerator.new()
var _monster_position_resolver := Callable()


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
	event_sequence = 0
	working_energy_regen_factor = regen_factor
	_random.seed = random_seed
	actors.clear()
	monsters.clear()
	monster_runtime.clear()
	combat_events.clear()
	death_events.clear()
	respawn_events.clear()
	return DomainResult.ok(self)


## Installs an authority-owned [param resolver] for static-map monster movement admission.
## [param resolver] Callable receiving monster ID, current position and requested position, then returning an admitted `Vector2`.
## Design: AI owns intent and speed while the map/navigation module remains the sole walkability authority.
func set_monster_position_resolver(resolver: Callable) -> void:
	_monster_position_resolver = resolver


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
	var engagement_policy := StringName(definition.get("engagement_policy", "unresponsive"))
	if engagement_policy not in [&"unresponsive", &"retaliatory", &"aggressive"]:
		return DomainResult.failure(&"combat.invalid_engagement_policy", "monster engagement policy is invalid")
	var lifecycle: MonsterLifecycle = MonsterLifecycleScript.new()
	var result := lifecycle.configure(definition, simulation_hz)
	if not result.is_ok:
		return result
	if monsters.has(lifecycle.monster_id):
		return DomainResult.failure(&"combat.duplicate_monster", "monster identity is already registered")
	monsters[lifecycle.monster_id] = lifecycle
	monster_runtime[lifecycle.monster_id] = {
		"species_id": String(definition.get("species_id", "")),
		"display_name": String(definition.get("display_name", lifecycle.monster_id)),
		"combat_actor_id": String(definition.get("combat_actor_id", "")),
		"home_position": lifecycle.position,
		"behavior_profile": StringName(definition.get("behavior_profile", "idle")),
		"engagement_policy": engagement_policy,
		"move_speed": maxf(0.0, float(definition.get("runtime_move_speed", 0.0))),
		"base_attack": maxi(0, int(definition.get("base_attack", 0))),
		"attack_range": maxf(0.0, float(definition.get("attack_range", 0.0))),
		"aggro_radius": maxf(0.0, float(definition.get("aggro_radius", 0.0))),
		"leash_distance": maxf(0.0, float(definition.get("leash_distance", 0.0))),
		"wander_radius": maxf(0.0, float(definition.get("wander_radius", 0.0))),
		"attack_interval_ticks": maxi(1, roundi(float(definition.get("attack_interval_seconds", 1.5)) * simulation_hz)),
		"attack_ready_tick": 0,
		"target_actor_id": "",
		"wander_target": lifecycle.position,
		"next_wander_tick": posmod(hash(lifecycle.monster_id), simulation_hz * 2) + simulation_hz,
		"action": &"idle",
		"facing_index": 6,
	}
	return DomainResult.ok(lifecycle)


## Removes the vehicle owned by [param actor_id] from this map-scoped combat world.
## [param actor_id] Authenticated entity leaving the map instance or expiring its session.
## Returns true when an actor existed and was removed.
func unregister_vehicle(actor_id: String) -> bool:
	return actors.erase(actor_id)


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
	var runtime: Dictionary = monster_runtime[target_id]
	if StringName(runtime["engagement_policy"]) in [&"retaliatory", &"aggressive"] and monster.is_alive():
		runtime["target_actor_id"] = actor_id
	var event := _record_combat_event({
		"event_type": &"energy_cannon_hit",
		"server_tick": current_tick,
		"attacker_id": actor_id,
		"target_entity_id": target_id,
		"weapon_id": weapon["weapon_id"],
		"damage": damage_result.value["applied_damage"],
		"target_health": damage_result.value["health"],
		"working_energy": vehicle_state.working_energy,
		"cooldown_ready_tick": actor["cooldown_ready_ticks"][ability_id],
	})
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
				var runtime: Dictionary = monster_runtime[monster_id]
				monster.position = runtime["home_position"]
				runtime["action"] = &"idle"
				runtime["target_actor_id"] = ""
				runtime["wander_target"] = runtime["home_position"]
				runtime["next_wander_tick"] = current_tick + simulation_hz
				var respawn_event := {
					"event_type": &"monster_respawned",
					"server_tick": current_tick,
					"monster_id": monster_id,
					"death_generation": monster.death_generation,
				}
				respawn_events.append(respawn_event)
				emitted_respawns.append(respawn_event)
			if monster.is_alive():
				_simulate_monster_tick(monster_id, fixed_delta)
	return DomainResult.ok(emitted_respawns)


## Builds a client-safe combat snapshot scoped to [param actor_id]'s map instance.
## [param actor_id] Authenticated local vehicle whose private resource state is included.
## Returns local vehicle resources plus public monster presentation/combat facts, or an empty dictionary for unknown actors.
## Design: Definitions and random rolls remain server-side; clients receive only current authoritative results.
func snapshot_for_actor(actor_id: String) -> Dictionary:
	if not actors.has(actor_id):
		return {}
	var actor: Dictionary = actors[actor_id]
	var map_instance_id := String(actor["map_instance_id"])
	var monster_snapshots: Array[Dictionary] = []
	var monster_ids := monsters.keys()
	monster_ids.sort()
	for monster_id: String in monster_ids:
		var monster: MonsterLifecycle = monsters[monster_id]
		if monster.map_instance_id != map_instance_id:
			continue
		var runtime: Dictionary = monster_runtime[monster_id]
		monster_snapshots.append({
			"entity_id": monster_id,
			"species_id": runtime["species_id"],
			"display_name": runtime["display_name"],
			"combat_actor_id": runtime["combat_actor_id"],
			"position": [monster.position.x, monster.position.y],
			"health": monster.health,
			"max_health": monster.max_health,
			"alive": monster.is_alive(),
			"action": String(runtime["action"]),
			"facing_index": int(runtime["facing_index"]),
		})
	return {
		"server_tick": current_tick,
		"local_entity_id": actor_id,
		"local_vehicle": (actor["vehicle_state"] as VehicleCombatState).to_dictionary(),
		"monsters": monster_snapshots,
		"recent_events": combat_events.slice(maxi(0, combat_events.size() - 32)).duplicate(true),
	}


## Advances one configured monster [param monster_id] by [param fixed_delta] under server authority.
## [param monster_id] Registered lifecycle and behavior identity.
## [param fixed_delta] One fixed simulation interval in seconds.
## Design: Target selection, movement, cooldown and vehicle damage are never accepted from client payloads.
func _simulate_monster_tick(monster_id: String, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var runtime: Dictionary = monster_runtime[monster_id]
	var target_id := _engaged_actor_id(monster)
	if target_id.is_empty():
		_simulate_unengaged_monster(monster_id, fixed_delta)
		return
	var actor: Dictionary = actors[target_id]
	var vehicle_state: VehicleCombatState = actor["vehicle_state"]
	var target_position: Vector2 = actor["position"]
	var home_position: Vector2 = runtime["home_position"]
	if monster.position.distance_to(home_position) > float(runtime["leash_distance"]):
		_move_monster_towards_home(monster_id, fixed_delta)
		return
	runtime["target_actor_id"] = target_id
	var distance := monster.position.distance_to(target_position)
	if distance > float(runtime["attack_range"]):
		_move_monster(monster_id, target_position, fixed_delta)
		return
	runtime["action"] = &"attack"
	_update_monster_facing(runtime, target_position - monster.position)
	if current_tick < int(runtime["attack_ready_tick"]):
		return
	runtime["attack_ready_tick"] = current_tick + int(runtime["attack_interval_ticks"])
	var damage := int(runtime["base_attack"])
	var damage_result := vehicle_state.apply_damage(damage)
	if not damage_result.is_ok:
		return
	_record_combat_event({
		"event_type": &"monster_attack_resolved",
		"server_tick": current_tick,
		"attacker_id": monster_id,
		"target_entity_id": target_id,
		"damage": int(damage_result.value["applied_damage"]),
		"target_health": int(damage_result.value["health"]),
		"target_destroyed": bool(damage_result.value["destroyed"]),
	})


## 依据 [param monster] 的三态接战策略解析当前目标。
## Returns 不还击时恒为空；反击型只保留受击目标；主动型可自行搜索最近玩家。
## Design: `npcinfo.attr_10` 的 0/1/2 在数据层转换为枚举，运行时不依赖怪物名称。
func _engaged_actor_id(monster: MonsterLifecycle) -> String:
	var runtime: Dictionary = monster_runtime[monster.monster_id]
	var current_target := String(runtime["target_actor_id"])
	if not current_target.is_empty() and _is_valid_actor_target(monster, current_target):
		return current_target
	runtime["target_actor_id"] = ""
	if StringName(runtime["engagement_policy"]) == &"aggressive":
		return _nearest_alive_actor(monster)
	return ""


## 验证 [param actor_id] 是否仍是 [param monster] 同地图上的存活目标。
## Returns 身份、地图与载具生命都有效时返回 `true`。
func _is_valid_actor_target(monster: MonsterLifecycle, actor_id: String) -> bool:
	if not actors.has(actor_id):
		return false
	var actor: Dictionary = actors[actor_id]
	var state: VehicleCombatState = actor["vehicle_state"]
	return state.health > 0 and String(actor["map_instance_id"]) == monster.map_instance_id


## 为 [param event] 分配单调事件号、写入有界重放窗口并返回记录副本。
## Returns 包含 `event_id` 的权威事件。
## Design: 快照携带短事件窗口以容忍 UDP/快照丢包，客户端按事件号去重。
func _record_combat_event(event: Dictionary) -> Dictionary:
	event_sequence += 1
	var recorded := event.duplicate(true)
	recorded["event_id"] = event_sequence
	combat_events.append(recorded)
	if combat_events.size() > 64:
		combat_events.pop_front()
	return recorded


## Finds the nearest living actor that [param monster] can aggro on its own map.
## [param monster] Server-owned monster lifecycle used for map and range filtering.
## Returns an actor ID or an empty string when no eligible vehicle is within aggro range.
func _nearest_alive_actor(monster: MonsterLifecycle) -> String:
	var runtime: Dictionary = monster_runtime[monster.monster_id]
	var best_id := ""
	var best_distance := INF
	for actor_id: String in actors:
		var actor: Dictionary = actors[actor_id]
		var state: VehicleCombatState = actor["vehicle_state"]
		if state.health <= 0 or String(actor["map_instance_id"]) != monster.map_instance_id:
			continue
		var distance := monster.position.distance_to(actor["position"])
		if distance <= float(runtime["aggro_radius"]) and distance < best_distance:
			best_id = actor_id
			best_distance = distance
	return best_id


## Moves [param monster_id] toward its configured home point by one [param fixed_delta].
## [param monster_id] Registered monster returning after losing or leashing a target.
## [param fixed_delta] One fixed simulation interval in seconds.
func _move_monster_towards_home(monster_id: String, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var runtime: Dictionary = monster_runtime[monster_id]
	runtime["target_actor_id"] = ""
	var home_position: Vector2 = runtime["home_position"]
	if monster.position.distance_to(home_position) <= 1.0:
		runtime["action"] = &"idle"
		return
	_move_monster(monster_id, home_position, fixed_delta)


## Simulates deterministic idle roaming for [param monster_id] by [param fixed_delta].
## [param monster_id] Registered monster without an eligible aggro target.
## [param fixed_delta] One fixed simulation interval controlling admitted displacement.
## Design: The authority selects reproducible patrol points inside configured wander radius; clients never randomize monster position.
func _simulate_unengaged_monster(monster_id: String, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var runtime: Dictionary = monster_runtime[monster_id]
	runtime["target_actor_id"] = ""
	var home_position: Vector2 = runtime["home_position"]
	var wander_radius := float(runtime["wander_radius"])
	if wander_radius <= 0.0:
		_move_monster_towards_home(monster_id, fixed_delta)
		return
	if monster.position.distance_to(home_position) > wander_radius + 8.0:
		_move_monster_towards_home(monster_id, fixed_delta)
		return
	var wander_target: Vector2 = runtime["wander_target"]
	if current_tick >= int(runtime["next_wander_tick"]) or monster.position.distance_to(wander_target) <= 2.0:
		var phase_degrees := posmod(hash(monster_id) + current_tick * 47, 360)
		var radius_factor := 0.35 + float(posmod(hash(monster_id) + current_tick, 60)) / 100.0
		wander_target = home_position + Vector2.RIGHT.rotated(deg_to_rad(phase_degrees)) * wander_radius * radius_factor
		runtime["wander_target"] = wander_target
		runtime["next_wander_tick"] = current_tick + simulation_hz * 4
	_move_monster(monster_id, wander_target, fixed_delta)


## Requests one authority-admitted movement step for [param monster_id] toward [param target_position].
## [param monster_id] Registered monster whose lifecycle position will change.
## [param target_position] Server-selected target or home coordinate.
## [param fixed_delta] One fixed simulation interval controlling maximum displacement.
func _move_monster(monster_id: String, target_position: Vector2, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var runtime: Dictionary = monster_runtime[monster_id]
	var delta := target_position - monster.position
	if delta.is_zero_approx():
		runtime["action"] = &"idle"
		return
	var requested := monster.position + delta.normalized() * minf(delta.length(), float(runtime["move_speed"]) * fixed_delta)
	var admitted := requested
	if _monster_position_resolver.is_valid():
		var resolved: Variant = _monster_position_resolver.call(monster_id, monster.position, requested)
		if resolved is Vector2:
			admitted = resolved
	if admitted.is_finite():
		monster.position = admitted
		runtime["action"] = &"move"
		_update_monster_facing(runtime, delta)


## Quantizes [param direction] into the shared eight-direction index on [param runtime].
## [param runtime] Mutable server presentation state for one monster.
## [param direction] Intended world-space motion or aim vector.
func _update_monster_facing(runtime: Dictionary, direction: Vector2) -> void:
	if direction.is_zero_approx():
		return
	runtime["facing_index"] = posmod(-roundi(direction.angle() / (PI / 4.0)), 8)


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
