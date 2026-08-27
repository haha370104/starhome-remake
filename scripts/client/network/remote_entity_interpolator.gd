class_name RemoteEntityInterpolator
extends RefCounted

signal presentation_state_changed(entity_id: StringName, state: Dictionary)
signal stale_snapshot_rejected(server_tick: int)

var interpolation_delay_seconds := 0.1
var last_server_tick := -1
var playback_server_time := 0.0

var _tracks: Dictionary = {}
var _latest_server_time := -1.0


## Configures the instance from validated runtime inputs.
## [param interpolation_delay] Input value consumed by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func configure(interpolation_delay: float = 0.1) -> void:
	interpolation_delay_seconds = maxf(0.0, interpolation_delay)


## Resets the managed state to its initial value.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func reset() -> void:
	_tracks.clear()
	last_server_tick = -1
	_latest_server_time = -1.0
	playback_server_time = 0.0


## Advances the managed state using the supplied update.
## [param server_tick] Sequence, tick, or index value used by the operation.
## [param server_time_seconds] Elapsed time in seconds for this update.
## [param entities] Input value consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func push_snapshot(server_tick: int, server_time_seconds: float, entities: Array) -> bool:
	if server_tick <= last_server_tick:
		stale_snapshot_rejected.emit(server_tick)
		return false
	last_server_tick = server_tick
	_latest_server_time = maxf(_latest_server_time, server_time_seconds)
	if _tracks.is_empty():
		playback_server_time = server_time_seconds - interpolation_delay_seconds

	for raw_entity in entities:
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		var entity_id := StringName(String(entity.get("entity_id", "")))
		if entity_id == &"" or not entity.has("position"):
			continue
		var sample := {
			"server_tick": server_tick,
			"server_time": server_time_seconds,
			"position": _to_vector2(entity["position"]),
			"facing_direction": int(entity.get("facing_direction", 0)),
			"action_id": StringName(String(entity.get("action_id", "idle"))),
			"speed": float(entity.get("speed", 0.0)),
		}
		var track: Array = _tracks.get(entity_id, [])
		track.append(sample)
		while track.size() > 3:
			track.pop_front()
		_tracks[entity_id] = track
	return true


## Advances the managed state using the supplied update.
## [param delta] Elapsed time in seconds for this update.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func advance(delta: float) -> void:
	if _latest_server_time < 0.0:
		return
	playback_server_time = minf(
		playback_server_time + maxf(0.0, delta),
		_latest_server_time,
	)
	for raw_id in _tracks:
		var entity_id: StringName = raw_id
		presentation_state_changed.emit(entity_id, sample_entity_at(entity_id, playback_server_time))


## Performs the `sample_entity_at` operation.
## [param entity_id] Stable identifier of the target value.
## [param server_time_seconds] Elapsed time in seconds for this update.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func sample_entity_at(entity_id: StringName, server_time_seconds: float) -> Dictionary:
	var track: Array = _tracks.get(entity_id, [])
	if track.is_empty():
		return {}
	if track.size() == 1 or server_time_seconds <= float(track[0]["server_time"]):
		return _presentation_from_sample(track[0])

	for index in range(1, track.size()):
		var previous: Dictionary = track[index - 1]
		var current: Dictionary = track[index]
		if server_time_seconds > float(current["server_time"]):
			continue
		var duration := float(current["server_time"]) - float(previous["server_time"])
		var weight := 1.0 if duration <= 0.0 else clampf(
			(server_time_seconds - float(previous["server_time"])) / duration,
			0.0,
			1.0,
		)
		return {
			"position": Vector2(previous["position"]).lerp(Vector2(current["position"]), weight),
			"facing_direction": int(current["facing_direction"]),
			"action_id": StringName(current["action_id"]),
			"speed": lerpf(float(previous["speed"]), float(current["speed"]), weight),
			"server_tick": int(current["server_tick"]),
		}
	return _presentation_from_sample(track[track.size() - 1])


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func presentation_states() -> Dictionary:
	var states := {}
	for raw_id in _tracks:
		var entity_id: StringName = raw_id
		states[entity_id] = sample_entity_at(entity_id, playback_server_time)
	return states


## Performs the `tracked_entity_count` operation.
## Returns the computed integer value.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func tracked_entity_count() -> int:
	return _tracks.size()


## Mutates the managed collection for the requested value.
## [param entity_id] Stable identifier of the target value.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func remove_entity(entity_id: StringName) -> void:
	_tracks.erase(entity_id)


## Performs the `presentation_from_sample` operation.
## [param sample] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _presentation_from_sample(sample: Dictionary) -> Dictionary:
	return {
		"position": Vector2(sample["position"]),
		"facing_direction": int(sample["facing_direction"]),
		"action_id": StringName(sample["action_id"]),
		"speed": float(sample["speed"]),
		"server_tick": int(sample["server_tick"]),
	}


## Performs the `to_vector2` operation.
## [param value] New value requested by the caller.
## Returns the resolved coordinate.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _to_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO
