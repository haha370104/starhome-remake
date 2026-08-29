extends SceneTree

const Adapter = preload("res://scripts/client/network/client_network_adapter.gd")
const MoveIntentContract = preload("res://scripts/network/contracts/move_intent.gd")
const Predictor = preload("res://scripts/client/network/local_movement_predictor.gd")
const Interpolator = preload("res://scripts/client/network/remote_entity_interpolator.gd")
const Session = preload("res://scripts/client/network/client_multiplayer_session.gd")
const MapTransitionIntentContract = preload("res://scripts/network/contracts/map_transition_intent.gd")
const ServerConfigScript = preload("res://scripts/server/server_config.gd")

var assertions := 0
var failures: Array[String] = []
var session_database_path := ""


## 启动客户端网络冒烟用例，并将需要 SceneTree 的会话集成测试延迟执行。
## 设计：纯逻辑用例同步运行，节点生命周期用例跨帧运行后再统一结束进程。
func _init() -> void:
	_test_offline_adapter()
	_test_local_prediction_and_reconciliation()
	_test_destination_prediction_does_not_rewind_on_ack()
	_test_remote_interpolation()
	call_deferred("_test_session_integration")


## 验证进程内模式在显式连接前不会吞掉或伪装已发送命令。
func _test_offline_adapter() -> void:
	var adapter := Adapter.new()
	root.add_child(adapter)
	adapter.configure_offline_debug(true)
	_expect_equal(adapter.connection_state, Adapter.ConnectionState.DISCONNECTED,
		"进程内传输也必须经历显式连接和会话握手")
	var sent: Array[Dictionary] = []
	adapter.move_intent_sent.connect(func(payload: Dictionary) -> void: sent.append(payload))
	_expect_equal(
		adapter.send_move_intent({"input_sequence": 1}),
		ERR_UNCONFIGURED,
		"未连接的进程内传输必须拒绝移动意图",
	)
	_expect_equal(sent.size(), 0, "被拒绝的命令不得伪造发送观察事件")
	adapter.disconnect_from_server()
	_expect_equal(adapter.connection_state, Adapter.ConnectionState.DISCONNECTED, "disconnect state")
	adapter.queue_free()


## 验证本地输入序列、预测位置、权威确认与误差阈值校正逻辑。
## 设计：该用例锁定客户端预测与服务器权威快照之间的边界行为。
func _test_local_prediction_and_reconciliation() -> void:
	var predictor := Predictor.new()
	predictor.reset(Vector2(10.0, 20.0))
	var first := predictor.create_move_intent("hall.instance.1", Vector2(100.0, 20.0))
	var second := predictor.create_move_intent("hall.instance.1", Vector2(200.0, 20.0))
	_expect_equal(first["input_sequence"], 1, "first sequence")
	_expect_equal(second["input_sequence"], 2, "second sequence")
	_expect_equal(first["map_instance_id"], "hall.instance.1", "map instance is in wire payload")
	_expect_true(first.has("requested_world_point"), "contract world point field is used")
	_expect_false(first.has("target_world_point"), "private target field is absent")
	var restored_intent = MoveIntentContract.from_dictionary(first)
	_expect_true(restored_intent.is_ok, "client payload satisfies MoveIntent contract")
	_expect_equal(restored_intent.value.to_dictionary(), first, "client payload contract round trips")
	_expect_true(predictor.apply_predicted_delta(1, Vector2(30.0, 0.0)), "first delta accepted")
	_expect_true(predictor.apply_predicted_delta(2, Vector2(10.0, 0.0)), "second delta accepted")
	_expect_vector(predictor.predicted_position, Vector2(50.0, 20.0), "prediction advances")
	_expect_equal(predictor.pending_intent_count(), 2, "two pending")

	# 确认旧目的地时，新目的地仍在可靠传输途中；旧快照不得回拽新路线表现。
	_expect_true(predictor.apply_authoritative_snapshot(10, 1, Vector2(35.0, 20.0)), "fresh snapshot accepted")
	_expect_equal(predictor.pending_intent_count(), 1, "acked input discarded")
	_expect_equal(predictor.correction_mode, Predictor.CORRECTION_NONE, "in-flight destination does not rewind")
	predictor.advance(0.075)
	_expect_vector(predictor.predicted_position, Vector2(50.0, 20.0), "prediction remains continuous")
	predictor.advance(0.075)
	_expect_vector(predictor.predicted_position, Vector2(50.0, 20.0), "old snapshot never becomes a delayed correction")
	_expect_equal(predictor.correction_mode, Predictor.CORRECTION_NONE, "no deferred correction remains")

	_expect_false(predictor.apply_authoritative_snapshot(10, 2, Vector2.ZERO), "old tick rejected")
	_expect_vector(predictor.predicted_position, Vector2(50.0, 20.0), "stale snapshot cannot mutate")
	_expect_true(predictor.apply_authoritative_snapshot(11, 2, Vector2(300.0, 20.0)), "forced snapshot accepted")
	_expect_vector(predictor.predicted_position, Vector2(300.0, 20.0), "96px error snaps")
	_expect_equal(predictor.pending_intent_count(), 0, "all intents acknowledged")
	_expect_false(predictor.apply_predicted_delta(99, Vector2.ONE), "unknown sequence rejected")

	var boundary_predictor := Predictor.new()
	boundary_predictor.reset(Vector2.ZERO)
	_expect_true(boundary_predictor.apply_authoritative_snapshot(1, 0, Vector2(24.0, 0.0)), "24px snapshot accepted")
	_expect_equal(boundary_predictor.correction_mode, Predictor.CORRECTION_SMOOTH, "24px uses smooth correction")
	var continued_intent := boundary_predictor.create_move_intent("hall.instance.1", Vector2(50.0, 0.0))
	_expect_true(
		boundary_predictor.apply_predicted_delta(int(continued_intent["input_sequence"]), Vector2(5.0, 0.0)),
		"prediction continues during smoothing",
	)
	boundary_predictor.advance(0.15)
	_expect_vector(boundary_predictor.predicted_position, Vector2(29.0, 0.0), "fresh input is retained after smoothing")
	boundary_predictor.reset(Vector2.ZERO)
	_expect_true(boundary_predictor.apply_authoritative_snapshot(1, 0, Vector2(96.0, 0.0)), "96px snapshot accepted")
	_expect_vector(boundary_predictor.predicted_position, Vector2(96.0, 0.0), "96px forces immediate correction")


