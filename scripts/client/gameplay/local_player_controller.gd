class_name LocalPlayerController
extends Node

signal position_changed(position: Vector2)
signal route_finished
signal route_stopped(message: String)

var path_points := PackedVector2Array()
var path_index := 0
var current_direction := 6
var active_movement_input_sequence := 0

var _character: Node2D
var _navigation: RefCounted
var _destination_marker: CanvasItem
var _multiplayer_presenter: Node
var _movement_speed := 140.0
var _target_position := Vector2.ZERO
var _has_target := false
var _authority_position_held := false
var _held_position := Vector2.ZERO


## 绑定 [param character]、[param navigation]、[param destination_marker] 和可配置的 [param movement_speed]。
## [param initial_position] 是控制器接管角色位置时使用的唯一初始坐标。
## Returns 依赖完整且速度有效时返回 `OK`，否则返回 `ERR_INVALID_PARAMETER`。
## Design: 配置完成后，运行时代码不得绕过本控制器写入本地角色位置或路线状态。
func configure(
	character: Node2D,
	navigation: RefCounted,
	destination_marker: CanvasItem,
	movement_speed: float,
	initial_position: Vector2,
) -> Error:
	if character == null or navigation == null or destination_marker == null or movement_speed <= 0.0:
		return ERR_INVALID_PARAMETER
	_character = character
	_navigation = navigation
	_destination_marker = destination_marker
	_movement_speed = movement_speed
	_write_position(initial_position)
	cancel_route()
	return OK


## 注入 [param presenter] 作为移动意图与本地预测位移的会话端口。
## Design: 控制器不依赖具体网络会话类型，只调用表现接缝的稳定移动 API。
func set_multiplayer_presenter(presenter: Node) -> void:
	_multiplayer_presenter = presenter


## 将后续寻路切换到 [param navigation]；调用方应随后提交出生点或取消旧路线。
func set_navigation(navigation: RefCounted) -> void:
	_navigation = navigation


## 返回当前由控制器管理的角色坐标。
## Returns 未配置时返回零向量。
func position() -> Vector2:
	return _character.position if _character != null else Vector2.ZERO


## 报告玩家是否仍有尚未完成的移动目标与路线段。
## Returns 路线正在由控制器推进时返回 `true`。
func has_active_route() -> bool:
	return _has_target and path_index < path_points.size()


## 解析并请求前往 [param requested_position]，包括最近可达点回退和会话意图创建。
## Returns 成功时包含解析目标和回退标志；失败时包含稳定原因与提示文字。
func request_move(requested_position: Vector2) -> Dictionary:
	if _character == null or _navigation == null:
		return {"ok": false, "code": &"unconfigured", "message": "本地移动尚未初始化"}
	var resolved_position := requested_position
	var used_nearest_walkable := false
	if not _navigation.is_walkable(requested_position):
		resolved_position = _navigation.closest_reachable_position(position(), requested_position)
		used_nearest_walkable = true
		if not resolved_position.is_finite():
			return {"ok": false, "code": &"no_reachable_point", "message": "附近也没有可达点"}
	var route: PackedVector2Array = _navigation.find_path(position(), resolved_position)
	if route.is_empty():
		return {"ok": false, "code": &"path_not_found", "message": "无法找到路径"}
	path_points = route
	path_index = 1 if path_points.size() > 1 else 0
	_target_position = resolved_position
	_has_target = true
	active_movement_input_sequence = 0
	if _multiplayer_presenter != null:
		var movement_intent: Dictionary = _multiplayer_presenter.request_move(resolved_position)
		active_movement_input_sequence = int(movement_intent.get("input_sequence", 0))
	_destination_marker.position = resolved_position
	_destination_marker.visible = true
	_begin_current_segment()
	return {
		"ok": true,
		"resolved_position": resolved_position,
		"used_nearest_walkable": used_nearest_walkable,
	}


## 以 [param delta] 推进当前路线，并把实际位移记录到对应预测输入序号。
func advance(delta: float) -> void:
	if _character == null or path_index >= path_points.size():
		return
	var previous_position := position()
	var waypoint := path_points[path_index]
	var delta_to_target := waypoint - previous_position
	var distance := delta_to_target.length()
	if distance <= _movement_speed * delta:
		_write_position(waypoint)
		path_index += 1
		if path_index >= path_points.size():
			_record_predicted_delta(position() - previous_position)
			_complete_route()
			return
		else:
			_begin_current_segment()
	else:
		var next_position := previous_position + delta_to_target.normalized() * _movement_speed * delta
		if not _navigation.is_walkable(next_position):
			cancel_route("路径被阻挡")
			return
		_write_position(next_position)
	_record_predicted_delta(position() - previous_position)


