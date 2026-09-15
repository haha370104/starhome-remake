class_name AuthoritativeMiningModule
extends RefCounted

const MineSourceScript := preload("res://scripts/domain/mining/mine_source.gd")

const COLLECT_ABILITY_ID := "mining.collect"

var current_tick := 0
var simulation_hz := 20
var map_id := ""
var map_instance_id := ""
var sources: Dictionary = {}

var _catalog
var _navigation
var _policy: Dictionary = {}
var _actions: Dictionary = {}
var _pending_cycles: Dictionary = {}
var _ready_cycles: Array[Dictionary] = []
var _spawn_sequence := 0
var _cycle_sequence := 0
# 每个权威矿源模块拥有独立的 128 位命名空间，避免重启或地图重建后与存档物品编号碰撞。
# 同一预约重试仍使用原 token；不能移除背包的重复入账保护。
var _reward_namespace := Crypto.new().generate_random_bytes(16).hex_encode()
var _next_replenishment_tick := -1
var _last_command_sequences: Dictionary = {}


## 为一张地图建立服务端矿源种群；非采矿地图保持禁用但不报错。
## [param catalog] 调用方传入的 `catalog` 参数。
## [param requested_map_id] 调用方传入的 `requested_map_id` 参数。
## [param requested_instance_id] 调用方传入的 `requested_instance_id` 参数。
## [param requested_simulation_hz] 调用方传入的 `requested_simulation_hz` 参数。
## [param navigation] 调用方传入的 `navigation` 参数。
## 返回该函数计算、查询或操作得到的结果。
func configure(
	catalog,
	requested_map_id: String,
	requested_instance_id: String,
	requested_simulation_hz: int,
	navigation,
) -> DomainResult:
	if catalog == null or requested_map_id.is_empty() or requested_instance_id.is_empty() \
			or requested_simulation_hz <= 0 or navigation == null:
		return DomainResult.failure(&"mining.invalid_configuration", "mining module configuration is invalid")
	_catalog = catalog
	map_id = requested_map_id
	map_instance_id = requested_instance_id
	simulation_hz = requested_simulation_hz
	_navigation = navigation
	_policy = catalog.policy_for_map(map_id)
	if _policy.is_empty():
		return DomainResult.ok(0)
	var maximum := int(_policy["maximum_sources"])
	for _index: int in range(maximum):
		var spawned := _spawn_one()
		if not spawned.is_ok:
			return spawned
	_next_replenishment_tick = _seconds_to_ticks(float(_policy["replenish_interval_seconds"]))
	return DomainResult.ok(sources.size())


## 以点击坐标选择矿源，并在距离、等级满足时启动连续三秒采集周期。
## [param actor_id] 调用方传入的 `actor_id` 参数。
## [param actor_position] 调用方传入的 `actor_position` 参数。
## [param aim_world_position] 调用方传入的 `aim_world_position` 参数。
## [param mining_level] 调用方传入的 `mining_level` 参数。
## [param command_sequence] 调用方传入的 `command_sequence` 参数。
## [param time_reduction_ms] 服务器从已装配接合器派生的间隔减值；周期最短 0.1 秒。
## 返回该函数计算、查询或操作得到的结果。
func begin_collection(
	actor_id: String,
	actor_position: Vector2,
	aim_world_position: Vector2,
	mining_level: int,
	command_sequence: int,
	time_reduction_ms: int = 0,
) -> DomainResult:
	if _policy.is_empty():
		return DomainResult.failure(&"mining.not_available", "this map has no mineral population")
	if actor_id.is_empty() or not actor_position.is_finite() or not aim_world_position.is_finite():
		return DomainResult.failure(&"mining.invalid_request", "mining request identity or position is invalid")
	if command_sequence <= int(_last_command_sequences.get(actor_id, 0)):
		return DomainResult.failure(&"mining.stale_command", "mining command sequence is stale")
	_last_command_sequences[actor_id] = command_sequence
	var source: Variant = _source_at(aim_world_position)
	if source == null:
		return DomainResult.failure(&"mining.source_missing", "no mine source was selected")
	var distance := actor_position.distance_to(source.position)
	if distance < float(_policy["minimum_collection_distance"]) \
			or distance > float(_policy["maximum_collection_distance"]):
		return DomainResult.failure(&"mining.out_of_range", "mine source is outside collection range")
	if mining_level < source.required_mining_level:
		return DomainResult.failure(&"mining.skill_too_low", "mining skill does not meet the source requirement")
	var interval := maxf(0.1, float(_policy["collection_interval_seconds"]) - float(maxi(0, time_reduction_ms)) / 1000.0)
	_actions[actor_id] = {
		"interval_seconds": interval,
		"source_id": source.source_id,
		"next_cycle_tick": current_tick + _seconds_to_ticks(interval),
	}
	return DomainResult.ok({
		"event_type": &"mining_started",
		"actor_id": actor_id,
		"source_id": source.source_id,
		"interval_seconds": interval,
	})