## 验证目的地命令被服务器确认后，本地路线仍可逐帧连续前进且不会被中途快照回拽。
## 设计：约 200ms 的正常预测领先量应在双方抵达同一终点后自然收敛，而非逐帧插值抵消。
func _test_destination_prediction_does_not_rewind_on_ack() -> void:
	var predictor := Predictor.new()
	predictor.reset(Vector2.ZERO)
	var intent := predictor.create_move_intent("hall.instance.1", Vector2(50.0, 0.0))
	var sequence := int(intent["input_sequence"])
	_expect_true(predictor.apply_predicted_delta(sequence, Vector2(40.0, 0.0)),
		"确认前应接受约 200ms 的本地领先位移")
	_expect_true(predictor.apply_authoritative_snapshot(
		1, sequence, Vector2(10.0, 0.0), &"walking"
	), "服务器确认目的地并开始行走")
	_expect_vector(predictor.predicted_position, Vector2(40.0, 0.0),
		"确认只代表收到命令，不得把表现位置拉回服务器旧坐标")
	_expect_equal(predictor.correction_mode, Predictor.CORRECTION_NONE,
		"正常网络领先期间不得启动平滑回拽")
	_expect_true(predictor.apply_predicted_delta(sequence, Vector2(10.0, 0.0)),
		"路线确认后仍应继续记录本地逐帧位移")
	_expect_vector(predictor.predicted_position, Vector2(50.0, 0.0),
		"本地表现应连续抵达目标")
	_expect_true(predictor.finish_local_route(sequence), "本地路线应进入等待权威收敛阶段")
	_expect_true(predictor.apply_authoritative_snapshot(
		2, sequence, Vector2(35.0, 0.0), &"walking"
	), "服务器尚在追赶终点")
	_expect_vector(predictor.predicted_position, Vector2(50.0, 0.0),
		"本地抵达后不得因服务器仍在路上而倒退")
	_expect_true(predictor.apply_authoritative_snapshot(
		3, sequence, Vector2(50.0, 0.0), &"idle"
	), "双方抵达同一终点后完成权威收敛")
	_expect_vector(predictor.predicted_position, Vector2(50.0, 0.0),
		"最终权威收敛不应产生可见跳动")
	_expect_equal(predictor.pending_intent_count(), 0, "完成的目的地意图应被释放")

	var rapid_predictor := Predictor.new()
	rapid_predictor.reset(Vector2.ZERO)
	var old_intent := rapid_predictor.create_move_intent("hall.instance.1", Vector2(80.0, 0.0))
	rapid_predictor.apply_predicted_delta(int(old_intent["input_sequence"]), Vector2(20.0, 0.0))
	var replacement := rapid_predictor.create_move_intent("hall.instance.1", Vector2(80.0, 40.0))
	rapid_predictor.apply_predicted_delta(int(replacement["input_sequence"]), Vector2(5.0, 5.0))
	_expect_true(rapid_predictor.apply_authoritative_snapshot(
		1, int(old_intent["input_sequence"]), Vector2(8.0, 0.0), &"walking"
	), "新目的地仍在传输时可能先收到旧路线快照")
	_expect_vector(rapid_predictor.predicted_position, Vector2(25.0, 5.0),
		"快速连续点地期间不得被旧路线快照回拽")
	_expect_equal(rapid_predictor.correction_mode, Predictor.CORRECTION_NONE,
		"等待新命令确认期间不应产生插值顿挫")


