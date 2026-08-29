extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")

var failures: PackedStringArray = []
var assertions := 0
var transition_events: Array[String] = []


## 延迟运行完整场景切图测试，等待大厅、HUD 和离线会话完成 `_ready`。
func _initialize() -> void:
	call_deferred("_run")


## 驱动真实大厅出口与城市西北门，验证 RoomSvr1→City1Svr→D04 原子表现切换。
func _run() -> void:
	var hall: Node2D = MainHallScene.instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	var server_config := ServerConfigScript.new()
	server_config.network_enabled = false
	server_config.persistence_enabled = false
	hall.multiplayer_presenter.session.network_adapter.configure_in_process_server(server_config)
	_expect(
		hall.multiplayer_presenter.session.connect_to_server("in-process", 0) == OK,
		"场景测试应成功启动隔离的进程内权威服务器",
	)
	await _wait_for_session(hall)
	hall.multiplayer_presenter.session.map_joined.connect(
		func(map_id: StringName, _instance_id: String, _position: Vector2, _version: int) -> void:
			transition_events.append("joined:%s" % map_id)
	)
	hall.multiplayer_presenter.session.map_change_failed.connect(
		func(transition_id: StringName, code: StringName, message: String) -> void:
			transition_events.append("failed:%s:%s:%s" % [transition_id, code, message])
	)
	_expect(hall.map_definition.map_id == &"yian_harbor_hall_floor_1", "测试必须从荣耀版大厅开始")
	var initial_sequence: int = hall.multiplayer_presenter.session.local_predictor.next_input_sequence
	hall.pending_map_transition = {"transition_id": &"exit_to_city"}
	hall.call("_move_to", Vector2(900, 1300))
	_expect(
		hall.multiplayer_presenter.session.local_predictor.next_input_sequence == initial_sequence,
		"预载或等待切图期间不得继续提交旧地图移动",
	)
	hall.call(
		"_on_authoritative_map_change_failed",
		&"exit_to_city",
		&"map_transition.too_far_from_exit",
		"距离出口太远",
	)
	_expect(not hall.call("_world_input_locked"), "权威拒绝后应恢复旧地图输入")

	# Reconnect may join a map whose resources were not preloaded. The old scene must
	# hold its player position and stop its route until the authoritative bundle commits.
	var held_position: Vector2 = hall.player.position
	hall.path_points = PackedVector2Array([held_position, held_position + Vector2(100, 0)])
	hall.path_index = 1
	hall.active_movement_input_sequence = 7
	hall.call(
		"_hold_old_map_for_authoritative_join",
		&"yian_harbor_city",
		"yian_harbor_city.instance.review",
		Vector2(1399, 954),
	)
	_expect(hall.path_points.is_empty(), "异步权威切图必须立即终止旧地图路径")
	_expect(hall.active_movement_input_sequence == 0, "异步权威切图必须停止记录旧地图预测输入")
	hall.player.position = Vector2(1399, 954)
	hall.call("_on_multiplayer_local_character_state_applied", {})
	_expect(hall.player.position == held_position, "资源提交前旧地图必须保持原角色位置")
	hall.pending_authoritative_join.clear()

	_place_authoritative_player(hall, Vector2(480, 370))
	hall.call("_try_begin_nearby_map_transition")
	await _wait_for_map(hall, &"yian_harbor_city")
	_expect(hall.map_definition.map_id == &"yian_harbor_city", "大厅出口必须进入真实 City1Svr 业务图")
	_expect(hall.player.position == Vector2(1399, 954), "城市入口0必须采用配置化权威落点")
	_expect(hall.navigation.grid_size == Vector2i(71, 560), "城市必须切换到自己的荣耀导航")
	_expect(hall.map_scene_nodes.size() == 919, "城市必须提交官网惰性资源恢复后的完整语义遮挡层")
	_expect(hall.npc_instances.is_empty(), "大厅 NPC 不得泄漏到城市")
	_expect(hall.hud.minimap_dock.map_name_label.text == "易安港城区", "HUD 必须原子更新城市名")

	_place_authoritative_player(hall, Vector2(78, 170))
	hall.call("_try_begin_nearby_map_transition")
	await _wait_for_map(hall, &"d04_field_zone")
	_expect(hall.map_definition.map_id == &"d04_field_zone", "城市西北门必须进入 D04")
	_expect(hall.player.position == Vector2(1290, 2562), "D04入口1必须采用配置化权威落点")
	_expect(hall.navigation.grid_size == Vector2i(101, 800), "D04必须切换到自己的荣耀导航")
	_expect(hall.map_scene_nodes.size() == 117, "D04必须提交官网惰性资源恢复后的荣耀语义遮挡层")
	_expect(hall.hud.minimap_dock.map_name_label.text == "D04区", "HUD 必须原子更新 D04 名称")
	_expect(hall.multiplayer_presenter.session.current_map_id == &"d04_field_zone", "离线调试会话也必须同步当前业务地图")
	var final_sequence: int = hall.multiplayer_presenter.session.local_predictor.next_input_sequence
	hall.call("_handle_map_commit_failure", "测试不可恢复提交失败")
	hall.call("_move_to", Vector2(1200, 2500))
	_expect(hall.call("_world_input_locked"), "权威已切图但客户端提交失败后必须锁住旧画面输入")
	_expect(
		hall.multiplayer_presenter.session.local_predictor.next_input_sequence == final_sequence,
		"不可恢复提交失败后不得再创建地图移动输入",
	)

	if failures.is_empty():
		print("MAP_TRANSITION_SCENE_SMOKE_OK (%d assertions)" % assertions)
		hall.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	hall.free()
	quit(1)


