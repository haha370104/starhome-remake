extends SceneTree

class FailingWriter extends BackgroundFileWriter:
	## 模拟退出时真实后台写盘失败，不操作用户存档。
	## [param _job] 未写入的快照。
	## 返回磁盘失败。
	func _write_job(_job: Dictionary) -> DomainResult:
		return DomainResult.failure(&"test.disk_failure", "模拟后台磁盘失败")

var checks := 0
var failures: Array[String] = []


## 使用完整权威服务器检验内存事务、延迟存档与退出持久化边界。
func _initialize() -> void:
	call_deferred("_run")


## 验证当前仓储默认异步，只有检查点与正常退出触发磁盘快照。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	_check(config.autosave_interval_seconds == 60.0, "游戏默认一分钟检查点")
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.map_catalog_path = "res://tests/fixtures/nonexistent_map_catalog.json"
	config.default_spawn = Vector2(2412, 2400)
	config.player_state_store_path = "user://background-persistence/state.json"
	config.autosave_interval_seconds = 0.5
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "默认服务器启动后台仓储")
	var repository := server.player_state_repository as FilePlayerStateRepository
	_check(repository._writer != null, "真实游戏启用后台线程")
	_check(server.open_session(97, {"protocol_version":config.protocol_version, "content_version":config.content_version}, 0).ok, "角色会话")
	var session := server.sessions.session_for_peer(97)
	var state := server.autosave_service.state_for(session.entity_id)
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(config.player_state_store_path))
	_check(disk.players.is_empty(), "建号只进入内存，普通事务没有实时写盘")
	state.currency += 123
	var committed := server.autosave_service.commit_player_state(session.entity_id, state)
	_check(committed.is_ok and repository.load_player(session.entity_id).value.currency == state.currency, "内存钱包与角色事务立即一致")
	_check(repository.save_player(state, 0).error_code == &"persistence.revision_conflict", "后台模式仍拒绝旧版本")
	var revision: int = committed.value.revision
	server.advance_simulation(0.49, 0)
	_check(repository.load_player(session.entity_id).value.revision == revision, "检查点到期前不重复采集")
	server.advance_simulation(0.01, 0)
	_check(repository._writer.flush().is_ok, "等候已入队的定时快照")
	disk = JSON.parse_string(FileAccess.get_file_as_string(config.player_state_store_path))
	_check(disk.players[session.entity_id].currency == state.currency, "定时快照保存最新钱包")
	var before := server.autosave_service.state_for(session.entity_id).to_dictionary()
	repository._writer.close()
	repository._writer = FailingWriter.new()
	repository._writer.start()
	var command := {"type":"prepare_exit", "request_id":"0123456789abcdef0123456789abcdef"}
	var failed := server.handle_peer_player_panel_command(97, command)
	_check(not failed.ok, "后台退出失败不给成功回执")
	_check(server.sessions.session_for_peer(97) == session, "退出失败保留会话")
	_check(server.autosave_service.state_for(session.entity_id).to_dictionary() == before, "退出失败不采用暂停生产或新版本候选")
	repository._writer.close()
	repository._writer = BackgroundFileWriter.new()
	repository._writer.start()
	var identity := session.entity_id
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	map.vehicle_combat_state_for(identity).health = 37
	map.vehicle_combat_state_for(identity).reserve_energy = 1234
	var exited := server.handle_peer_player_panel_command(97, command)
	_check(exited.ok and server.sessions.session_for_peer(97) == null, "正常退出等待真实落盘再释放会话")
	disk = JSON.parse_string(FileAccess.get_file_as_string(config.player_state_store_path))
	_check(disk.players[identity].vehicle_health == 37 and disk.players[identity].reserve_energy == 1234, "退出保存最新战斗资源")
	_check(server.handle_peer_player_panel_command(97, command).value == exited.value, "退出回执仍幂等")
	server.free()
	var reopened := FilePlayerStateRepository.new(config.player_state_store_path)
	_check(reopened.initialize().is_ok and reopened.load_player(identity).value.vehicle_health == 37, "正常退出后的文件可重新加载")
	for failure in failures: push_error(failure)
	print("BACKGROUND_PERSISTENCE_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 汇总真实后台存档行为。
## [param condition] 断言结果。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