## 验证远端实体在 10 Hz 快照间的插值、状态投影和移除流程。
func _test_remote_interpolation() -> void:
	var interpolator := Interpolator.new()
	interpolator.configure(0.1)
	_expect_true(interpolator.push_snapshot(10, 1.0, [_entity("remote.one", 0.0, 0)]), "first remote snapshot")
	_expect_true(interpolator.push_snapshot(11, 1.1, [_entity("remote.one", 10.0, 2)]), "second remote snapshot")
	var midpoint := interpolator.sample_entity_at(&"remote.one", 1.05)
	_expect_vector(midpoint["position"], Vector2(5.0, 0.0), "10Hz midpoint interpolation")
	_expect_equal(midpoint["facing_direction"], 2, "latest facing direction projects")
	_expect_equal(midpoint["action_id"], &"walking", "action ID projects without assets")
	_expect_false(interpolator.push_snapshot(11, 1.1, [_entity("remote.one", 99.0, 0)]), "duplicate tick rejected")
	_expect_false(interpolator.push_snapshot(9, 0.9, [_entity("remote.one", 99.0, 0)]), "old tick rejected")
	_expect_equal(interpolator.tracked_entity_count(), 1, "one remote tracked")
	interpolator.remove_entity(&"remote.one")
	_expect_equal(interpolator.tracked_entity_count(), 0, "remote removal")


