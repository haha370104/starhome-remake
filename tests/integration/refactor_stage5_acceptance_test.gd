extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const ControllerScript := preload("res://scripts/server/llm/llm_player_controller.gd")

const MAP_PATH := "res://data/maps/glory_nft_bl_d04.json"
const HANDSHAKE_PEER_START := 801
const PLAYER_COUNT := 4

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config := ConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.map_config_path = MAP_PATH
	config.map_catalog_path = "res://tests/fixtures/nonexistent_map_catalog.json"
	config.default_spawn = Vector2(2412.0, 2400.0)
	config.dynamic_blocking_enabled = false
	config.autosave_interval_seconds = 0.25
	config.player_state_store_path = "user://refactor-stage5-acceptance-%d.json" % Time.get_ticks_usec()
	var server: AuthoritativeServer = ServerScript.new()
	var initialized := server.initialize(config)
	_check(initialized.ok, "阶段 5 组合验收服务器初始化")
	if not initialized.ok:
		_finish(server)
		return
	root.add_child(server)
	var d04_result := server.ensure_runtime_map("glory_nft_bl_d04")
	_check(d04_result.ok, "阶段 5 组合验收加载 D04 运行实例")
	if not d04_result.ok:
		_finish(server)
		return
	var d04_instance: AuthoritativeMapInstance = d04_result.value

	_check(d04_instance.definition.map_id == &"glory_nft_bl_d04", "验收地图必须是 D04")
	var population_policy: Dictionary = server._combat_catalog.monster_population_policy_for_map("glory_nft_bl_d04")
	print("STAGE5_D04_POPULATION actual=%d configured_maximum=%d" % [
		d04_instance.combat_module.monsters.size(), int(population_policy.get("maximum_population", 0)),
	])
	_check(int(population_policy.get("maximum_population", 0)) == 200,
		"D04 普通怪物种群上限必须为 200")
	_check(d04_instance.combat_module.monsters.size() >= 200,
		"D04 实际初始怪物数量应达到约 200")
	var sessions: Array[ServerSession] = []
	for index in range(PLAYER_COUNT):
		var peer_id := HANDSHAKE_PEER_START + index
		var opened := server.open_session(peer_id, _handshake(config), 1000)
		_check(opened.ok, "同图混合角色会话建立 %d" % index)
		if opened.ok:
			var session: ServerSession = server.sessions.session_for_peer(peer_id)
			sessions.append(session)
	_check(sessions.size() == PLAYER_COUNT, "四个角色必须全部进入同一权威地图")
	if sessions.size() != PLAYER_COUNT:
		_finish(server)
		return

	var map_instance_id := sessions[0].map_instance_id
	for session: ServerSession in sessions:
		_check(session.map_instance_id == map_instance_id, "四个角色的会话地图必须一致")
	_check(d04_instance.entities.has(sessions[0].entity_id), "Human 角色实体必须存在")
	_check(d04_instance.entities.has(sessions[1].entity_id), "第二个 Human 角色实体必须存在")

	_check(server.disconnect_session(HANDSHAKE_PEER_START + 2, 1000).ok, "第一个 LLM 角色断开 Human 会话")
	_check(server.disconnect_session(HANDSHAKE_PEER_START + 3, 1000).ok, "第二个 LLM 角色断开 Human 会话")
	var resolver := func(_area_id: String, frame: Dictionary) -> DomainResult:
		var actor_id := String(frame.get("actor_id", ""))
		var actor_session := server.sessions.session_for_entity(actor_id)
		if actor_session == null:
			return DomainResult.failure(&"test.actor_missing", "actor session is missing")
		var actor_map: AuthoritativeMapInstance = server.map_registry.instance_by_id(actor_session.map_instance_id)
		var actor: AuthoritativeEntity = actor_map.entities.get(actor_id) if actor_map != null else null
		if actor == null:
			return DomainResult.failure(&"test.actor_missing", "actor entity is missing")
		return DomainResult.ok({
			"map_instance_id": actor_session.map_instance_id,
			"target_position": actor.position,
		})
	var provider := func(frame: Dictionary) -> HighLevelPlayerAction:
		var revision := int(frame.get("observation_revision", -1))
		return HighLevelPlayerAction.wait_action(
			"stage5.acceptance.%d.%d" % [revision, Time.get_ticks_usec()],
			revision,
			Time.get_ticks_msec() + 1000,
		)
	for index in [2, 3]:
		var controller: LlmPlayerController = ControllerScript.new()
		var registered := server.register_llm_player(
			sessions[index].entity_id, controller, resolver, provider,
		)
		_check(registered.is_ok, "LLM 角色注册 %d" % (index - 1))
		var observed := server.observe_llm_player(sessions[index].entity_id)
		_check(observed.is_ok, "LLM 角色观察 %d" % (index - 1))
		_check(server.request_llm_decision(sessions[index].entity_id).is_ok,
			"LLM 角色异步决策 %d" % (index - 1))
	for _frame in range(8):
		await process_frame
	_check(server.sessions.active_sessions().size() == 2, "LLM 接管后只保留两个 Human 网络会话")
	_check(d04_instance.entities.size() >= PLAYER_COUNT, "混合角色实体仍在同一张 D04 地图")

	var blocked_reconnect := server.open_session(805, _handshake(config, sessions[2].reconnect_token), 1001)
	_check(not blocked_reconnect.ok and blocked_reconnect.code == &"llm.actor_controlled",
		"LLM 控制期间 Human 重连必须被拒绝")

	var tick_before_checkpoint := server.server_tick
	var snapshots_before_checkpoint := server.emitted_snapshot_count
	var saves_before_checkpoint := server.autosave_service.save_count
	server.autosave_service.mark_dirty(sessions[0].entity_id, ["location"])
	server.advance_simulation(0.5, 1500)
	_check(server.server_tick - tick_before_checkpoint == 10, "组合验收应推进 20Hz 的十个 tick")
	_check(server.emitted_snapshot_count - snapshots_before_checkpoint == 5,
		"快照应在同一推进窗口发布五次")
	_check(server.autosave_service.save_count > saves_before_checkpoint,
		"自动存档到期应在同一窗口完成保存")

	var scene_players := server.handle_peer_player_panel_command(
		HANDSHAKE_PEER_START,
		{"type": "query_scene_players"},
	)
	_check(scene_players.ok, "Human 面板场景名单查询成功")
	if scene_players.ok:
		var projected: Dictionary = scene_players.value.scene_players
		_check(projected.map_instance_id == map_instance_id, "面板场景名单使用会话地图")
		_check(projected.players.size() == 2, "面板场景名单只投影在线 Human 角色")

	_check(server.unregister_llm_player(sessions[2].entity_id).is_ok, "注销第一个 LLM 控制")
	_check(server.unregister_llm_player(sessions[3].entity_id).is_ok, "注销第二个 LLM 控制")
	var reclaimed := server.open_session(805, _handshake(config, sessions[2].reconnect_token), 2000)
	_check(reclaimed.ok, "注销 LLM 控制后允许 Human 使用重连令牌")

	_finish(server)


func _handshake(config: DedicatedServerConfig, reconnect_token := "") -> Dictionary:
	var request := {
		"protocol_version": config.protocol_version,
		"content_version": config.content_version,
	}
	if not reconnect_token.is_empty():
		request["reconnect_token"] = reconnect_token
	return request


func _finish(server: AuthoritativeServer) -> void:
	if is_instance_valid(server):
		server.free()
	for failure: String in failures:
		push_error(failure)
	print("REFACTOR_STAGE5_ACCEPTANCE_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
