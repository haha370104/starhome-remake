class_name RemoteEntityInterpolator
extends RefCounted

signal presentation_state_changed(entity_id: StringName, state: Dictionary)
signal stale_snapshot_rejected(server_tick: int)

var interpolation_delay_seconds := 0.1
var last_server_tick := -1
var playback_server_time := 0.0

var _tracks: Dictionary = {}
var _latest_server_time := -1.0


## 配置并初始化 `configure` 对应的模块状态。
## [param interpolation_delay] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func configure(interpolation_delay: float = 0.1) -> void:
	interpolation_delay_seconds = maxf(0.0, interpolation_delay)


## 执行 `reset` 对应的模块操作。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func reset() -> void:
	_tracks.clear()
	last_server_tick = -1
	_latest_server_time = -1.0
	playback_server_time = 0.0


## 执行 `push_snapshot` 对应的模块操作。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_time_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entities] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 执行 `advance` 对应的模块操作。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 执行 `sample_entity_at` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_time_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 执行 `presentation_states` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func presentation_states() -> Dictionary:
	var states := {}
	for raw_id in _tracks:
		var entity_id: StringName = raw_id
		states[entity_id] = sample_entity_at(entity_id, playback_server_time)
	return states


## 执行 `tracked_entity_count` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func tracked_entity_count() -> int:
	return _tracks.size()


## 移除并清理 `remove_entity` 对应的模块状态。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func remove_entity(entity_id: StringName) -> void:
	_tracks.erase(entity_id)


## 执行 `presentation_from_sample` 对应的模块操作。
## [param sample] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _presentation_from_sample(sample: Dictionary) -> Dictionary:
	return {
		"position": Vector2(sample["position"]),
		"facing_direction": int(sample["facing_direction"]),
		"action_id": StringName(sample["action_id"]),
		"speed": float(sample["speed"]),
		"server_tick": int(sample["server_tick"]),
	}


## 序列化或保存 `to_vector2` 对应的模块状态。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _to_vector2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO
