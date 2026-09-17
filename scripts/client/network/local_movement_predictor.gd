class_name LocalMovementPredictor
extends RefCounted

const MoveIntentContract = preload("res://scripts/network/contracts/move_intent.gd")

signal move_intent_created(payload: Dictionary)
signal presentation_state_changed(state: Dictionary)
signal correction_started(mode: StringName, error_distance: float)
signal correction_finished(mode: StringName)
signal stale_snapshot_rejected(server_tick: int)

const CORRECTION_NONE: StringName = &"none"
const CORRECTION_SMOOTH: StringName = &"smooth"
const CORRECTION_FORCED: StringName = &"forced"

var smooth_threshold_px := 24.0
var force_threshold_px := 96.0
var smooth_duration_seconds := 0.15

var predicted_position := Vector2.ZERO
var authoritative_position := Vector2.ZERO
var next_input_sequence := 1
var last_acknowledged_sequence := 0
var last_server_tick := -1
var correction_mode: StringName = CORRECTION_NONE

var _pending_intents: Array[Dictionary] = []
var _active_intent_sequence := 0
var _active_route_finished := false
var _correction_origin := Vector2.ZERO
var _correction_target := Vector2.ZERO
var _correction_elapsed := 0.0
var _correction_duration := 0.0
var _movement_speed := -1.0


## 配置并初始化 `configure` 对应的模块状态。
## [param smooth_threshold] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param force_threshold] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param smooth_duration] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func configure(
	smooth_threshold: float = 24.0,
	force_threshold: float = 96.0,
	smooth_duration: float = 0.15,
) -> void:
	smooth_threshold_px = maxf(0.0, smooth_threshold)
	force_threshold_px = maxf(smooth_threshold_px, force_threshold)
	smooth_duration_seconds = maxf(0.001, smooth_duration)


## 执行 `reset` 对应的模块操作。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param starting_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param emit_change] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func reset(position: Vector2, starting_sequence: int = 1, emit_change: bool = true) -> void:
	predicted_position = position
	authoritative_position = position
	next_input_sequence = maxi(1, starting_sequence)
	last_acknowledged_sequence = next_input_sequence - 1
	last_server_tick = -1
	_movement_speed = -1.0
	_pending_intents.clear()
	_active_intent_sequence = 0
	_active_route_finished = false
	_clear_correction()
	if emit_change:
		_emit_presentation_state()


## 创建 `create_move_intent` 对应的模块状态。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_world_point] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func create_move_intent(map_instance_id: String, requested_world_point: Vector2) -> Dictionary:
	var sequence := next_input_sequence
	next_input_sequence += 1
	var intent: Dictionary = {
		"input_sequence": sequence,
		"map_instance_id": map_instance_id,
		"requested_world_point": requested_world_point,
		"predicted_delta": Vector2.ZERO,
	}
	_pending_intents.append(intent)
	_active_intent_sequence = sequence
	_active_route_finished = false
	var payload := _intent_payload(intent)
	move_intent_created.emit(payload.duplicate(true))
	return payload


## 设置或恢复 `apply_predicted_delta` 对应的模块状态。
## [param input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param displacement] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func apply_predicted_delta(input_sequence: int, displacement: Vector2) -> bool:
	for index in range(_pending_intents.size() - 1, -1, -1):
		var intent := _pending_intents[index]
		if int(intent["input_sequence"]) != input_sequence:
			continue
		intent["predicted_delta"] = Vector2(intent["predicted_delta"]) + displacement
		_pending_intents[index] = intent
		predicted_position += displacement
		if correction_mode == CORRECTION_SMOOTH:
			# New prediction continues while reconciliation is blending; move both ends
			# of the correction so fresh input does not resurrect the old error.
			_correction_origin += displacement
			_correction_target += displacement
		_emit_presentation_state()
		return true
	return false


## 标记指定目的地路线已在客户端表现层走完，但继续保留其预测终点直至服务器也结束移动。
## [param input_sequence] 已完成路线对应的移动输入序号。
## 返回序号是否仍是当前活动路线；过期路线不会改变预测状态。
## 设计：服务端确认序号只表示“已接收目的地”，不能被误用为“已追上客户端位置”。
func finish_local_route(input_sequence: int) -> bool:
	if input_sequence <= 0 or input_sequence != _active_intent_sequence:
		return false
	_active_route_finished = true
	return true


## 设置或恢复 `apply_authoritative_snapshot` 对应的模块状态。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param acknowledged_input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_action] 权威实体当前是仍在执行路线还是已经停下。
## [param server_movement_speed] 已校验的权威可用移速；-1 表示旧快照未提供。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func apply_authoritative_snapshot(
	server_tick: int,
	acknowledged_input_sequence: int,
	server_position: Vector2,
	server_action: StringName = &"idle",
	server_movement_speed: float = -1.0,
) -> bool:
	if server_tick <= last_server_tick:
		stale_snapshot_rejected.emit(server_tick)
		return false
	last_server_tick = server_tick
	if is_finite(server_movement_speed) and server_movement_speed >= 0.0:
		_movement_speed = server_movement_speed
	authoritative_position = server_position
	last_acknowledged_sequence = maxi(last_acknowledged_sequence, acknowledged_input_sequence)
	_mark_acknowledged_intents(last_acknowledged_sequence)

	var active_intent := _active_intent()
	if not active_intent.is_empty() and not bool(active_intent.get("acknowledged", false)):
		# 可靠目的地命令尚在传输途中时，快照必然描述发送前的旧路线。此时用旧
		# 权威坐标校正会让快速连续点地的玩家每次点击都顿一下。
		_discard_acknowledged_intents(last_acknowledged_sequence, true)
		_clear_correction()
		_emit_presentation_state()
		return true
	if not active_intent.is_empty() and bool(active_intent.get("acknowledged", false)):
		var requested_point := Vector2(active_intent["requested_world_point"])
		var server_reached_requested_point := server_position.distance_to(requested_point) \
			<= smooth_threshold_px
		# 目的地协议只确认一次命令，服务器会在随后多个 tick 内逐步执行路线。
		# 这段时间客户端持续播放同一路线，不把正常的网络领先量当成位置误差。
		if server_action == &"walking" or (
			not _active_route_finished and server_reached_requested_point
		):
			_discard_acknowledged_intents(last_acknowledged_sequence, true)
			_clear_correction()
			_emit_presentation_state()
			return true
		# 双方均结束路线后，才把服务器终点作为最终校正目标。服务器若提前停在
		# 另一处，也会进入同一分支纠偏，避免永久保留错误的本地路线。
		_active_intent_sequence = 0
		_active_route_finished = false
	_discard_acknowledged_intents(last_acknowledged_sequence)

	var reconciliation_target := authoritative_position
	for intent in _pending_intents:
		reconciliation_target += Vector2(intent["predicted_delta"])
	var error_distance := predicted_position.distance_to(reconciliation_target)
	if error_distance <= 0.001:
		predicted_position = reconciliation_target
		_clear_correction()
		_emit_presentation_state()
		return true
	if error_distance >= force_threshold_px:
		correction_mode = CORRECTION_FORCED
		correction_started.emit(correction_mode, error_distance)
		predicted_position = reconciliation_target
		_emit_presentation_state()
		correction_finished.emit(correction_mode)
		_clear_correction()
		return true

	correction_mode = CORRECTION_SMOOTH
	_correction_origin = predicted_position
	_correction_target = reconciliation_target
	_correction_elapsed = 0.0
	# Tiny errors use the full blend window. Larger-but-not-forced errors converge sooner.
	var threshold_span := maxf(0.001, force_threshold_px - smooth_threshold_px)
	var normalized_error := clampf(
		(error_distance - smooth_threshold_px) / threshold_span,
		0.0,
		1.0,
	)
	_correction_duration = lerpf(smooth_duration_seconds, 0.04, normalized_error)
	correction_started.emit(correction_mode, error_distance)
	return true


## 执行 `advance` 对应的模块操作。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func advance(delta: float) -> void:
	if correction_mode != CORRECTION_SMOOTH:
		return
	_correction_elapsed += maxf(0.0, delta)
	var weight := clampf(_correction_elapsed / _correction_duration, 0.0, 1.0)
	predicted_position = _correction_origin.lerp(_correction_target, weight)
	_emit_presentation_state()
	if weight >= 1.0:
		correction_finished.emit(correction_mode)
		_clear_correction()


## 执行 `pending_intent_count` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func pending_intent_count() -> int:
	return _pending_intents.size()


## 执行 `presentation_state` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func presentation_state() -> Dictionary:
	var state := {
		"position": predicted_position,
		"authoritative_position": authoritative_position,
		"correction_mode": correction_mode,
		"last_server_tick": last_server_tick,
		"last_acknowledged_sequence": last_acknowledged_sequence,
		"pending_intent_count": _pending_intents.size(),
		"active_intent_sequence": _active_intent_sequence,
		"active_route_finished": _active_route_finished,
	}
	if _movement_speed >= 0.0:
		state["movement_speed"] = _movement_speed
	return state


## 执行 `discard_acknowledged_intents` 对应的模块操作。
## [param ack_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param preserve_active] 是否保留已确认但仍在本地连续播放的活动路线。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _discard_acknowledged_intents(ack_sequence: int, preserve_active: bool = false) -> void:
	var remaining: Array[Dictionary] = []
	for intent in _pending_intents:
		var sequence := int(intent["input_sequence"])
		if sequence > ack_sequence or (preserve_active and sequence == _active_intent_sequence):
			remaining.append(intent)
	_pending_intents = remaining


## 把服务器累计确认序号投影到本地意图，但不立即丢弃仍在播放的活动路线。
## [param ack_sequence] 服务器已接收的最大移动输入序号。
## 设计：确认状态与路线完成状态分离，是目的地式移动协议保持平滑的关键。
func _mark_acknowledged_intents(ack_sequence: int) -> void:
	for index in range(_pending_intents.size()):
		var intent := _pending_intents[index]
		intent["acknowledged"] = int(intent["input_sequence"]) <= ack_sequence
		_pending_intents[index] = intent


## 查询当前仍负责本地连续表现的移动意图。
## 返回活动意图副本；不存在时返回空字典。
func _active_intent() -> Dictionary:
	if _active_intent_sequence <= 0:
		return {}
	for intent in _pending_intents:
		if int(intent["input_sequence"]) == _active_intent_sequence:
			return intent
	return {}


## 执行 `intent_payload` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _intent_payload(intent: Dictionary) -> Dictionary:
	var contract := MoveIntentContract.new(
		String(intent["map_instance_id"]),
		Vector2(intent["requested_world_point"]),
		int(intent["input_sequence"]),
	)
	return contract.to_dictionary()


## 发布 `emit_presentation_state` 对应的模块状态。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _emit_presentation_state() -> void:
	presentation_state_changed.emit(presentation_state())


## 移除并清理 `clear_correction` 对应的模块状态。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _clear_correction() -> void:
	correction_mode = CORRECTION_NONE
	_correction_elapsed = 0.0
	_correction_duration = 0.0