## 移动、换装或其他中断原因停止当前采矿动作。
## [param actor_id] 调用方传入的 `actor_id` 参数。
## [param _reason] 保留中断原因接口，当前模块不按原因区分清理方式。
## 返回该函数计算、查询或操作得到的结果。
func interrupt(actor_id: String, _reason: StringName) -> bool:
	if not _actions.has(actor_id):
		return false
	_actions.erase(actor_id)
	for token: String in _pending_cycles.keys():
		if String(_pending_cycles[token].get("actor_id", "")) == actor_id:
			_pending_cycles.erase(token)
	return true


## 玩家离开实例时清理动作和序号状态。
## [param actor_id] 调用方传入的 `actor_id` 参数。
func unregister_actor(actor_id: String) -> void:
	interrupt(actor_id, &"map_exit")
	_last_command_sequences.erase(actor_id)


## 按服务器固定 tick 推进采矿周期与五分钟补点计时。
## [param tick_count] 调用方传入的 `tick_count` 参数。
func advance_ticks(tick_count: int = 1) -> void:
	for _tick: int in range(maxi(0, tick_count)):
		current_tick += 1
		_replenish_if_due()
		_reserve_due_cycles()


## 判断采矿模块是否没有待结算的玩家动作，允许解除导航引用。
## 返回当前是否能安全休眠。
func can_suspend() -> bool:
	return _actions.is_empty() and _pending_cycles.is_empty() and _ready_cycles.is_empty()


## 解除占内存的导航引用，但保留矿量、点位、序号及补充时钟。
func release_navigation() -> void:
	_navigation = null


## 唤醒时重新绑定导航并按经过时间补点，不逐 tick 重放休眠时间。
## [param navigation] 新加载的当前地图导航。
## [param elapsed_ticks] 休眠期间经过的权威时钟刻数。
func resume_navigation(navigation, elapsed_ticks: int) -> void:
	_navigation = navigation
	current_tick += maxi(0, elapsed_ticks)
	_replenish_if_due()


## 取出本 tick 已到期、等待背包事务的采矿结算预约。
## 返回该函数计算、查询或操作得到的结果。
func drain_ready_cycles() -> Array[Dictionary]:
	var result := _ready_cycles.duplicate(true)
	_ready_cycles.clear()
	return result


## 在背包成功入账后扣减矿源并安排同一目标的下一周期。
## [param token] 调用方传入的 `token` 参数。
## 返回该函数计算、查询或操作得到的结果。
func commit_cycle(token: String) -> DomainResult:
	var reservation_value: Variant = _pending_cycles.get(token)
	if not reservation_value is Dictionary:
		return DomainResult.failure(&"mining.cycle_missing", "mining cycle reservation no longer exists")
	var reservation: Dictionary = reservation_value
	var actor_id := String(reservation["actor_id"])
	var source_id := String(reservation["source_id"])
	var source = sources.get(source_id)
	if source == null:
		_pending_cycles.erase(token)
		_actions.erase(actor_id)
		return DomainResult.failure(&"mining.source_depleted", "mine source disappeared before settlement")
	var extracted: Variant = source.extract(int(reservation["quantity"]))
	if not extracted.is_ok:
		return extracted
	_pending_cycles.erase(token)
	var depleted: bool = source.remaining <= 0
	if depleted:
		sources.erase(source_id)
		_actions.erase(actor_id)
	elif _actions.has(actor_id):
		_actions[actor_id]["next_cycle_tick"] = current_tick \
			+ _seconds_to_ticks(float(_actions[actor_id].get("interval_seconds", _policy["collection_interval_seconds"])))
	return DomainResult.ok({
		"event_type": &"mining_collected",
		"actor_id": actor_id,
		"source_id": source_id,
		"mineral_id": source.mineral_id,
		"display_name": source.display_name,
		"item_definition_id": source.item_definition_id,
		"quantity": int(reservation["quantity"]),
		"remaining": source.remaining,
		"depleted": depleted,
		"experience_coefficient": source.experience_coefficient,
	})


## 背包或持久化拒绝本周期时停止采矿且不消耗矿源。
## [param token] 调用方传入的 `token` 参数。
## 返回该函数计算、查询或操作得到的结果。
func reject_cycle(token: String) -> bool:
	var reservation: Variant = _pending_cycles.get(token)
	if not reservation is Dictionary:
		return false
	_actions.erase(String(reservation.get("actor_id", "")))
	_pending_cycles.erase(token)
	return true


## 投影指定玩家的当前采矿动作，供客户端持续播放而非猜测动作状态。
## [param actor_id] 服务器会话绑定的玩家标识。
## 返回 active，以及活动时的矿源标识和世界目标坐标；没有动作时明确为 false。
func action_snapshot(actor_id: String) -> Dictionary:
	var action: Dictionary = _actions.get(actor_id, {})
	var source = sources.get(String(action.get("source_id", "")))
	if action.is_empty() or source == null or source.remaining <= 0:
		return {"active": false}
	return {
		"active": true,
		"source_id": source.source_id,
		"target_position": [source.position.x, source.position.y],
	}


