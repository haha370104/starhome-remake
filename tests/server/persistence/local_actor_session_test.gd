extends SceneTree

var checks := 0
var failures: Array[String] = []


## 经正式持久化及移动入口验证插件角色不占用普通玩家身份。
func _initialize() -> void:
	call_deferred("_run")


## 先启动插件角色，再登录真人、退出插件并重建服务器，验证双方各自保存恢复。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.dynamic_blocking_enabled = false
	config.player_state_store_path = "user://local-actors-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "正式服务器初始化")
	var opened := server.open_local_actor("ai_explorer")
	_check(opened.ok, "本地角色会话")
	var actor_peer := int(opened.value.session.peer_id)
	var actor_id := String(opened.value.session.entity_id)
	_check(actor_id == "local.ai_explorer" and actor_peer >= 0x100000000, "身份及连接空间独立")
	_check(not server.open_local_actor("ai_explorer").ok, "在线身份不可重复创建")
	_check(not server.open_local_actor("../player.1").ok, "拒绝伪造或路径式身份")
	var human := server.open_session(2, {"protocol_version": config.protocol_version,
		"content_version": config.content_version, "actor_key": "ai_explorer"})
	_check(human.ok and human.value.session.entity_id == "player.1", "普通握手不能选择插件身份且仍为player.1")
	var human_before := server.autosave_service.state_for("player.1").to_dictionary()
	var map := server.map_registry.instance_by_id(server.sessions.session_for_peer(actor_peer).map_instance_id)
	var actor: AuthoritativeEntity = map.entities[actor_id]
	var origin := actor.position
	var target: Vector2 = map.navigation.closest_reachable_position(origin, origin + Vector2(80, 0))
	var moved := server.handle_peer_move(actor_peer, MoveIntent.new(map.instance_id, target, 1).to_dictionary())
	_check(moved.ok, "插件经过正常移动校验")
	server.advance_simulation(1.0)
	_check(actor.position.distance_to(origin) > 1.0, "真实模拟推进插件角色")
	var final_position := actor.position
	var exited := server.handle_peer_player_panel_command(actor_peer, {"type": "prepare_exit", "request_id": "local-actor-test".md5_text()})
	_check(exited.ok and server.sessions.session_for_entity(actor_id) == null, "正常退出保存并释放插件角色")
	_check(server.sessions.session_for_peer(2) != null and server.autosave_service.state_for("player.1").currency == human_before.currency,
		"插件退出不关闭或改写真人钱包")
	server._save_all_persistent_players()
	server.free()
	server = AuthoritativeServer.new()
	_check(server.initialize(config).ok, "重启服务器")
	human = server.open_session(2, {"protocol_version": config.protocol_version, "content_version": config.content_version})
	_check(human.ok and human.value.session.entity_id == "player.1", "关闭插件后普通存档身份不变")
	opened = server.open_local_actor("ai_explorer")
	_check(opened.ok, "重开同一插件角色")
	map = server.map_registry.instance_by_id(server.sessions.session_for_entity(actor_id).map_instance_id)
	_check(map.entities[actor_id].position.distance_to(final_position) < 0.1, "插件角色独立恢复已保存位置")
	server._save_all_persistent_players()
	server.free()
	print("Local actor sessions: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计可观察的真实行为断言。
## [param condition] 实际条件。[param message] 预期说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
