extends SceneTree

const PersistenceCoordinatorScript := preload(
	"res://scripts/server/persistence/persistence_coordinator.gd"
)

var checks := 0
var failures: Array[String] = []
var database_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var disabled := PersistenceCoordinatorScript.new()
	_check(not disabled.advance(0.25, false).is_ok, "未配置协调器拒绝推进")
	_check(not disabled.configure(null, null, Callable()).is_ok, "缺少采集端口时拒绝配置")
	_check(disabled.configure(null, null, Callable(self, "_capture_passthrough")).is_ok,
		"关闭持久化时允许配置空服务")
	var disabled_advance := disabled.advance(0.25, false)
	_check(disabled_advance.is_ok and disabled_advance.value == false, "关闭持久化时推进为空操作")
	var disabled_save := disabled.save_all()
	_check(disabled_save.is_ok and disabled_save.value == 0, "关闭持久化时全量保存为空操作")

	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/glory_nft_bl_d04.json"
	config.map_catalog_path = "res://tests/fixtures/nonexistent_map_catalog.json"
	config.default_spawn = Vector2(2412, 2400)
	config.autosave_interval_seconds = 0.25
	database_path = "user://persistence-coordinator/state_%d_%d.json" % [
		OS.get_process_id(), Time.get_ticks_msec(),
	]
	config.player_state_store_path = database_path
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "服务器初始化")
	_check(server._persistence_coordinator != null, "服务器组装持久化协调器")
	var opened := server.open_session(121, {
		"protocol_version": config.protocol_version,
		"content_version": config.content_version,
	}, 0)
	_check(opened.ok, "建立测试会话")
	var identity := server.sessions.session_for_peer(121).entity_id
	var autosave: AuthoritativeAutosaveService = server.autosave_service
	var coordinator: PersistenceCoordinator = server._persistence_coordinator
	var saved_before := autosave.save_count

	var result := coordinator.advance(0.25, false)
	_check(result.is_ok and autosave.save_count == saved_before + 1,
		"到期检查点捕获并保存 dirty 角色")
	_check(autosave.dirty_domains_for(identity).is_empty(), "检查点成功后清除 dirty 领域")

	saved_before = autosave.save_count
	autosave.mark_dirty(identity, ["location"])
	result = coordinator.advance(0.25, true)
	_check(result.is_ok and autosave.save_count == saved_before, "重型刷新时延迟检查点")
	result = coordinator.advance(0.25, false)
	_check(result.is_ok and autosave.save_count == saved_before + 1,
		"延迟检查点在下一次可用帧继续执行")

	saved_before = autosave.save_count
	result = coordinator.save_expired_player(identity)
	_check(result.is_ok and autosave.save_count == saved_before + 1, "过期会话保存最新角色状态")
	result = coordinator.save_all()
	_check(result.is_ok and result.value == 1, "全量保存并等待仓储 flush")
	server._save_all_persistent_players()
	server.free()
	_cleanup_test_files()

	for failure: String in failures:
		push_error(failure)
	print("PERSISTENCE_COORDINATOR_OK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _capture_passthrough(state: Player, _domains: Array[String] = []) -> DomainResult:
	return DomainResult.ok(state)


func _cleanup_test_files() -> void:
	for path: String in [database_path, database_path + ".tmp", database_path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