## 执行 `wait_for_map` 对应的模块操作。
## [param hall] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected_map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _wait_for_map(hall: Node2D, expected_map_id: StringName) -> void:
	for _frame in range(600):
		if hall.map_definition.map_id == expected_map_id:
			return
		await process_frame
	_fail(
		"等待地图提交超时：%s；提示=%s；待提交=%s；待权威提交=%s；预载包=%s；会话待确认=%s；事件=%s"
		% [
			expected_map_id,
			hall.hint_label.text,
			hall.pending_map_transition,
			hall.pending_authoritative_join,
			hall.pending_map_bundle.keys(),
			hall.multiplayer_presenter.session._pending_map_change,
			transition_events,
		]
	)


## 等待进程内传输完成与正式权威服务器相同的异步握手。
## [param hall] 正在启动本地权威会话的大厅场景。
func _wait_for_session(hall: Node2D) -> void:
	for _frame in range(120):
		if hall.multiplayer_presenter.session.network_adapter.session_ready:
			return
		await process_frame
	_fail("等待进程内权威会话握手超时")


## 将场景测试的客户端与权威实体同时摆放到待测出口，避免用数秒寻路污染切图断言。
## [param hall] 持有进程内传输和玩家表现的大厅场景。
## [param position] 本次切图需要测试的出口接近点。
## 设计：该辅助函数只准备测试前置状态；切图请求、校验、落点和回包仍完整经过正式服务器。
func _place_authoritative_player(hall: Node2D, position: Vector2) -> void:
	var transport: Node = hall.multiplayer_presenter.session.network_adapter._transport_endpoint
	var server: AuthoritativeServer = transport.authoritative_server
	var session: ServerSession = server.sessions.session_for_peer(transport.LOCAL_PEER_ID)
	var instance: AuthoritativeMapInstance = server.map_registry.instance_by_id(session.map_instance_id)
	var entity: AuthoritativeEntity = instance.entities[session.entity_id]
	entity.position = position
	entity.set_path(PackedVector2Array([position]), position, entity.last_input_sequence)
	hall.multiplayer_presenter.session.initialize_local_player(position)
	hall.local_player_controller.set_position(position)


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 执行 `fail` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _fail(message: String) -> void:
	failures.append(message)
