class_name NpcBase
extends "res://scripts/characters/world_character.gd"

enum PatrolState { WAITING, MOVING }

const DEFAULT_MOVEMENT_SPEED := 203.0
const DEFAULT_ANIMATION_SPEED_SCALE := 1.0

var npc_id := ""
var npc_definition: Dictionary
var navigation: RefCounted
var patrol_points: Array[Dictionary] = []
var patrol_state := PatrolState.WAITING
var patrol_index := 0
var path_points := PackedVector2Array()
var path_index := 0
var movement_speed := DEFAULT_MOVEMENT_SPEED
var wait_remaining := 0.0
var interaction_active := false
var random := RandomNumberGenerator.new()


## Configures the instance from validated runtime inputs.
## [param character_set] Input value consumed by the operation.
## [param definition] Configuration data that controls the operation.
## [param navigation_service] Input value consumed by the operation.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func configure_npc(
	character_set: Dictionary,
	definition: Dictionary,
	navigation_service: RefCounted,
) -> void:
	npc_definition = definition
	npc_id = String(definition.get("id", "npc"))
	navigation = navigation_service
	name = npc_id
	var requested_spawn := _vector_from(definition["spawn"])
	var spawn := requested_spawn
	if not navigation.is_walkable(spawn):
		spawn = navigation.closest_walkable_position(spawn)
	if not spawn.is_finite():
		push_error("NPC %s has no walkable spawn point" % npc_id)
		spawn = requested_spawn
	position = spawn
	var name_offset := _vector_from(definition.get("name_offset", [-64, -88]))
	configure(
		character_set,
		String(definition.get("name", npc_id)),
		Color.WHITE,
		name_offset,
	)
	var patrol: Dictionary = definition.get("patrol", {})
	movement_speed = float(patrol.get("speed", DEFAULT_MOVEMENT_SPEED))
	set_animation_speed_scale(
		float(patrol.get("animation_speed_scale", DEFAULT_ANIMATION_SPEED_SCALE))
	)
	for raw_point in patrol.get("points", []):
		var point: Dictionary = raw_point.duplicate(true)
		var requested := _vector_from(point["position"])
		var resolved := requested
		if not navigation.is_walkable(requested):
			resolved = navigation.closest_reachable_position(spawn, requested)
		point["resolved_position"] = resolved
		patrol_points.append(point)
	if patrol_points.is_empty():
		patrol_points.append({"resolved_position": spawn, "dwell": [2.0, 4.0]})
	patrol_index = 0
	random.randomize()
	random.seed = random.seed ^ hash(npc_id)
	wait_remaining = _random_seconds(patrol.get("initial_delay", [0.4, 2.4]), 1.0)
	set_action("stand", current_direction)


## Advances frame-based presentation state.
## [param delta] Elapsed time in seconds for this update.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _process(delta: float) -> void:
	if interaction_active or patrol_points.size() < 2:
		return
	if patrol_state == PatrolState.WAITING:
		wait_remaining -= delta
		if wait_remaining <= 0.0:
			_start_next_leg()
	else:
		_advance_movement(delta)


## Updates the managed state with the supplied value.
## [param active] Whether the corresponding behavior is enabled.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func set_interaction_active(active: bool) -> void:
	interaction_active = active
	if active:
		set_action("stand", current_direction)
	elif patrol_state == PatrolState.MOVING:
		_begin_path_segment()


## Retrieves the requested value from the managed state.
## Returns Structured result data produced by the operation.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func get_interaction_data() -> Dictionary:
	var interaction: Dictionary = npc_definition.get("interaction", {})
	var actions: Array = interaction.get("actions", [])
	if actions.is_empty():
		actions = default_actions()
	return {
		"npc_id": npc_id,
		"kind": String(npc_definition.get("kind", "ambient")),
		"title": String(npc_definition.get("name", npc_id)),
		"body": String(interaction.get("body", "对方似乎暂时没有事情要交给你。")),
		"actions": actions,
	}


## Provides the default interaction actions exposed by this NPC type.
## Returns the resulting collection.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func default_actions() -> Array:
	return [{"id": "talk", "label": "交谈"}]


## Processes the requested protocol or gameplay operation.
## [param action_id] Stable identifier of the target value.
## Returns the resolved string value.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func handle_action(action_id: String) -> String:
	return "%s 的“%s”功能尚未接入" % [String(npc_definition.get("name", npc_id)), action_id]


## Performs the `start_next_leg` operation.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _start_next_leg() -> void:
	patrol_index = (patrol_index + 1) % patrol_points.size()
	var target := _patrol_position(patrol_index)
	path_points = navigation.find_path(position, target)
	if path_points.is_empty():
		patrol_state = PatrolState.WAITING
		wait_remaining = 1.0
		return
	path_index = 1 if path_points.size() > 1 else 0
	patrol_state = PatrolState.MOVING
	_begin_path_segment()


## Advances the managed state using the supplied update.
## [param delta] Elapsed time in seconds for this update.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _advance_movement(delta: float) -> void:
	if path_index >= path_points.size():
		_arrive_at_patrol_point()
		return
	var waypoint := path_points[path_index]
	var motion := waypoint - position
	var step := movement_speed * delta
	if motion.length() <= step:
		position = waypoint
		path_index += 1
		if path_index >= path_points.size():
			_arrive_at_patrol_point()
		else:
			_begin_path_segment()
	else:
		position += motion.normalized() * step


## Performs the `begin_path_segment` operation.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _begin_path_segment() -> void:
	if path_index >= path_points.size():
		return
	var motion := path_points[path_index] - position
	if motion.length_squared() <= 0.01:
		return
	current_direction = posmod(-roundi(motion.angle() / (PI / 4.0)), 8)
	set_action("move", current_direction)


## Performs the `arrive_at_patrol_point` operation.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _arrive_at_patrol_point() -> void:
	patrol_state = PatrolState.WAITING
	path_points = PackedVector2Array()
	path_index = 0
	set_action("stand", current_direction)
	wait_remaining = _random_seconds(patrol_points[patrol_index].get("dwell", [1.5, 3.5]), 2.0)


## Performs the `patrol_position` operation.
## [param index] Sequence, tick, or index value used by the operation.
## Returns the resolved coordinate.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _patrol_position(index: int) -> Vector2:
	return patrol_points[index]["resolved_position"]


## Performs the `random_seconds` operation.
## [param value] New value requested by the caller.
## [param fallback] Input value consumed by the operation.
## Returns the result produced by the operation.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _random_seconds(value: Variant, fallback: float) -> float:
	if value is Array and value.size() >= 2:
		return random.randf_range(float(value[0]), float(value[1]))
	return float(value) if value is float or value is int else fallback


## Performs the `vector_from` operation.
## [param value] New value requested by the caller.
## Returns the resolved coordinate.
## Design: Uses the configurable NPC template model; patrol mechanics stay in the base type while subclasses extend interactions.
func _vector_from(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