## 返回按稳定标识排序的全部活动矿源快照。
## 构建 `snapshot` 对应的只读状态快照。
func snapshot() -> Array[Dictionary]:
	var ids := sources.keys()
	ids.sort()
	var result: Array[Dictionary] = []
	for source_id: String in ids:
		result.append(sources[source_id].snapshot())
	return result


## 执行 `reserve_due_cycles` 对应的模块操作。
func _reserve_due_cycles() -> void:
	var actor_ids := _actions.keys()
	actor_ids.sort()
	for actor_id: String in actor_ids:
		var action: Dictionary = _actions[actor_id]
		if current_tick < int(action["next_cycle_tick"]) or _actor_has_pending_cycle(actor_id):
			continue
		var source = sources.get(String(action["source_id"]))
		if source == null or source.remaining <= 0:
			_actions.erase(actor_id)
			continue
		var quantity := mini(int(_policy["yield_per_cycle"]), source.remaining)
		var token := "%s.mining.%s.cycle.%d" % [map_instance_id, _reward_namespace, _cycle_sequence]
		_cycle_sequence += 1
		var reservation := {
			"token": token,
			"actor_id": actor_id,
			"source_id": source.source_id,
			"item_definition_id": source.item_definition_id,
			"quantity": quantity,
		}
		_pending_cycles[token] = reservation
		_ready_cycles.append(reservation.duplicate(true))


## 执行 `replenish_if_due` 对应的模块操作。
func _replenish_if_due() -> void:
	if _next_replenishment_tick < 0 or current_tick < _next_replenishment_tick:
		return
	var interval := _seconds_to_ticks(float(_policy["replenish_interval_seconds"]))
	var missed_intervals := 1 + floori(float(current_tick - _next_replenishment_tick) / interval)
	_next_replenishment_tick += missed_intervals * interval
	var missing := maxi(0, int(_policy["maximum_sources"]) - sources.size())
	for _index: int in range(missing):
		var result := _spawn_one()
		if not result.is_ok:
			push_warning("Mine replenishment stopped: %s" % result.error_message)
			break


## 执行 `spawn_one` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func _spawn_one() -> DomainResult:
	var selected: Variant = _catalog.mineral_for_spawn(map_id, _spawn_sequence)
	if not selected.is_ok:
		return selected
	var occupied: Array[Vector2] = []
	for source in sources.values():
		occupied.append(source.position)
	var position := RandomWalkableSpawnSampler.sample(
		_navigation,
		hash("%s.mine.%d" % [map_instance_id, _spawn_sequence]),
		occupied,
		float(_policy["minimum_spawn_separation"]),
	)
	if not position.is_finite():
		return DomainResult.failure(&"mining.no_spawn", "map has no walkable mineral spawn")
	var definition: Dictionary = selected.value
	var source_id := "%s.mine.%d" % [map_instance_id, _spawn_sequence]
	var random := RandomNumberGenerator.new()
	random.seed = hash(source_id)
	var source := MineSourceScript.new()
	var configured := source.configure({
		"source_id": source_id,
		"mineral_id": String(definition["id"]),
		"display_name": String(definition["display_name"]),
		"item_definition_id": String(definition["item_definition_id"]),
		"world_presentation_id": String(definition["world_presentation_id"]),
		"map_instance_id": map_instance_id,
		"position": position,
		"capacity": int(_policy["source_capacity"]),
		"remaining": int(_policy["source_capacity"]),
		"required_mining_level": int(definition["required_mining_level"]),
		"experience_coefficient": float(definition["experience_coefficient"]),
		"visual_variant": random.randi_range(0, 6),
		"alpha_byte": random.randi_range(200, 254),
	})
	if not configured.is_ok:
		return configured
	sources[source_id] = source
	_spawn_sequence += 1
	return DomainResult.ok(source)


## 执行 `source_at` 对应的模块操作。
## [param world_position] 调用方传入的 `world_position` 参数。
func _source_at(world_position: Vector2):
	var result = null
	var closest_squared := float(_policy["selection_radius"]) ** 2
	for source in sources.values():
		var distance_squared: float = source.position.distance_squared_to(world_position)
		if distance_squared <= closest_squared:
			closest_squared = distance_squared
			result = source
	return result


## 执行 `actor_has_pending_cycle` 对应的模块操作。
## [param actor_id] 调用方传入的 `actor_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _actor_has_pending_cycle(actor_id: String) -> bool:
	for reservation: Dictionary in _pending_cycles.values():
		if String(reservation.get("actor_id", "")) == actor_id:
			return true
	return false


## 执行 `seconds_to_ticks` 对应的模块操作。
## [param seconds] 调用方传入的 `seconds` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _seconds_to_ticks(seconds: float) -> int:
	return maxi(1, roundi(seconds * float(simulation_hz)))