## 验证离线会话节点对本地预测、远端快照和生命周期信号的集成。
## 设计：该异步夹具等待 SceneTree 帧，以覆盖节点就绪与信号回调时序。
func _test_session_integration() -> void:
	var session := Session.new()
	session.offline_debug_enabled = true
	root.add_child(session)
	await process_frame
	session_database_path = "res://client_network_session_%d.tmp" % Time.get_ticks_usec()
	var local_server_config := ServerConfigScript.new()
	local_server_config.network_enabled = false
	local_server_config.player_state_store_path = session_database_path
	_expect_true(session.network_adapter.configure_in_process_server(local_server_config),
		"测试应在连接前注入临时正式服务器存档")
	var panel_bundles: Array[Dictionary] = []
	session.player_panel_bundle_received.connect(
		func(bundle: Dictionary) -> void: panel_bundles.append(bundle.duplicate(true))
	)
	_expect_equal(session.connect_to_server("ignored", 0), OK, "进程内会话应启动正式服务器")
	for _frame in range(6):
		await process_frame
	_expect_equal(session.network_adapter.connection_state, Adapter.ConnectionState.CONNECTED,
		"进程内会话应完成异步连接")
	_expect_true(session.network_adapter.session_ready, "进程内会话必须完成正式握手")
	_expect_true(not session.current_map_instance_id.is_empty(), "正式握手必须分配地图实例")
	_expect_equal(panel_bundles.size(), 1, "握手后应自动查询正式服务器面板聚合")
	var sent_payloads: Array[Dictionary] = []
	session.network_adapter.move_intent_sent.connect(
		func(payload: Dictionary) -> void: sent_payloads.append(payload)
	)
	var start_position: Vector2 = session.local_presentation_state()["position"]
	var intent := session.request_move(start_position + Vector2(24.0, 0.0))
	_expect_equal(intent["input_sequence"], 1, "session creates sequenced intent")
	_expect_equal(intent["map_instance_id"], session.current_map_instance_id,
		"session uses server-assigned map instance")
	_expect_equal(sent_payloads.size(), 1, "session sends one contract payload")
	_expect_true(MoveIntentContract.from_dictionary(sent_payloads[0]).is_ok, "sent payload round trips through contract")
	_expect_true(session.record_local_predicted_delta(1, Vector2(20.0, 0.0)), "session records prediction")
	var injected_tick := int(session.local_presentation_state()["last_server_tick"]) + 1
	session.inject_offline_snapshot({
		"server_tick": injected_tick,
		"server_time_seconds": float(injected_tick) / 10.0,
		"entities": [
			_entity(String(session.local_entity_id), start_position.x + 20.0, 2, 1, injected_tick),
			_entity("player.other", 100.0, 6, 0, injected_tick),
		],
	})
	_expect_equal(session.local_presentation_state()["last_server_tick"], injected_tick,
		"session routes authority")
	_expect_equal(session.remote_interpolator.tracked_entity_count(), 1, "session routes remotes")
	_expect_true(session.remote_presentation_states().has(&"player.other"), "remote state exposed")
	var invalid_session := Session.new()
	invalid_session.offline_debug_enabled = true
	root.add_child(invalid_session)
	await process_frame
	var handshake_failures: Array[String] = []
	invalid_session.connection_failed.connect(
		func(message: String) -> void: handshake_failures.append(message)
	)
	var invalid_handshake_join: Dictionary = _map_joined_message(
		1, 20, "g08.instance.invalid_handshake", Vector2(420.0, 520.0)
	)["result"]["value"]
	invalid_handshake_join.erase("transition_sequence")
	invalid_handshake_join["session"] = {
		"entity_id": "player.me",
		"reconnect_token": "invalid-handshake-token",
	}
	invalid_handshake_join["snapshot"]["server_tick"] = 19
	invalid_session.network_adapter.receive_server_message({
		"type": "session_opened",
		"result": {"ok": true, "value": invalid_handshake_join},
	})
	_expect_equal(handshake_failures.size(), 1, "invalid initial map join reports connection failure")
	_expect_equal(
		invalid_session.network_adapter.connection_state,
		Adapter.ConnectionState.DISCONNECTED,
		"invalid initial map join closes the client session",
	)
	invalid_session.queue_free()
	session.disconnect_from_server()
	session.queue_free()
	for path: String in [
		session_database_path,
		session_database_path + ".tmp",
		session_database_path + ".bak",
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_finish()


## 验证切图请求的最小权限载荷、失败原子性，以及成功后的状态整体替换。
## [param session] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：用原始可靠消息注入覆盖关联序列，确保移动拒绝和失配响应不能破坏 pending 切图。
func _test_map_change_session(session) -> void:
	var requested: Array[Dictionary] = []
	var joined_events: Array[Dictionary] = []
	var failed_events: Array[Dictionary] = []
	var removed_entities: Array[StringName] = []
	session.map_change_requested.connect(
		func(transition_id: StringName, sequence: int) -> void:
			requested.append({"transition_id": transition_id, "sequence": sequence})
	)
	session.map_joined.connect(
		func(map_id: StringName, instance_id: String, spawn: Vector2, version: int) -> void:
			joined_events.append({
				"map_id": map_id,
				"instance_id": instance_id,
				"spawn": spawn,
				"version": version,
			})
	)
	session.map_change_failed.connect(
		func(transition_id: StringName, code: StringName, message: String) -> void:
			failed_events.append({
				"transition_id": transition_id,
				"code": code,
				"message": message,
			})
	)
	session.remote_entity_removed.connect(
		func(entity_id: StringName) -> void: removed_entities.append(entity_id)
	)

	var old_position: Vector2 = session.local_presentation_state()["position"]
	var first: Dictionary = session.request_map_change(&"exit_to_city", 3)
	_expect_true(MapTransitionIntentContract.from_dictionary(first).is_ok, "map transition payload satisfies contract")
	_expect_equal(
		first.keys().all(func(key): return key in [
			"map_instance_id", "transition_id", "destination_entry_number", "input_sequence",
		]),
		true,
		"map transition payload exposes no destination authority fields",
	)
	_expect_false(first.has("map_id"), "map transition does not self-report destination map")
	_expect_false(first.has("spawn_position"), "map transition does not self-report spawn")
	_expect_true(session.is_map_change_pending(), "map transition becomes pending")
	_expect_equal(requested.size(), 1, "scene layer observes one map change request")
	_expect_equal(session.current_map_id, &"hall", "old map ID remains before response")
	_expect_equal(session.current_map_instance_id, "hall.instance.7", "old instance remains before response")
	_expect_vector(session.local_presentation_state()["position"], old_position, "old prediction remains before response")
	_expect_equal(session.request_map_change(&"other_exit", 0), {}, "second concurrent transition is rejected locally")
	_expect_equal(session.request_move(Vector2(90.0, 0.0)), {}, "movement is paused while transition is pending")

	# An unrelated movement rejection must not complete the transition.
	session.network_adapter.receive_server_message({
		"type": "command_rejected",
		"result": {
			"ok": false,
			"code": "network.value_out_of_range",
			"message": "move rejected",
			"value": {"command_type": "move_intent", "input_sequence": 99},
		},
	})
	_expect_true(session.is_map_change_pending(), "unrelated rejection preserves pending transition")
	_expect_equal(failed_events.size(), 0, "unrelated rejection emits no map failure")

	# A valid join paired with a different-tick snapshot must fail without replacing old-map state.
	session.network_adapter.receive_server_message({
		"type": "map_joined",
		"result": {
			"ok": true,
			"value": {
				"transition_sequence": first["input_sequence"],
				"map_joined": {
					"map_id": "g08",
					"map_instance_id": "g08.instance.mismatched",
					"entity_id": "player.me",
					"spawn_position": {"x": 400.0, "y": 500.0},
					"definition_version": 1,
					"server_tick": 20,
				},
				"snapshot": _snapshot(19, [_entity("player.me", 400.0, 2, 0, 19)]),
			},
		},
	})
	_expect_false(session.is_map_change_pending(), "malformed correlated success releases pending latch")
	_expect_equal(failed_events.size(), 1, "malformed success becomes explicit map failure")
	_expect_equal(session.current_map_id, &"hall", "malformed success preserves old map")
	_expect_equal(session.current_map_instance_id, "hall.instance.7", "malformed success preserves old instance")
	_expect_vector(session.local_presentation_state()["position"], old_position, "malformed success preserves prediction")
	_expect_equal(session.remote_interpolator.tracked_entity_count(), 1, "malformed success preserves remote tracks")

	var second: Dictionary = session.request_map_change(&"exit_to_city", 3)
	var second_sequence := int(second["input_sequence"])
	# A rejection for another transition sequence cannot finish the active request.
	session.network_adapter.receive_server_message(_map_change_rejected_message(
		second_sequence + 100,
		"map_transition.too_far_from_exit",
	))
	_expect_true(session.is_map_change_pending(), "mismatched transition rejection is ignored")
	session.network_adapter.receive_server_message(_map_change_rejected_message(
		second_sequence,
		"map_transition.too_far_from_exit",
	))
	_expect_false(session.is_map_change_pending(), "matching transition rejection releases pending latch")
	_expect_equal(failed_events.size(), 2, "matching rejection emits map failure")
	_expect_equal(failed_events[-1]["transition_id"], &"exit_to_city", "failure identifies requested exit")
	_expect_equal(session.current_map_id, &"hall", "authoritative rejection preserves old map")
	_expect_equal(session.remote_interpolator.tracked_entity_count(), 1, "authoritative rejection preserves remote tracks")

	var third: Dictionary = session.request_map_change(&"exit_to_city", 3)
	var third_sequence := int(third["input_sequence"])
	var commit_signal_order: Array[String] = []
	session.map_joined.connect(
		func(_map_id: StringName, _instance_id: String, _spawn: Vector2, _version: int) -> void:
			commit_signal_order.append("joined")
	)
	session.local_presentation_state_changed.connect(
		func(_state: Dictionary) -> void: commit_signal_order.append("local")
	)
	# Stale success for a previous request cannot replace the active transition.
	session.network_adapter.receive_server_message(_map_joined_message(
		second_sequence, 20, "g08.instance.stale", Vector2(400.0, 500.0)
	))
	_expect_true(session.is_map_change_pending(), "stale map join sequence is ignored")
	_expect_equal(session.current_map_id, &"hall", "stale map join preserves old map")

	session.network_adapter.receive_server_message(_map_joined_message(
		third_sequence, 20, "g08.instance.2", Vector2(420.0, 520.0)
	))
	_expect_false(session.is_map_change_pending(), "matching map join completes transition")
	_expect_equal(session.current_map_id, &"g08", "successful join atomically replaces map ID")
	_expect_equal(session.current_map_instance_id, "g08.instance.2", "successful join replaces instance ID")
	_expect_equal(session.network_adapter.map_id, "g08", "adapter observes committed target map ID")
	_expect_equal(session.network_adapter.map_instance_id, "g08.instance.2", "adapter observes committed target instance")
	_expect_vector(session.local_presentation_state()["position"], Vector2(420.0, 520.0), "successful join resets prediction to spawn")
	_expect_equal(session.local_predictor.pending_intent_count(), 0, "successful join drops old-map prediction inputs")
	_expect_true(&"player.other" in removed_entities, "successful join removes old-map remote entity")
	_expect_false(session.remote_presentation_states().has(&"player.other"), "old-map remote track cannot survive transfer")
	_expect_true(session.remote_presentation_states().has(&"player.new_map"), "initial target-map snapshot is projected")
	_expect_equal(joined_events.size(), 1, "scene layer observes one committed map join")
	_expect_equal(joined_events[0]["version"], 1, "joined event includes definition version")
	_expect_equal(commit_signal_order, ["joined", "local"], "join is visible before new spawn presentation")

	# A delayed packet from the previous map cannot roll back the newly reset predictor.
	session.inject_offline_snapshot({
		"server_tick": 19,
		"server_time_seconds": 0.95,
		"entities": [_entity("player.me", 1.0, 0, 0, 19)],
	})
	_expect_vector(session.local_presentation_state()["position"], Vector2(420.0, 520.0), "pre-join snapshot is ignored")


## 执行 `map_change_rejected_message` 对应的模块操作。
## [param transition_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _map_change_rejected_message(transition_sequence: int, code: String) -> Dictionary:
	return {
		"type": "command_rejected",
		"result": {
			"ok": false,
			"code": code,
			"message": "map change rejected",
			"value": {
				"command_type": "map_transition_intent",
				"transition_sequence": transition_sequence,
			},
		},
	}


## 执行 `map_joined_message` 对应的模块操作。
## [param transition_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param spawn_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _map_joined_message(
	transition_sequence: int,
	server_tick: int,
	instance_id: String,
	spawn_position: Vector2,
) -> Dictionary:
	return {
		"type": "map_joined",
		"result": {
			"ok": true,
			"code": "ok",
			"message": "",
			"value": {
				"transition_sequence": transition_sequence,
				"map_joined": {
					"map_id": "g08",
					"map_instance_id": instance_id,
					"entity_id": "player.me",
					"spawn_position": {"x": spawn_position.x, "y": spawn_position.y},
					"definition_version": 1,
					"server_tick": server_tick,
				},
				"snapshot": {
					"server_tick": server_tick,
					"server_time_seconds": float(server_tick) / 20.0,
					"entities": [
						_entity("player.me", spawn_position.x, 2, 0, server_tick).merged({
							"position": {"x": spawn_position.x, "y": spawn_position.y},
						}, true),
						_entity("player.new_map", spawn_position.x + 20.0, 6, 0, server_tick).merged({
							"position": {"x": spawn_position.x + 20.0, "y": spawn_position.y},
						}, true),
					],
				},
			},
		},
	}


