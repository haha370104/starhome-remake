class_name AuthoritativeEntity
extends RefCounted

const EntitySnapshotContract := preload("res://scripts/network/contracts/entity_snapshot.gd")

var entity_id := ""
var map_instance_id := ""
var position := Vector2.ZERO
var target_position := Vector2.ZERO
var movement_speed := 203.0
var facing_index := 0
var action := &"idle"
var last_input_sequence := -1
var state_revision := 0
var path := PackedVector2Array()
var path_index := 0


## Updates the managed state with the supplied value.
## [param new_path] Resource or movement path consumed by the operation.
## [param target] World-space position used by the operation.
## [param input_sequence] Sequence, tick, or index value used by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func set_path(new_path: PackedVector2Array, target: Vector2, input_sequence: int) -> void:
	path = new_path
	path_index = 1 if path.size() > 1 else path.size()
	target_position = target
	last_input_sequence = input_sequence
	state_revision += 1
	action = &"walking" if path_index < path.size() else &"idle"
	_update_facing_to_next_point()


## Advances the managed state using the supplied update.
## [param delta] Elapsed time in seconds for this update.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func simulate(delta: float) -> void:
	if delta <= 0.0 or path_index >= path.size():
		action = &"idle"
		return
	var remaining_distance := movement_speed * delta
	while remaining_distance > 0.0 and path_index < path.size():
		var next_point := path[path_index]
		var distance := position.distance_to(next_point)
		if distance <= 0.001:
			position = next_point
			path_index += 1
			_update_facing_to_next_point()
			continue
		if remaining_distance >= distance:
			position = next_point
			remaining_distance -= distance
			path_index += 1
			_update_facing_to_next_point()
		else:
			position = position.move_toward(next_point, remaining_distance)
			remaining_distance = 0.0
	action = &"walking" if path_index < path.size() else &"idle"
	state_revision += 1


## Serializes the current state into a transport-safe dictionary.
## [param server_tick] Sequence, tick, or index value used by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func snapshot(server_tick: int) -> Dictionary:
	var contract = EntitySnapshotContract.new(
		entity_id,
		server_tick,
		position,
		facing_index,
		action,
		movement_speed if action == &"walking" else 0.0,
		state_revision,
		maxi(0, last_input_sequence),
	)
	return contract.to_dictionary()


## Advances the managed state using the supplied update.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _update_facing_to_next_point() -> void:
	if path_index >= path.size():
		return
	var direction := position.direction_to(path[path_index])
	if direction.is_zero_approx():
		return
	# 0 faces east; indices advance clockwise in 45-degree steps.
	var octant := roundi(direction.angle() / (PI / 4.0))
	facing_index = posmod(octant, 8)
