extends SceneTree

var failures: Array[String] = []
var checks := 0
var tick := 0

class Avatar extends Node2D:
	## 接受移动控制器的动作投影；本测试不加载美术资源。
	## [param _action] 动作名称。
	## [param _direction] 八方向索引。
	func set_action(_action: String, _direction: int) -> void:
		pass

class Navigation extends RefCounted:
	var route := PackedVector2Array()

	## 测试路线全部位于可行走区域。
	## [param _point] 待检查的世界点。
	## 返回该点是否可通行。
	func is_walkable(_point: Vector2) -> bool:
		return true

	## 为客户端和服务器提供相同的多拐点路线。
	## [param _from] 起点。
	## [param _target] 终点。
	## 返回已准备的路线副本。
	func find_path(_from: Vector2, _target: Vector2) -> PackedVector2Array:
		return route.duplicate()

class MovementSeam extends Node:
	var session: ClientMultiplayerSession

	## 将移动目的地交给实际预测器，隔离测试的网络连接。
	## [param target] 世界目的地。
	## 返回带输入序号的真实移动意图。
	func request_move(target: Vector2) -> Dictionary:
		return session.local_predictor.create_move_intent("test.movement", target)

	## 记录控制器实际行进的位移。
	## [param sequence] 当前移动意图序号。
	## [param displacement] 本帧位移。
	func record_local_predicted_delta(sequence: int, displacement: Vector2) -> void:
		session.local_predictor.apply_predicted_delta(sequence, displacement)

	## 通知预测器本地路线已走完。
	## [param sequence] 已完成的移动意图序号。
	func finish_local_predicted_route(sequence: int) -> void:
		session.local_predictor.finish_local_route(sequence)


## 延迟至节点树可用后运行真实快照、预测器和移动控制器的组合回归。
func _initialize() -> void:
	call_deferred("_run")


## 验证站立快照、装备移速变更、拐点距离预算和旧协议兼容。
func _run() -> void:
	var entity := AuthoritativeEntity.new()
	entity.entity_id = "player.local"
	var session := ClientMultiplayerSession.new()
	root.add_child(session)
	session.set_process(false)
	var avatar := Avatar.new()
	root.add_child(avatar)
	var navigation := Navigation.new()
	var controller := LocalPlayerController.new()
	root.add_child(controller)
	var seam := MovementSeam.new()
	seam.session = session
	root.add_child(seam)
	controller.set_multiplayer_presenter(seam)
	session.local_presentation_state_changed.connect(controller.apply_authoritative_presentation)
	_test_contract(entity)
	for speed: float in [87.0, 143.0, 203.0, 240.0]:
		for frame_delta: float in [1.0 / 20.0, 1.0 / 60.0, 1.0 / 144.0]:
			navigation.route = PackedVector2Array([Vector2.ZERO])
			for index in range(1200):
				var step := Vector2(11, 0) if index % 2 == 0 else Vector2(0, 13)
				navigation.route.append(navigation.route[-1] + step)
				if index % 7 == 0:
					navigation.route.append(navigation.route[-1])
			controller.configure(avatar, navigation, 203.0, Vector2.ZERO)
			session.local_predictor.reset(Vector2.ZERO)
			entity.position = Vector2.ZERO
			entity.stop_moving()
			entity.movement_speed = speed
			_publish(session, entity)
			_expect(entity.snapshot(tick).speed == 0.0, "站立瞬时速度为零")
			_expect(controller.request_move(navigation.route[-1]).ok, "多拐点路线须可开始")
			entity.set_path(navigation.route, navigation.route[-1], controller.active_movement_input_sequence)
			var peak_error := 0.0
			for frame in range(600):
				var delta := 0.17 if frame % 37 == 0 else frame_delta
				controller.advance(delta)
				entity.simulate(delta)
				_publish(session, entity)
				peak_error = maxf(peak_error, controller.position().distance_to(entity.position))
			_expect(peak_error < 0.08, "移速 %.0f / 帧长 %.5f 连续行进不应漂移，实际 %.4fpx" % [speed, frame_delta, peak_error])
	# 装备变化和推进器停机必须同步到未结束的路线，不依赖重新点击。
	var before := controller.position()
	entity.movement_speed = 0.0
	_publish(session, entity)
	controller.advance(1.0)
	_expect(controller.position() == before and controller.has_active_route(), "零移速停止位移且不重建路线")
	var stale := entity.snapshot(tick - 1)
	stale.movement_speed = 240.0
	session._on_world_snapshot({"server_tick": tick - 1, "server_time_seconds": 0.0, "entities": [stale]})
	controller.advance(1.0)
	_expect(controller.position() == before, "旧快照不能覆盖最新移速")
	entity.movement_speed = 87.0
	_publish(session, entity)
	controller.advance(0.5)
	entity.simulate(0.5)
	_expect(controller.position().distance_to(entity.position) < 0.08, "换装后的移速须应用于正在行进的路线")
	controller.advance(1000.0)
	entity.simulate(1000.0)
	_publish(session, entity)
	_expect(not controller.has_active_route() and controller.position() == entity.position, "大帧长穿越多拐点后须正确结束路线")
	_expect(session.local_predictor.pending_intent_count() == 0, "完成路线后须释放预测意图")
	session.local_predictor.reset(Vector2.ZERO)
	_expect(not session.local_predictor.presentation_state().has("movement_speed"), "切图重置不能带入旧地图速度")
	seam.free()
	controller.free()
	avatar.free()
	session.free()
	for failure: String in failures:
		push_error(failure)
	print("LOCAL_MOVEMENT_SPEED_SYNC checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 验证新增移速字段可选，且外部无效数值不能进入预测。
## [param entity] 用于构造实际权威快照的实体。
func _test_contract(entity: AuthoritativeEntity) -> void:
	var payload := entity.snapshot(0)
	var parsed = EntitySnapshot.from_dictionary(payload)
	_expect(parsed.is_ok and parsed.value.movement_speed == 203.0, "站立快照须保留可用速度")
	_expect(parsed.value.to_dictionary() == payload, "带移速快照须完整往返")
	payload.erase("movement_speed")
	parsed = EntitySnapshot.from_dictionary(payload)
	_expect(parsed.is_ok and parsed.value.movement_speed == -1.0
		and parsed.value.to_dictionary() == payload, "旧八字段快照须保持兼容")
	for invalid: Variant in [-1.0, INF, NAN, NetworkProtocol.MAX_SPEED + 1.0, "fast"]:
		payload.movement_speed = invalid
		_expect(not EntitySnapshot.from_dictionary(payload).is_ok, "拒绝不合法的外部移速")


## 通过实际会话解码和表现信号传递服务器移速。
## [param session] 客户端会话。
## [param entity] 权威玩家实体。
func _publish(session: ClientMultiplayerSession, entity: AuthoritativeEntity) -> void:
	tick += 1
	session._on_world_snapshot({"server_tick": tick, "server_time_seconds": tick * 0.05,
		"entities": [entity.snapshot(tick)]})


## 累计断言并保留失败原因。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
