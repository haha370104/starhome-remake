extends SceneTree

var checks := 0
var failures: Array[String] = []


## 此测试不静态引用AI类，验证普通启动不会加载可选实现。
func _initialize() -> void:
	call_deferred("_run")


## 验证默认关闭、关闭优先、失败降级及真实模块生命周期。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.ai_players_config_path = "user://does-not-exist-ai.json"
	config.player_state_store_path = "user://ai-opt-in-%d.json" % Time.get_ticks_usec()
	_check(not config.ai_players_enabled, "默认关闭")
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "关闭时忽略不存在的AI配置")
	_check(server.get_node_or_null("OptionalAiPlayers") == null, "无AI节点")
	for file: String in ["ai_module_installer", "ai_player_module", "ai_responses_provider", "ai_player_memory", "ai_player_settings"]:
		_check(not ResourceLoader.has_cached("res://scripts/server/optional_ai/%s.gd" % file), "关闭时不加载：" + file)
	var human := server.open_session(2, {"protocol_version": config.protocol_version, "content_version": config.content_version})
	_check(human.ok and human.value.session.entity_id == "player.1", "普通登录不受影响")
	server._save_all_persistent_players()
	server.free()
	var disabled := DedicatedServerConfig.from_command_line(PackedStringArray(["--disable-ai-players", "--enable-ai-players"]))
	_check(not disabled.ai_players_enabled, "显式关闭优先于启用参数")
	config.ai_players_enabled = true
	server = AuthoritativeServer.new()
	_check(server.initialize(config).ok and server.get_node_or_null("OptionalAiPlayers") == null, "缺失配置只拒绝AI")
	server.free()
	var path := "user://ai-opt-in-config.json"
	var memory_path := "user://ai-opt-in-memory-%d" % Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"provider": "demo", "actors": [{"id": "visitor"}],
		"max_requests_per_session": 1, "memory_directory": memory_path}))
	file.close()
	config.ai_players_config_path = path
	server = AuthoritativeServer.new()
	_check(server.initialize(config).ok, "启用后服务器正常初始化")
	root.add_child(server)
	await process_frame
	await process_frame
	var module: Node = server.get_node_or_null("OptionalAiPlayers")
	_check(module != null and module.get("running"), "明确启用才启动模块")
	if module != null:
		module.set_process(false)
		module.call("advance", Time.get_ticks_msec())
		await process_frame
		_check(module.get("request_count") == 1, "演示决策实际执行")
		for index in 80:
			module.call("advance", Time.get_ticks_msec() + index * 500)
			server.advance_simulation(0.5)
			await process_frame
		_check(module.get("request_count") == 1, "总预算用完不再请求")
		var actors: Array = module.get("actors")
		_check(actors.size() == 1 and actors[0].paused and actors[0].history.size() > 0, "预算耗尽仅暂停AI并记录结果")
		human = server.open_session(2, {"protocol_version": config.protocol_version, "content_version": config.content_version})
		_check(human.ok and human.value.session.entity_id == "player.1", "启用AI后真人仍使用原存档")
		module.call("stop")
		module.call("stop")
		_check(server.sessions.session_for_entity("local.ai_visitor") == null, "停用释放自己的会话")
		_check(server.sessions.session_for_peer(2) != null, "停用保留真人会话")
		_check(FileAccess.file_exists(memory_path.path_join("visitor.json")), "独立记忆已落盘")
	server.queue_free()
	await process_frame
	print("AI opt-in: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总开关、失败降级及生命周期断言。
## [param condition] 实际条件。[param message] 预期说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
