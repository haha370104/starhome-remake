extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run()


func _run() -> void:
	var unconfigured := PlayerPanelCoordinator.new()
	var unavailable := unconfigured.execute(1, {"type": "query"})
	_check(not unavailable.ok and unavailable.code == &"panel_coordinator.unavailable",
		"未配置协调器应拒绝面板命令")

	var config := ConfigScript.new()
	config.network_enabled = false
	config.player_state_store_path = "user://player-panel-coordinator-%d.json" % Time.get_ticks_usec()
	var server: AuthoritativeServer = ServerScript.new()
	var initialized := server.initialize(config)
	_check(initialized.ok, "服务器应组装玩家面板协调器")
	if initialized.ok:
		_check(server._player_panel_coordinator != null, "服务器应持有唯一面板协调器")
		var opened := server.open_session(71, {
			"protocol_version": config.protocol_version,
			"content_version": config.content_version,
		}, 1000)
		_check(opened.ok, "面板协调器测试应建立权威会话")
		if opened.ok:
			var presets := server.handle_peer_player_panel_command(71, {
				"type": "query_vehicle_presets",
			})
			_check(presets.ok and presets.value.has("vehicle_presets"),
				"面板查询应经协调器返回战车预设")
			var scene_players := server.handle_peer_player_panel_command(71, {
				"type": "query_scene_players",
			})
			var session: ServerSession = server.sessions.session_for_peer(71)
			_check(scene_players.ok and scene_players.value.scene_players.map_instance_id == session.map_instance_id,
				"场景玩家查询应使用会话地图而非客户端地图")
			session.manufacturing_station = "station.fixture"
			var closed := server.handle_peer_player_panel_command(71, {
				"type": "close_manufacturing",
			})
			_check(closed.ok and session.manufacturing_station.is_empty(),
				"关闭生产面板应经协调器清除会话站点")
		server.free()

	var no_persistence_config := ConfigScript.new()
	no_persistence_config.network_enabled = false
	no_persistence_config.persistence_enabled = false
	var no_persistence: AuthoritativeServer = ServerScript.new()
	var no_persistence_initialized := no_persistence.initialize(no_persistence_config)
	_check(no_persistence_initialized.ok, "无存档服务器仍应完成面板协调器组装")
	if no_persistence_initialized.ok:
		var no_persistence_opened := no_persistence.open_session(72, {
			"protocol_version": no_persistence_config.protocol_version,
			"content_version": no_persistence_config.content_version,
		}, 1000)
		_check(no_persistence_opened.ok, "无存档服务器应建立临时会话")
		var rejected := no_persistence.handle_peer_player_panel_command(72, {
			"type": "query_vehicle_presets",
		})
		_check(not rejected.ok and rejected.code == &"panels.persistence_required",
			"无存档模式应保持 persistence_required 兼容错误")
		no_persistence.free()

	for failure: String in failures:
		push_error(failure)
	print("PLAYER_PANEL_COORDINATOR_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