## 消费会话发布的 [param state]，并执行平滑重算或强制取消路线策略。
## Design: `smooth` 保留业务目标并从新表现位置重算；`forced` 是传送/强纠偏边界，旧路线不可续用。
func apply_authoritative_presentation(state: Dictionary) -> void:
	if _character == null:
		return
	if _authority_position_held:
		_write_position(_held_position)
		return
	if not state.has("position"):
		return
	_write_position(Vector2(state["position"]))
	var correction_mode := StringName(state.get("correction_mode", &"none"))
	if correction_mode == &"forced":
		cancel_route()
		return
	if correction_mode == &"smooth" and _has_target:
		_replan_to_active_target()


## 暂停权威位置投影并取消路线，使旧地图画面停留在当前脚点等待资源提交。
func hold_position_for_map_commit() -> void:
	_authority_position_held = true
	_held_position = position()
	cancel_route()


## 采用 [param navigation] 和权威 [param spawn_position] 原子进入新地图并恢复位置投影。
func commit_map_position(navigation: RefCounted, spawn_position: Vector2) -> void:
	_navigation = navigation
	_authority_position_held = false
	cancel_route()
	_write_position(spawn_position)


## 在同图传送或初始化时采用 [param new_position]；[param cancel_active_route] 控制是否终止旧路线。
func set_position(new_position: Vector2, cancel_active_route: bool = true) -> void:
	_authority_position_held = false
	if cancel_active_route:
		cancel_route()
	_write_position(new_position)


## 取消当前目标、路径和预测输入序号；非空 [param message] 会发布停步原因。
func cancel_route(message: String = "") -> void:
	path_points = PackedVector2Array()
	path_index = 0
	active_movement_input_sequence = 0
	_has_target = false
	if _destination_marker != null:
		_destination_marker.visible = false
	_set_character_action(&"stand")
	if not message.is_empty():
		route_stopped.emit(message)


## 将当前角色切换到 [param action]，方向始终来自控制器当前路线段。
func set_character_action(action: StringName) -> void:
	_set_character_action(action)


## 重新计算当前路线段方向；仅供旧诊断入口在直接设置路径后触发刷新。
func refresh_route_direction() -> void:
	_begin_current_segment()


## 从当前位置到既有业务目标重算路线；失败时停止并发布可读原因。
func _replan_to_active_target() -> void:
	var route: PackedVector2Array = _navigation.find_path(position(), _target_position)
	if route.is_empty():
		cancel_route("权威校正后无法继续前往原目标")
		return
	path_points = route
	path_index = 1 if path_points.size() > 1 else 0
	_begin_current_segment()


## 更新当前路线段方向，并以八方向素材播放行走动作。
func _begin_current_segment() -> void:
	if path_index >= path_points.size() or _character == null:
		return
	var segment_motion := path_points[path_index] - position()
	if segment_motion.length_squared() <= 0.01:
		return
	current_direction = direction_index(segment_motion)
	_set_character_action(&"move")


## 完成路线、隐藏目标并通知场景层检查地图出口。
func _complete_route() -> void:
	path_points = PackedVector2Array()
	path_index = 0
	active_movement_input_sequence = 0
	_has_target = false
	_destination_marker.visible = false
	_set_character_action(&"stand")
	route_finished.emit()


## 把 [param displacement] 记录到当前活动输入；零位移和无序号时不产生调用。
func _record_predicted_delta(displacement: Vector2) -> void:
	if (
		_multiplayer_presenter != null
		and active_movement_input_sequence > 0
		and not displacement.is_zero_approx()
	):
		_multiplayer_presenter.record_local_predicted_delta(
			active_movement_input_sequence,
			displacement,
		)


## 通过唯一写入口把 [param new_position] 投影到角色并通知摄像机/HUD。
func _write_position(new_position: Vector2) -> void:
	_character.position = new_position
	position_changed.emit(new_position)


## 在当前 [param current_direction] 上播放业务动作 [param action]。
func _set_character_action(action: StringName) -> void:
	if _character != null:
		_character.set_action(String(action), current_direction)


## 将连续方向向量 [param motion] 量化为荣耀素材的八方向索引。
## Returns `E, NE, N, NW, W, SW, S, SE` 对应的 `0..7`。
static func direction_index(motion: Vector2) -> int:
	return posmod(-roundi(motion.angle() / (PI / 4.0)), 8)
