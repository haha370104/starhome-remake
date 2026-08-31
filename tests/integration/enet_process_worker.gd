extends SceneTree

const AdapterScript := preload("res://scripts/client/network/client_network_adapter.gd")
const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")

var role := ""
var port := 24680
var result_dir := ""
var failures: Array[String] = []
var snapshots: Array[Dictionary] = []
var rejections: Array[Dictionary] = []
var session_results: Array[Dictionary] = []
var client


## 使用调用方参数初始化当前实例。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _init() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--role="):
			role = argument.trim_prefix("--role=")
		elif argument.begins_with("--port="):
			port = int(argument.trim_prefix("--port="))
		elif argument.begins_with("--result-dir="):
			result_dir = argument.trim_prefix("--result-dir=")
	call_deferred("_run")


## 执行 `run` 对应的模块操作。
func _run() -> void:
	match role:
		"server":
			await _run_server()
		"client_a":
			await _run_client_a()
		"client_b":
			await _run_client_b()
		_:
			_fail("unknown worker role: %s" % role)
			_finish({})


## 执行 `run_server` 对应的模块操作。
func _run_server() -> void:
	var server = ServerScript.new()
	server.name = "AuthoritativeServer"
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = false
	config.port = port
	config.reconnect_grace_seconds = 1.0
	server.config = config
	root.add_child(server)
	await process_frame
	var result: Dictionary = server.start_network()
	if not bool(result.get("ok", false)):
		_fail("server listen failed: %s" % result)
		_finish({})
		return
	_write_json("server_ready.json", {"port": port})
	var deadline := Time.get_ticks_msec() + 12000
	var saw_two_entities := false
	var saw_disconnected_retained := false
	var saw_resumed_entity := false
	var saw_expired_cleanup := false
	var retained_entity_id := ""
	var known_entities: Array[String] = []
	while Time.get_ticks_msec() < deadline:
		if server.map_instance != null and server.map_instance.entities.size() >= 2:
			saw_two_entities = true
			for entity_id in server.map_instance.entities.keys():
				if not known_entities.has(String(entity_id)):
					known_entities.append(String(entity_id))
		for session in server.sessions.all_sessions():
			if not session.has_active_peer():
				saw_disconnected_retained = true
				retained_entity_id = session.entity_id
			elif not retained_entity_id.is_empty() and session.entity_id == retained_entity_id:
				saw_resumed_entity = true
		if (
			saw_resumed_entity
			and not retained_entity_id.is_empty()
			and server.sessions.session_for_entity(retained_entity_id) == null
			and not server.map_instance.entities.has(retained_entity_id)
		):
			saw_expired_cleanup = true
		if saw_two_entities and saw_disconnected_retained and saw_resumed_entity and saw_expired_cleanup:
			break
		await process_frame
	if saw_expired_cleanup:
		# Let the final complete snapshot without A flush to the still-connected observer B.
		await create_timer(0.5).timeout
	if not saw_two_entities:
		_fail("server never hosted two distinct entities")
	if not saw_disconnected_retained:
		_fail("server never observed a grace-period retained session")
	if not saw_resumed_entity:
		_fail("server never observed the retained session resume")
	if not saw_expired_cleanup:
		_fail("server never removed the resumed entity after its second disconnect grace period")
	server.stop_network()
	_finish({
		"saw_two_entities": saw_two_entities,
		"saw_disconnected_retained": saw_disconnected_retained,
		"saw_resumed_entity": saw_resumed_entity,
		"saw_expired_cleanup": saw_expired_cleanup,
		"entity_ids": known_entities,
	})


## 执行 `run_client_a` 对应的模块操作。
func _run_client_a() -> void:
	client = _new_client()
	root.add_child(client)
	await process_frame
	if client.connect_to_server("127.0.0.1", port) != OK:
		_fail("client A could not start connecting")
		_finish({})
		return
	if not await _wait_until(func() -> bool: return client.session_ready, 5.0):
		_fail("client A handshake timed out")
		_finish({})
		return
	var original_entity_id: String = client.entity_id
	var initial_position := _latest_entity_position(original_entity_id)
	if not initial_position.is_finite():
		_fail("client A initial snapshot omitted its own entity")
		_finish({})
		return
	client.send_move_intent({
		"map_instance_id": client.map_instance_id,
		"requested_world_point": {"x": initial_position.x + 320.0, "y": initial_position.y},
		"input_sequence": 1,
	})
	var moved := await _wait_until(
		func() -> bool:
			var current := _latest_entity_position(original_entity_id)
			return current.is_finite() and current.distance_to(initial_position) > 1.0 \
				and _latest_entity_ack(original_entity_id) >= 1,
		4.0,
	)
	if not moved:
		_fail("client A never received acknowledged movement snapshots")
	client.send_move_intent({
		"map_instance_id": client.map_instance_id,
		"requested_world_point": {"x": "invalid", "y": initial_position.y},
		"input_sequence": 2,
	})
	if not await _wait_until(func() -> bool: return not rejections.is_empty(), 3.0):
		_fail("client A malformed intent was not rejected")
	var reconnect_token: String = client.reconnect_token
	client.disconnect_from_server()
	await create_timer(0.6).timeout
	if client.connect_to_server("127.0.0.1", port) != OK:
		_fail("client A could not start reconnecting")
	elif not await _wait_until(func() -> bool: return client.session_ready, 5.0):
		_fail("client A reconnect timed out")
	var resumed: bool = (
		client.entity_id == original_entity_id
		and not session_results.is_empty()
		and bool(session_results[-1].get("value", {}).get("resumed", false))
	)
	if not resumed:
		_fail("client A reconnect did not resume the original entity")
	_finish({
		"entity_id": original_entity_id,
		"reconnect_token_issued": not reconnect_token.is_empty(),
		"movement_observed": moved,
		"rejection_count": rejections.size(),
		"resumed": resumed,
	})


## 执行 `run_client_b` 对应的模块操作。
func _run_client_b() -> void:
	client = _new_client()
	root.add_child(client)
	await process_frame
	if client.connect_to_server("127.0.0.1", port) != OK:
		_fail("client B could not start connecting")
		_finish({})
		return
	if not await _wait_until(func() -> bool: return client.session_ready, 5.0):
		_fail("client B handshake timed out")
		_finish({})
		return
	var own_entity_id: String = client.entity_id
	var own_initial_position := _latest_entity_position(own_entity_id)
	var found_remote := await _wait_until(
		func() -> bool: return not _latest_remote_entity_id(own_entity_id).is_empty(),
		5.0,
	)
	if not found_remote:
		_fail("client B never received client A in a snapshot")
		_finish({})
		return
	var remote_entity_id := _latest_remote_entity_id(own_entity_id)
	var first_position := _latest_entity_position(remote_entity_id)
	var first_tick_count := _entity_tick_count(remote_entity_id)
	var continuous_motion := await _wait_until(
		func() -> bool:
			var current := _latest_entity_position(remote_entity_id)
			return _entity_tick_count(remote_entity_id) >= first_tick_count + 3 \
				and current.is_finite() and current.distance_to(first_position) > 1.0,
		6.0,
	)
	if not continuous_motion:
		_fail("client B did not receive three continuous updates showing A movement")
	var remote_removed_after_grace := await _wait_until(
		func() -> bool: return _latest_remote_entity_id(own_entity_id).is_empty(),
		6.0,
	)
	if not remote_removed_after_grace:
		_fail("client B never observed A disappear after reconnect grace expiry")
	if not rejections.is_empty():
		_fail("client B received a rejection belonging to client A")
	var own_final_position := _latest_entity_position(own_entity_id)
	var own_state_unchanged := (
		own_initial_position.is_finite()
		and own_final_position.is_finite()
		and own_initial_position.is_equal_approx(own_final_position)
	)
	if not own_state_unchanged:
		_fail("client A's valid/invalid intents mutated client B's authoritative position")
	_finish({
		"entity_id": own_entity_id,
		"remote_entity_id": remote_entity_id,
		"continuous_motion": continuous_motion,
		"remote_removed_after_grace": remote_removed_after_grace,
		"rejection_count": rejections.size(),
		"own_state_unchanged": own_state_unchanged,
	})


## 执行 `new_client` 对应的模块操作。
func _new_client():
	var adapter = AdapterScript.new()
	adapter.authoritative_snapshot_received.connect(
		func(snapshot: Dictionary) -> void: snapshots.append(snapshot.duplicate(true))
	)
	adapter.command_rejected.connect(
		func(code: StringName, message: String) -> void:
			rejections.append({"code": String(code), "message": message})
	)
	adapter.session_opened.connect(
		func(result: Dictionary) -> void: session_results.append(result.duplicate(true))
	)
	return adapter


## 执行 `wait_until` 对应的模块操作。
## [param predicate] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param timeout_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _wait_until(predicate: Callable, timeout_seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + roundi(timeout_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return bool(predicate.call())


## 执行 `latest_remote_entity_id` 对应的模块操作。
## [param own_entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _latest_remote_entity_id(own_entity_id: String) -> String:
	if snapshots.is_empty():
		return ""
	for entity in snapshots[-1].get("entities", []):
		var candidate := String(entity.get("entity_id", ""))
		if not candidate.is_empty() and candidate != own_entity_id:
			return candidate
	return ""


## 执行 `latest_entity_position` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _latest_entity_position(entity_id: String) -> Vector2:
	for snapshot_index in range(snapshots.size() - 1, -1, -1):
		for entity in snapshots[snapshot_index].get("entities", []):
			if String(entity.get("entity_id", "")) == entity_id:
				var position: Dictionary = entity.get("position", {})
				return Vector2(float(position.get("x", 0.0)), float(position.get("y", 0.0)))
	return Vector2(INF, INF)


## 执行 `latest_entity_ack` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _latest_entity_ack(entity_id: String) -> int:
	for snapshot_index in range(snapshots.size() - 1, -1, -1):
		for entity in snapshots[snapshot_index].get("entities", []):
			if String(entity.get("entity_id", "")) == entity_id:
				return int(entity.get("acknowledged_input_sequence", -1))
	return -1


## 执行 `entity_tick_count` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _entity_tick_count(entity_id: String) -> int:
	var ticks: Dictionary = {}
	for snapshot in snapshots:
		for entity in snapshot.get("entities", []):
			if String(entity.get("entity_id", "")) == entity_id:
				ticks[int(snapshot.get("server_tick", -1))] = true
	return ticks.size()


## 执行 `fail` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _fail(message: String) -> void:
	failures.append(message)


## 执行 `finish` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _finish(payload: Dictionary) -> void:
	payload["role"] = role
	payload["ok"] = failures.is_empty()
	payload["failures"] = failures
	_write_json("%s_result.json" % role, payload)
	if failures.is_empty():
		print("ENET_WORKER_OK role=%s" % role)
		quit(0)
		return
	for failure in failures:
		push_error("[%s] %s" % [role, failure])
	quit(1)


## 执行 `write_json` 对应的模块操作。
## [param file_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _write_json(file_name: String, payload: Dictionary) -> void:
	if result_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(result_dir)
	var file := FileAccess.open(result_dir.path_join(file_name), FileAccess.WRITE)
	if file == null:
		_fail("could not write %s" % file_name)
		return
	file.store_string(JSON.stringify(payload, "  "))