## 执行 `entity` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param x] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param acknowledged_input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _entity(
	entity_id: String,
	x: float,
	direction: int,
	acknowledged_input_sequence := 0,
	server_tick := 0,
) -> Dictionary:
	return {
		"entity_id": entity_id,
		"server_tick": server_tick,
		"position": {"x": x, "y": 0.0},
		"facing_direction": direction,
		"action_id": "walking",
		"speed": 100.0,
		"state_revision": 1,
		"acknowledged_input_sequence": acknowledged_input_sequence,
	}


## 执行 `snapshot` 对应的模块操作。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entities] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _snapshot(server_tick: int, entities: Array) -> Dictionary:
	return {
		"server_tick": server_tick,
		"server_time_seconds": float(server_tick) / 20.0,
		"entities": entities,
	}


## 执行 `expect_true` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_true(value: bool, label: String) -> void:
	assertions += 1
	if not value:
		failures.append(label)


## 执行 `expect_false` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param label] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect_false(value: bool, label: String) -> void:
	_expect_true(not value, label)


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


## 输出客户端网络测试汇总，并根据累计失败数量设置进程退出码。
func _finish() -> void:
	if failures.is_empty():
		print("CLIENT NETWORK TESTS PASSED: %d assertions" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	print("CLIENT NETWORK TESTS FAILED: %d assertions, %d failures" % [assertions, failures.size()])
	quit(1)
