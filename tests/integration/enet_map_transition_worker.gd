extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const SessionScript := preload("res://scripts/client/network/client_multiplayer_session.gd")

const SOURCE_MAP_ID := "yian_harbor_hall_floor_1"
const SOURCE_INSTANCE_ID := "yian_harbor_hall_floor_1.instance.1"
const TARGET_MAP_ID := "yian_harbor_city"
const TARGET_INSTANCE_ID := "yian_harbor_city.instance.1"
const TARGET_SPAWN := Vector2(1399.0, 954.0)

var role := ""
var port := 24680
var result_dir := ""
var failures: Array[String] = []
var joined_results: Array[Dictionary] = []
var snapshots_after_join: Array[Dictionary] = []
var transition_committed := false


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
		"client":
			await _run_client()
		_:
			_fail("unknown worker role: %s" % role)
			_finish({})


## 执行 `run_server` 对应的模块操作。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _run_server() -> void:
	var server = ServerScript.new()
	server.name = "AuthoritativeServer"
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = false
	config.port = port
	config.default_spawn = Vector2(480.0, 370.0)
	server.config = config
	root.add_child(server)
	await process_frame
	var listen_result: Dictionary = server.start_network()
	if not bool(listen_result.get("ok", false)):
		_fail("server listen failed: %s" % listen_result)
		_finish({})
		return
	var source: AuthoritativeMapInstance
	var target: AuthoritativeMapInstance
	if not server.map_registry.all_instances().is_empty():
		_fail("server must not load maps before any player arrives")
		server.stop_network()
		_finish({})
		return
	_write_json("server_ready.json", {"port": port})
	var deadline := Time.get_ticks_msec() + 15000
	var entity_id := ""
	var saw_source_ownership := false
	var saw_target_ownership := false
	var source_released := false
	var session_switched := false
	var target_snapshot_isolated := false
	while Time.get_ticks_msec() < deadline:
		if source == null:
			source = server.map_registry.instance_by_id(SOURCE_INSTANCE_ID)
		if target == null:
			target = server.map_registry.instance_by_id(TARGET_INSTANCE_ID)
		var all_sessions: Array[ServerSession] = server.sessions.all_sessions()
		if not all_sessions.is_empty():
			var active_session: ServerSession = all_sessions[0]
			entity_id = active_session.entity_id
			if source != null and source.entities.has(entity_id) \
					and (target == null or not target.entities.has(entity_id)):
				saw_source_ownership = true
			if source != null and target != null and target.entities.has(entity_id):
				saw_target_ownership = true
				source_released = not source.entities.has(entity_id)
				session_switched = active_session.map_instance_id == TARGET_INSTANCE_ID
				var peer_snapshot := server.snapshot_for_peer(active_session.peer_id)
				target_snapshot_isolated = (
					_snapshot_has_entity(peer_snapshot, entity_id)
					and not _snapshot_has_foreign_entity(peer_snapshot, entity_id)
					and not _snapshot_has_entity(source.snapshot(server.server_tick, 0.0), entity_id)
				)
		if (
			saw_source_ownership
			and saw_target_ownership
			and source_released
			and session_switched
			and target_snapshot_isolated
		):
			break
		await process_frame
	if not saw_source_ownership:
		_fail("server never observed the entity owned only by RoomSvr1 before transfer")
	if not saw_target_ownership:
		_fail("server never observed the entity owned by City1Svr after transfer")
	if not source_released:
		_fail("RoomSvr1 retained the entity after target admission")
	if not session_switched:
		_fail("server session did not atomically switch to the City1Svr instance")
	if not target_snapshot_isolated:
		_fail("peer snapshot was not isolated to the target map after transfer")
	if failures.is_empty():
		# Keep ENet alive long enough for reliable MapJoined and several target snapshots to flush.
		await create_timer(1.0).timeout
	server.stop_network()
	_finish({
		"entity_id": entity_id,
		"source_map_id": SOURCE_MAP_ID,
		"target_map_id": TARGET_MAP_ID,
		"saw_source_ownership": saw_source_ownership,
		"saw_target_ownership": saw_target_ownership,
		"source_released": source_released,
		"session_switched": session_switched,
		"target_snapshot_isolated": target_snapshot_isolated,
	})


