class_name AuthoritativeMapInstance
extends RefCounted

const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const EntityScript := preload("res://scripts/server/authoritative_entity.gd")
const MoveIntentContract := preload("res://scripts/network/contracts/move_intent.gd")
const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")
const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")

var definition
var navigation
var entities: Dictionary = {}
var movement_speed_cap := 240.0
var dynamic_blocking_enabled := true
var dynamic_blocking_radius := 18.0
var instance_id := ""
var combat_module: AuthoritativeCombatModule
var _combat_catalog
var _combat_assembly: Dictionary = {}
var _combat_weapons: Dictionary = {}


## Loads and validates the requested resource data.
## [param map_config_path] Resource or movement path consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func load_map(map_config_path: String) -> Dictionary:
	var loader = MapDefinitionLoaderScript.new()
	definition = loader.load_file(map_config_path)
	if definition == null:
		return _failure(&"invalid_map_definition", "; ".join(loader.errors))
	instance_id = "%s.instance.1" % definition.map_id
	navigation = DiamondNavigationScript.new()
	if not navigation.load_from(
		definition.navigation_data_path,
		definition.navigation_grid_size,
		definition.navigation_cell_size,
	):
		definition = null
		return _failure(&"invalid_navigation", "map navigation failed to load")
	return _success(definition)


## Configures optional map-scoped combat from [param catalog] at [param simulation_hz].
## [param catalog] Validated gameplay definition catalog owned by the server process.
## [param simulation_hz] Fixed authority frequency used for cooldown, AI and respawn timing.
## Returns success with the monster count, including zero for maps without an encounter.
## Design: Map instances own combat populations so spawn rules and interest snapshots remain map-scoped.
func configure_combat(catalog, simulation_hz: int) -> Dictionary:
	if definition == null or navigation == null:
		return _failure(&"combat.map_not_loaded", "load map navigation before combat")
	var lifecycle_result = catalog.monster_lifecycles_for_map(String(definition.map_id), instance_id)
	if not lifecycle_result.is_ok:
		return _failure(lifecycle_result.error_code, lifecycle_result.error_message)
	if lifecycle_result.value.is_empty():
		return _success(0)
	var assembly_result = catalog.starter_vehicle_assembly(10, {
		"base_speed_multiplier": 1500.0,
		"base_speed_cap": movement_speed_cap,
	})
	var weapon_result = catalog.starter_energy_cannon(simulation_hz)
	if not assembly_result.is_ok or not weapon_result.is_ok:
		return _failure(&"combat.definition_invalid", "starter vehicle combat definitions are invalid")
	_combat_catalog = catalog
	_combat_assembly = assembly_result.value
	_combat_weapons = {"energy_cannon.primary": weapon_result.value}
	combat_module = CombatModuleScript.new()
	var configured = combat_module.configure(simulation_hz, hash(instance_id), 1.0)
	if not configured.is_ok:
		return _failure(configured.error_code, configured.error_message)
	combat_module.set_monster_position_resolver(_resolve_monster_position)
	for raw_definition: Variant in lifecycle_result.value:
		var monster_definition: Dictionary = raw_definition.duplicate(true)
		var requested_position: Vector2 = monster_definition["position"]
		if not navigation.is_walkable(requested_position):
			requested_position = navigation.closest_walkable_position(requested_position)
		if not requested_position.is_finite():
			return _failure(&"combat.no_monster_spawn", "monster group has no walkable spawn")
		monster_definition["position"] = requested_position
		var registration = combat_module.register_monster(monster_definition)
		if not registration.is_ok:
			return _failure(registration.error_code, registration.error_message)
	for entity_id: String in entities:
		var registration := _register_vehicle_combat(entity_id)
		if not registration.ok:
			return registration
	return _success(combat_module.monsters.size())


## Builds the requested runtime object from configuration data.
## [param entity_id] Stable identifier of the target value.
## [param requested_position] World-space position used by the operation.
## [param movement_speed] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func spawn_entity(entity_id: String, requested_position: Vector2, movement_speed: float) -> Dictionary:
	if definition == null or navigation == null:
		return _failure(&"map_not_loaded", "load a map before spawning entities")
	if entity_id.is_empty() or entities.has(entity_id):
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "entity_id must be non-empty and unique")
	if not requested_position.is_finite():
		return _failure(&"invalid_position", "spawn position must be finite")
	if movement_speed <= 0.0 or movement_speed > movement_speed_cap:
		return _failure(&"invalid_speed", "movement speed exceeds the server cap")
	var spawn_position := admitted_spawn_position(requested_position, StringName(entity_id))
	if not spawn_position.is_finite():
		return _failure(&"no_walkable_spawn", "map has no walkable spawn near requested position")
	var entity: AuthoritativeEntity = EntityScript.new()
	entity.entity_id = entity_id
	entity.map_instance_id = instance_id
	entity.position = spawn_position
	entity.target_position = spawn_position
	entity.movement_speed = movement_speed
	entities[entity_id] = entity
	if combat_module != null:
		var combat_result := _register_vehicle_combat(entity_id)
		if not combat_result.ok:
			entities.erase(entity_id)
			return combat_result
	return _success(entity)


