extends SceneTree

const MainHallScene := preload("res://scenes/main_hall.tscn")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")

var failures: PackedStringArray = []
var assertions := 0
var database_path := ""


## 延迟执行旧地图存档的完整启动场景回归。
func _initialize() -> void:
	call_deferred("_run")


## 预置业务化前的宇航中心地图 ID，并验证大厅启动能迁移地图、坐标和加载遮罩。
func _run() -> void:
	database_path = "res://persisted_map_startup_%d.tmp" % Time.get_ticks_usec()
	var seeded_server = ServerScript.new()
	var seeded_result: Dictionary = seeded_server.initialize(_server_config())
	_expect(seeded_result.ok, "旧存档夹具必须初始化权威服务器")
	if not seeded_result.ok:
		_finish(null, seeded_server)
		return
	var opened: Dictionary = seeded_server.open_session(2, _handshake(), 1000)
	_expect(opened.ok, "旧存档夹具必须创建默认角色")
	if not opened.ok:
		_finish(null, seeded_server)
		return
	var entity_id := String(opened.value.session.entity_id)
	var loaded = seeded_server.player_state_repository.load_player(entity_id)
	_expect(loaded.is_ok, "旧存档夹具必须读取默认角色")
	if not loaded.is_ok:
		_finish(null, seeded_server)
		return
	var legacy_state: PlayerStateRecord = loaded.value
	legacy_state.map_id = "glory_nft_bl_nasa1"
	legacy_state.map_instance_id = "glory_nft_bl_nasa1.instance.1"
	legacy_state.position = Vector2(1381.0, 918.0)
	_expect(
		seeded_server.player_state_repository.save_player(
			legacy_state, legacy_state.revision
		).is_ok,
		"旧存档夹具必须写入规范化前的宇航中心位置",
	)
	seeded_server.free()

	var hall: Node2D = MainHallScene.instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	hall.map_travel._initial_authoritative_world_ready = false
	hall.initial_loading_screen.show_loading("正在读取角色与地图数据")
	_expect(
		hall.multiplayer_presenter.session.network_adapter.configure_in_process_server(
			_server_config()
		),
		"完整启动夹具必须注入正式持久化配置",
	)
	_expect(
		hall.multiplayer_presenter.session.connect_to_server("in-process", 0) == OK,
		"完整启动夹具必须建立进程内权威会话",
	)
	for _frame in range(30):
		if hall.map_travel._initial_authoritative_world_ready:
			break
		await process_frame
	_expect(hall.map_travel._initial_authoritative_world_ready, "旧地图存档必须在启动期间完成权威地图提交")
	_expect(not hall.initial_loading_screen.visible, "权威地图提交后必须关闭角色与地图加载遮罩")
	_expect(
		hall.active_world_controller.definition.map_id == &"dragon_city_space_center",
		"客户端必须加载当前业务化的宇航中心地图",
	)
	_expect(
		hall.world_view.player.position.is_equal_approx(Vector2(1381.0, 918.0)),
		"客户端必须恢复旧存档中仍可达的角色坐标",
	)
	_finish(hall, null)


## 构造共享测试仓储的完整进程内权威服务器配置。
## 返回启用正式地图目录和持久化、但不监听网络端口的配置。
func _server_config():
	var config := ServerConfigScript.new()
	config.network_enabled = false
	config.persistence_enabled = true
	config.player_state_store_path = database_path
	config.dynamic_blocking_enabled = false
	return config


## 构造与当前客户端版本一致的会话握手载荷。
## 返回协议版本和内容版本字典。
func _handshake() -> Dictionary:
	return {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}


## 记录一个场景级布尔断言。
## [param condition] 预期成立的条件。
## [param message] 失败时输出的诊断信息。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 释放测试节点、清理仓储并按断言结果结束进程。
## [param hall] 已创建的大厅场景；前置失败时为空。
## [param seeded_server] 尚未移交给场景的夹具服务器；正常路径为空。
func _finish(hall: Node, seeded_server: Node) -> void:
	if hall != null:
		hall.free()
	if seeded_server != null:
		seeded_server.free()
	for path: String in [database_path, database_path + ".tmp", database_path + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("PERSISTED_MAP_STARTUP_SCENE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