## 执行 `run_client` 对应的模块操作。
## 设计：该测试以隔离夹具验证公开契约，不依赖未声明的全局状态。
func _run_client() -> void:
	var session: ClientMultiplayerSession = SessionScript.new()
	session.name = "ClientMultiplayerSession"
	root.add_child(session)
	await process_frame
	session.network_adapter.map_joined_received.connect(_on_map_joined_result)
	session.network_adapter.authoritative_snapshot_received.connect(_on_snapshot_received)
	if session.connect_to_server("127.0.0.1", port) != OK:
		_fail("client could not start connecting")
		_finish({})
		return
	if not await _wait_until(
		func() -> bool:
			return session.network_adapter.session_ready \
				and String(session.current_map_id) == SOURCE_MAP_ID,
		5.0,
	):
		_fail("client did not join RoomSvr1")
		_finish({})
		return
	var entity_id := String(session.local_entity_id)
	var source_instance_id := session.current_map_instance_id
	var payload := session.request_map_change(&"exit_to_city", 0)
	if payload.is_empty():
		_fail("client rejected the valid RoomSvr1 exit request locally")
		_finish({})
		return
	if not await _wait_until(
		func() -> bool:
			return String(session.current_map_id) == TARGET_MAP_ID \
				and session.current_map_instance_id == TARGET_INSTANCE_ID \
				and not session.is_map_change_pending(),
		5.0,
	):
		_fail("client did not commit the authoritative City1Svr MapJoined")
		_finish({})
		return
	if joined_results.size() != 1:
		_fail("client expected exactly one explicit MapJoined result")
	var joined_contract_ok := false
	var joined_spawn := Vector2.INF
	var joined_entity_id := ""
	if not joined_results.is_empty():
		var value: Dictionary = joined_results[-1].get("value", {})
		var joined_result = MapJoinedContract.from_dictionary(value.get("map_joined", {}))
		joined_contract_ok = joined_result.is_ok
		if joined_result.is_ok:
			joined_spawn = joined_result.value.spawn_position
			joined_entity_id = joined_result.value.entity_id
	if not joined_contract_ok:
		_fail("explicit map result did not satisfy the strict MapJoined contract")
	if joined_entity_id != entity_id:
		_fail("MapJoined changed the server-assigned entity identity")
	if not joined_spawn.is_equal_approx(TARGET_SPAWN):
		_fail("MapJoined spawn did not match City1Svr entry 0: %s" % joined_spawn)
	if not await _wait_until(func() -> bool: return snapshots_after_join.size() >= 4, 4.0):
		_fail("client did not receive four post-transition target snapshots")
	var latest_snapshots_isolated := true
	for snapshot_index in range(maxi(0, snapshots_after_join.size() - 3), snapshots_after_join.size()):
		var snapshot := snapshots_after_join[snapshot_index]
		if not _snapshot_has_entity(snapshot, entity_id) \
			or _snapshot_has_foreign_entity(snapshot, entity_id):
			latest_snapshots_isolated = false
	if not latest_snapshots_isolated:
		_fail("latest post-transition snapshots were not isolated to City1Svr")
	var presentation_position: Vector2 = session.local_presentation_state().get(
		"position", Vector2.INF
	)
	if not presentation_position.is_equal_approx(TARGET_SPAWN):
		_fail("client presentation drifted from the authoritative City1Svr spawn")
	session.disconnect_from_server()
	_finish({
		"entity_id": entity_id,
		"source_instance_id": source_instance_id,
		"target_instance_id": session.current_map_instance_id,
		"map_joined_valid": joined_contract_ok,
		"spawn": {"x": joined_spawn.x, "y": joined_spawn.y},
		"post_join_snapshot_count": snapshots_after_join.size(),
		"latest_snapshots_isolated": latest_snapshots_isolated,
	})


## 处理 `_on_map_joined_result` 对应的信号回调。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_map_joined_result(result: Dictionary) -> void:
	joined_results.append(result.duplicate(true))
	transition_committed = true


## 处理 `_on_snapshot_received` 对应的信号回调。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_snapshot_received(snapshot: Dictionary) -> void:
	if transition_committed:
		snapshots_after_join.append(snapshot.duplicate(true))


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


## 执行 `snapshot_has_entity` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _snapshot_has_entity(snapshot: Dictionary, entity_id: String) -> bool:
	for entity: Dictionary in snapshot.get("entities", []):
		if String(entity.get("entity_id", "")) == entity_id:
			return true
	return false


## 执行 `snapshot_has_foreign_entity` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _snapshot_has_foreign_entity(snapshot: Dictionary, entity_id: String) -> bool:
	for entity: Dictionary in snapshot.get("entities", []):
		if String(entity.get("entity_id", "")) != entity_id:
			return true
	return false


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
		print("ENET_MAP_TRANSITION_WORKER_OK role=%s" % role)
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