## Resolves an admitted spawn near [param requested_position] while excluding [param entity_id].
## [param requested_position] Server-owned entry or initial spawn coordinate.
## [param entity_id] Existing entity ignored for same-instance portal admission, or a new entity ID.
## Returns the nearest statically and dynamically available point, or [constant Vector2.INF].
## Design: Initial spawn and map transfer share one target-admission policy without mutating navigation.
func admitted_spawn_position(
	requested_position: Vector2,
	entity_id: StringName = &"",
) -> Vector2:
	var spawn_position := requested_position
	if not navigation.is_walkable(spawn_position):
		spawn_position = navigation.closest_walkable_position(spawn_position)
	if not spawn_position.is_finite():
		return Vector2.INF
	if dynamic_blocking_enabled:
		spawn_position = _closest_dynamically_available_position(spawn_position, entity_id)
	return spawn_position


## Mutates the managed collection for the requested value.
## [param entity_id] Stable identifier of the target value.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func remove_entity(entity_id: String) -> bool:
	if combat_module != null:
		combat_module.unregister_vehicle(entity_id)
	return entities.erase(entity_id)


## Resolves an authenticated ability [param raw_intent] for [param entity_id] inside this map authority.
## [param entity_id] Session-owned vehicle entity selected by the server transport layer.
## [param raw_intent] Untrusted shared ability contract from the network boundary.
## Returns the authoritative combat result without accepting damage, energy or position from the client.
func handle_use_ability(entity_id: String, raw_intent: Variant):
	if combat_module == null:
		return _failure(&"combat.not_available", "this map has no configured combat encounter")
	var result = combat_module.handle_energy_cannon_attack(entity_id, raw_intent)
	return _success(result.value) if result.is_ok else _failure(result.error_code, result.error_message)


## Processes the requested protocol or gameplay operation.
## [param entity_id] Stable identifier of the target value.
## [param raw_intent] Serialized input received at the subsystem boundary.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func handle_move_intent(entity_id: String, raw_intent: Variant) -> Dictionary:
	var entity: AuthoritativeEntity = entities.get(entity_id)
	if entity == null:
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "entity is not present in this map instance")
	var intent_result = MoveIntentContract.from_dictionary(raw_intent)
	if not intent_result.is_ok:
		return _failure(intent_result.error_code, intent_result.error_message)
	var intent = intent_result.value
	if intent.map_instance_id != instance_id:
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "move intent targets a different map instance")
	var sequence: int = intent.input_sequence
	if sequence <= entity.last_input_sequence:
		return _failure(ErrorCodes.STALE_SEQUENCE, "sequence was already acknowledged")
	var requested_position: Vector2 = intent.requested_world_point
	var authoritative_target := requested_position
	if not navigation.is_walkable(authoritative_target):
		authoritative_target = navigation.closest_reachable_position(
			entity.position, requested_position
		)
	if not authoritative_target.is_finite():
		return _failure(&"unreachable_target", "no reachable fallback exists")
	var static_target := authoritative_target
	if dynamic_blocking_enabled and not _position_has_dynamic_clearance(
		authoritative_target, entity_id, true
	):
		authoritative_target = _closest_dynamically_available_position(
			authoritative_target, entity_id
		)
	if not authoritative_target.is_finite():
		return _failure(&"dynamic_target_blocked", "no target clears other entity foot points")
	var authoritative_path := _find_authoritative_path(entity_id, entity.position, authoritative_target)
	if authoritative_path.is_empty():
		return _failure(&"unreachable_target", "no authoritative path exists")
	entity.set_path(authoritative_path, authoritative_target, sequence)
	return _success({
		"sequence": sequence,
		"requested_target": requested_position,
		"authoritative_target": authoritative_target,
		"adjusted": not requested_position.is_equal_approx(authoritative_target),
		"dynamic_adjusted": not static_target.is_equal_approx(authoritative_target),
	})


## Advances the managed state using the supplied update.
## [param delta] Elapsed time in seconds for this update.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func simulate(delta: float) -> void:
	var entity_ids := entities.keys()
	entity_ids.sort()
	for entity_id: String in entity_ids:
		var entity: AuthoritativeEntity = entities[entity_id]
		if not dynamic_blocking_enabled or entities.size() <= 1:
			entity.simulate(delta)
			continue
		var motion_state := _capture_motion_state(entity)
		var previous_position: Vector2 = entity.position
		entity.simulate(delta)
		if (
			not entity.position.is_equal_approx(previous_position)
			and _movement_intersects_dynamic_blocker(
				entity_id, previous_position, entity.position
			)
		):
			_restore_motion_state(entity, motion_state)
	if combat_module != null:
		for entity_id: String in entities:
			combat_module.update_actor_position(entity_id, entities[entity_id].position)
		combat_module.advance_ticks(1)


