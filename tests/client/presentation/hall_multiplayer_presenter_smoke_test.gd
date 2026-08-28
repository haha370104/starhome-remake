extends SceneTree

const PresenterScript := preload(
	"res://scripts/client/presentation/hall_multiplayer_presenter.gd"
)
const AdapterScript := preload("res://scripts/client/network/client_network_adapter.gd")

var assertions := 0
var failures: Array[String] = []


## 延迟启动需要节点生命周期的大厅联机表现层冒烟测试。
func _init() -> void:
	call_deferred("_run")


## 验证本地预测投影、远端角色增删、动作映射和拒绝提示。
## 设计：测试通过离线注入完整权威快照，不依赖真实 ENet 端口或服务器进程。
func _run() -> void:
	var character_catalog_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://assets/characters/character_atlases.json")
	)
	_expect_true(character_catalog_value is Dictionary, "character catalog loads")
	var character_catalog: Dictionary = character_catalog_value

	var world := Node2D.new()
	world.name = "PresentationWorld"
	world.y_sort_enabled = true
	root.add_child(world)
	var local_character := Node2D.new()
	local_character.name = "LocalCharacter"
	local_character.position = Vector2(10.0, 20.0)
	world.add_child(local_character)
	var status_label := Label.new()
	status_label.text = "基础提示"
	root.add_child(status_label)

	var presenter = PresenterScript.new()
	presenter.configure(local_character, world, character_catalog, status_label)
	var local_states: Array[Dictionary] = []
	presenter.local_character_state_applied.connect(
		func(state: Dictionary) -> void: local_states.append(state)
	)
	root.add_child(presenter)
	var start_error: Error = presenter.start({
		"offline_debug_enabled": true,
		"local_entity_id": &"player.me",
		"map_id": &"yian_harbor_hall_floor_1",
		"map_instance_id": "yian_harbor_hall_floor_1.instance.1",
		"initial_position": local_character.position,
		"remote_appearance": "player",
	})
	_expect_equal(start_error, OK, "offline presenter starts")
	_expect_equal(
		presenter.session.network_adapter.connection_state,
		AdapterScript.ConnectionState.CONNECTED,
		"offline session reports connected",
	)

	var intent: Dictionary = presenter.request_move(Vector2(50.0, 20.0))
	_expect_equal(intent.get("input_sequence", 0), 1, "presenter creates local input sequence")
	_expect_true(
		presenter.record_local_predicted_delta(1, Vector2(10.0, 0.0)),
		"presenter records predicted displacement",
	)
	_expect_vector(Vector2(local_states[-1]["position"]), Vector2(20.0, 20.0), "prediction state is published")
	_expect_vector(local_character.position, Vector2(10.0, 20.0), "presenter does not write local character")

	presenter.session.inject_offline_snapshot(_snapshot(1, [
		_entity("player.me", Vector2(12.0, 20.0), 2, "walking", 1, 1),
		_entity("player.other", Vector2(100.0, 80.0), 5, "walking", 0, 1),
	]))
	presenter.session.local_predictor.advance(0.15)
	presenter.session.remote_interpolator.advance(0.1)
	_expect_vector(Vector2(local_states[-1]["position"]), Vector2(12.0, 20.0), "authority reconciliation is published")
	_expect_equal(presenter.remote_character_count(), 1, "remote character is created")
	var remote_character: Node2D = presenter.remote_character(&"player.other")
	_expect_true(remote_character != null, "remote character is indexed by entity ID")
	if remote_character != null:
		_expect_vector(remote_character.position, Vector2(100.0, 80.0), "remote interpolation applies position")
		_expect_equal(remote_character.current_action, "move", "network walking maps to character move")
		_expect_equal(remote_character.current_direction, 5, "network direction maps to character direction")

	presenter.session.inject_offline_snapshot(_snapshot(2, [
		_entity("player.me", Vector2(12.0, 20.0), 2, "idle", 1, 2),
	]))
	_expect_equal(presenter.remote_character_count(), 0, "absent remote entity is removed")
	presenter.session.network_adapter.command_rejected.emit(&"unreachable_target", "目标不可到达")
	_expect_equal(status_label.text, "请求被拒绝：目标不可到达", "rejection reason is visible")

	var requested_transitions: Array[Dictionary] = []
	var joined_maps: Array[StringName] = []
	presenter.map_change_requested.connect(
		func(transition_id: StringName, sequence: int) -> void:
			requested_transitions.append({"transition_id": transition_id, "sequence": sequence})
	)
	presenter.map_joined.connect(
		func(map_id: StringName, _instance_id: String, _spawn: Vector2, _version: int) -> void:
			joined_maps.append(map_id)
	)
	var transition_payload: Dictionary = presenter.request_map_change(&"exit_to_city", 3)
	_expect_equal(transition_payload.get("transition_id", ""), "exit_to_city", "presenter forwards transition ID")
	_expect_equal(requested_transitions.size(), 1, "presenter republishes map change request")
	presenter.session.network_adapter.receive_server_message(_map_joined_message(
		int(transition_payload["input_sequence"])
	))
	_expect_equal(joined_maps, [&"g08"], "presenter republishes committed map join")
	_expect_vector(Vector2(local_states[-1]["position"]), Vector2(420.0, 520.0), "map join publishes reset local position")
	var failed_transitions: Array[StringName] = []
	presenter.map_change_failed.connect(
		func(transition_id: StringName, _code: StringName, _message: String) -> void:
			failed_transitions.append(transition_id)
	)
	var rejected_payload: Dictionary = presenter.request_map_change(&"exit_to_city", 3)
	presenter.session.network_adapter.receive_server_message({
		"type": "command_rejected",
		"result": {
			"ok": false,
			"code": "map_transition.too_far_from_exit",
			"message": "距离出口太远",
			"value": {
				"command_type": "map_transition_intent",
				"transition_sequence": rejected_payload["input_sequence"],
			},
		},
	})
	_expect_equal(failed_transitions, [&"exit_to_city"], "presenter republishes correlated map failure")
	_expect_equal(status_label.text, "切换地图失败：距离出口太远", "map failure has specific status feedback")

	presenter.stop()
	presenter.queue_free()
	world.queue_free()
	status_label.queue_free()
	_finish()


