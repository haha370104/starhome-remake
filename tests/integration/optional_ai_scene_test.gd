extends SceneTree

var checks := 0
var failures: Array[String] = []


## 使用正式主场景、进程内传输和原有远端角色表现检验AI共存。
func _initialize() -> void:
	call_deferred("_run")


## 验证真人身份、AI实际移动与画面更新，以及关闭后的角色移除。
func _run() -> void:
	root.size = Vector2i(1280, 800)
	var hall: Node2D = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.player_state_store_path = "user://ai-scene-%d.json" % Time.get_ticks_usec()
	config.ai_players_enabled = true
	config.ai_players_config_path = "res://config/ai_players.example.json"
	var session: ClientMultiplayerSession = hall.multiplayer_presenter.session
	_check(session.network_adapter.configure_in_process_server(config), "启用真实进程内服务")
	_check(session.connect_to_server("in-process", 0) == OK, "真人连接成功")
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and not hall.multiplayer_presenter.remote_characters.has(&"local.ai_explorer"):
		await process_frame
	var presenter: HallMultiplayerPresenter = hall.multiplayer_presenter
	_check(presenter.remote_characters.has(&"local.ai_explorer"), "原有表现层显示AI远端角色")
	_check(session.network_adapter.entity_id == "player.1", "真人身份保持不变")
	var transport: InProcessAuthoritativeTransport = session.network_adapter._transport_endpoint
	var server := transport.authoritative_server
	var module: Node = server.get_node_or_null("OptionalAiPlayers")
	_check(module != null and module.get("running"), "运行中的可选模块")
	var peer_snapshots: Array[int] = []
	server.peer_snapshot_generated.connect(func(peer: int, _snapshot: Dictionary) -> void: peer_snapshots.append(peer))
	server._emit_snapshot()
	_check(peer_snapshots.has(2) and peer_snapshots.all(func(peer: int) -> bool: return peer < 0x100000000),
		"只给网络或本地真人生成私有网络快照")
	if presenter.remote_characters.has(&"local.ai_explorer"):
		var remote: Node2D = presenter.remote_characters[&"local.ai_explorer"]
		var origin := remote.position
		await create_timer(2.5).timeout
		_check(remote.position.distance_to(origin) > 1, "AI真实移动经快照呈现在游戏内")
		if "--capture" in OS.get_cmdline_user_args():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://.godot/optional_ai_scene.png")
	if module != null: module.call("stop")
	deadline = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline and presenter.remote_characters.has(&"local.ai_explorer"):
		await process_frame
	_check(not presenter.remote_characters.has(&"local.ai_explorer"), "停用后原有快照链路移除AI视图")
	_check(server.sessions.session_for_peer(2) != null, "停用后真人会话仍正常")
	session.disconnect_from_server()
	hall.queue_free()
	await process_frame
	await process_frame
	print("AI scene: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总场景、传输及生命周期行为断言。
## [param condition] 实际条件。[param message] 预期说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