## Finds the nearest static navigation point that clears every other entity foot point and reserved destination.
## [param requested_position] Preferred world-space target or spawn position.
## [param excluded_entity_id] Entity omitted from clearance checks, or an empty name during spawning.
## Returns the nearest available navigation point, or [constant Vector2.INF] when no point qualifies.
## Design: Dynamic occupancy is layered over immutable map navigation and never mutates static walkability data.
func _closest_dynamically_available_position(
	requested_position: Vector2,
	excluded_entity_id: StringName,
) -> Vector2:
	if _position_has_dynamic_clearance(requested_position, excluded_entity_id, true):
		return requested_position
	var best_position := Vector2.INF
	var best_distance_squared := INF
	for point_id: int in navigation.graph.get_point_ids():
		var candidate: Vector2 = navigation.graph.get_point_position(point_id)
		if not _position_has_dynamic_clearance(candidate, excluded_entity_id, true):
			continue
		var distance_squared := candidate.distance_squared_to(requested_position)
		if distance_squared < best_distance_squared:
			best_position = candidate
			best_distance_squared = distance_squared
	return best_position


## Reports whether [param candidate] respects the configured clearance from other current and optionally reserved foot points.
## [param candidate] World-space position being considered for an entity.
## [param excluded_entity_id] Entity whose own position and reservation are ignored.
## [param include_reserved_targets] Whether moving entities' terminal destinations also reserve clearance.
## Returns true when no relevant entity point is closer than [member dynamic_blocking_radius].
## Design: The radius is the minimum centre-to-centre foot-point distance, not a per-entity radius to be doubled.
func _position_has_dynamic_clearance(
	candidate: Vector2,
	excluded_entity_id: StringName,
	include_reserved_targets: bool,
) -> bool:
	var minimum_distance_squared := dynamic_blocking_radius * dynamic_blocking_radius
	for other_entity_id: String in entities:
		if StringName(other_entity_id) == excluded_entity_id:
			continue
		var other: AuthoritativeEntity = entities[other_entity_id]
		if candidate.distance_squared_to(other.position) < minimum_distance_squared:
			return false
		if (
			include_reserved_targets
			and not other.target_position.is_equal_approx(other.position)
			and candidate.distance_squared_to(other.target_position) < minimum_distance_squared
		):
			return false
	return true


## Builds a static-map path while temporarily excluding navigation nodes occupied by other entities.
## [param entity_id] Moving entity omitted from dynamic blockers.
## [param from_position] Current authoritative foot point.
## [param to_position] Already validated authoritative destination.
## Returns an unsimplified path that cannot reintroduce disabled nodes through line-of-sight shortening.
## Design: Point disabling is scoped to this synchronous query and restored immediately, preserving shared static navigation.
func _find_authoritative_path(
	entity_id: String,
	from_position: Vector2,
	to_position: Vector2,
) -> PackedVector2Array:
	if not dynamic_blocking_enabled or entities.size() <= 1:
		return navigation.find_path(from_position, to_position)
	var disabled_point_ids: Array[int] = []
	var minimum_distance_squared := dynamic_blocking_radius * dynamic_blocking_radius
	var from_point_id: int = navigation.cell_id(navigation.world_to_cell(from_position))
	for point_id: int in navigation.graph.get_point_ids():
		if point_id == from_point_id or navigation.graph.is_point_disabled(point_id):
			continue
		var point_position: Vector2 = navigation.graph.get_point_position(point_id)
		for other_entity_id: String in entities:
			if other_entity_id == entity_id:
				continue
			var other: AuthoritativeEntity = entities[other_entity_id]
			if point_position.distance_squared_to(other.position) < minimum_distance_squared:
				navigation.graph.set_point_disabled(point_id, true)
				disabled_point_ids.append(point_id)
				break
	var path: PackedVector2Array = navigation.find_path(from_position, to_position, false)
	for point_id: int in disabled_point_ids:
		navigation.graph.set_point_disabled(point_id, false)
	return path


## Captures the fields mutated by one entity simulation step so a dynamically blocked step can be rolled back atomically.
## [param entity] Authoritative entity about to be simulated.
## Returns a private motion-state snapshot used only within the current server tick.
## Design: Rollback retains the entity's path command while preventing partial waypoint or facing advancement.
func _capture_motion_state(entity: AuthoritativeEntity) -> Dictionary:
	return {
		"position": entity.position,
		"path_index": entity.path_index,
		"facing_index": entity.facing_index,
		"action": entity.action,
		"state_revision": entity.state_revision,
	}