## 执行 `snapshot` 对应的模块操作。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entities] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _snapshot(server_tick: int, entities: Array) -> Dictionary:
	return {
		"server_tick": server_tick,
		"server_time_seconds": float(server_tick) * 0.1,
		"entities": entities,
	}


## 执行 `map_joined_message` 对应的模块操作。
## [param transition_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _map_joined_message(transition_sequence: int) -> Dictionary:
	return {
		"type": "map_joined",
		"result": {
			"ok": true,
			"value": {
				"transition_sequence": transition_sequence,
				"map_joined": {
					"map_id": "g08",
					"map_instance_id": "g08.instance.1",
					"entity_id": "player.me",
					"spawn_position": {"x": 420.0, "y": 520.0},
					"definition_version": 1,
					"server_tick": 10,
				},
				"snapshot": _snapshot(10, [
					_entity("player.me", Vector2(420.0, 520.0), 2, "idle", 0, 10),
				]),
			},
		},
	}


## 执行 `entity` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param acknowledged_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _entity(
	entity_id: String,
	position: Vector2,
	direction: int,
	action_id: String,
	acknowledged_sequence: int,
	server_tick: int,
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"server_tick": server_tick,
		"position": {"x": position.x, "y": position.y},
		"facing_direction": direction,
		"action_id": action_id,
		"speed": 100.0 if action_id == "walking" else 0.0,
		"state_revision": server_tick,
		"acknowledged_input_sequence": acknowledged_sequence,
	}


## 执行 `expect_true` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_true(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)


## 执行 `expect_equal` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_equal(actual: Variant, expected: Variant, label: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (actual=%s expected=%s)" % [label, actual, expected])


## 执行 `expect_vector` 对应的模块操作。
## [param actual] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param expected] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_vector(actual: Vector2, expected: Vector2, label: String) -> void:
	assertions += 1
	if not actual.is_equal_approx(expected):
		failures.append("%s (actual=%s expected=%s)" % [label, actual, expected])


## 输出大厅联机表现层测试汇总，并根据累计失败数量设置退出码。
func _finish() -> void:
	if failures.is_empty():
		print("HALL MULTIPLAYER PRESENTER TESTS PASSED: %d assertions" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print(
		"HALL MULTIPLAYER PRESENTER TESTS FAILED: %d assertions, %d failures"
		% [assertions, failures.size()]
	)
	quit(1)