## Restores [param entity] from a private [param motion_state] after dynamic collision rejection.
## [param entity] Entity whose attempted step was blocked.
## [param motion_state] State captured immediately before simulation.
## Design: A blocked entity remains idle for the snapshot but keeps its route for a later tick when space clears.
func _restore_motion_state(entity: AuthoritativeEntity, motion_state: Dictionary) -> void:
	entity.position = motion_state.position
	entity.path_index = motion_state.path_index
	entity.facing_index = motion_state.facing_index
	entity.action = &"idle"
	entity.state_revision = int(motion_state.state_revision) + 1


## Reports whether a proposed foot-point segment enters another entity's configured blocking radius.
## [param entity_id] Moving entity omitted from the blocker set.
## [param from_position] Start of the proposed authoritative step.
## [param to_position] End of the proposed authoritative step.
## Returns true when the segment would overlap another current foot point.
## Design: Segment clearance prevents high-speed tunnelling and deterministic entity-order swaps during one server tick.
func _movement_intersects_dynamic_blocker(
	entity_id: String,
	from_position: Vector2,
	to_position: Vector2,
) -> bool:
	var minimum_distance_squared := dynamic_blocking_radius * dynamic_blocking_radius
	for other_entity_id: String in entities:
		if other_entity_id == entity_id:
			continue
		var other: AuthoritativeEntity = entities[other_entity_id]
		var closest_point := _closest_point_on_segment(
			other.position, from_position, to_position
		)
		if closest_point.distance_squared_to(other.position) < minimum_distance_squared:
			return true
	return false


## Projects [param point] onto the finite segment from [param segment_start] to [param segment_end].
## [param point] World-space point tested against the movement segment.
## [param segment_start] First segment endpoint.
## [param segment_end] Second segment endpoint.
## Returns the closest point on the finite segment.
func _closest_point_on_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2,
) -> Vector2:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return segment_start
	var weight := clampf((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return segment_start + segment * weight


## Serializes the current state into a transport-safe dictionary.
## [param server_tick] Sequence, tick, or index value used by the operation.
## [param server_time_seconds] Elapsed time in seconds for this update.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func snapshot(server_tick: int, server_time_seconds: float) -> Dictionary:
	var entity_snapshots: Array[Dictionary] = []
	var entity_ids := entities.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		entity_snapshots.append(entities[entity_id].snapshot(server_tick))
	return {
		"server_tick": server_tick,
		"server_time_seconds": server_time_seconds,
		"entities": entity_snapshots,
	}


## Serializes the world plus private combat state visible to [param actor_id].
## [param server_tick] Current fixed authority tick.
## [param server_time_seconds] Current simulation time in seconds.
## [param actor_id] Authenticated recipient entity whose vehicle resources may be disclosed.
## Returns the ordinary world snapshot with an optional `combat` document.
func snapshot_for_actor(server_tick: int, server_time_seconds: float, actor_id: String) -> Dictionary:
	var result := snapshot(server_tick, server_time_seconds)
	if combat_module != null:
		result["combat"] = combat_module.snapshot_for_actor(actor_id)
	return result


## Registers [param entity_id] with the already configured starter vehicle combat definition.
## [param entity_id] Existing movement entity entering this combat-enabled map instance.
## Returns a map-style success/failure result while all mutable resources remain server-owned.
func _register_vehicle_combat(entity_id: String) -> Dictionary:
	var entity: AuthoritativeEntity = entities.get(entity_id)
	if entity == null or combat_module == null:
		return _failure(&"combat.invalid_actor", "combat vehicle registration requires a map entity")
	var result = combat_module.register_vehicle(
		entity_id, instance_id, entity.position, _combat_assembly, _combat_weapons
	)
	return _success(result.value) if result.is_ok else _failure(result.error_code, result.error_message)


## Admits one monster step from [param current_position] toward [param requested_position].
## [param monster_id] Stable monster identity retained for future dynamic avoidance policies.
## [param current_position] Current server lifecycle foot point.
## [param requested_position] AI-selected next fixed-step position.
## Returns a walkable next position, or the unchanged current point when static navigation rejects the step.
## Design: Combat AI cannot bypass the same immutable navigation authority used by players.
func _resolve_monster_position(
	monster_id: String,
	current_position: Vector2,
	requested_position: Vector2,
) -> Vector2:
	if monster_id.is_empty() or navigation == null:
		return current_position
	if navigation.is_walkable(requested_position):
		return requested_position
	var fallback: Vector2 = navigation.closest_reachable_position(current_position, requested_position)
	return fallback if fallback.is_finite() else current_position


## Performs the `success` operation.
## [param value] New value requested by the caller.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## Performs the `failure` operation.
## [param code] Stable identifier of the target value.
## [param message] Serialized input received at the subsystem boundary.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
