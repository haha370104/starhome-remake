extends SceneTree

const AUDIT_PATH := "res://data/content/glory_map_recovery_20261014.json"
const DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"
var _hall: Node2D
var _exit_confirmed := false


## 启动独立实测入口；地图必须属于已审计的本轮补齐清单。
func _initialize() -> void:
	call_deferred("_run")


## 使用正式客户端、进程内权威会话和独立测试存档，保留真实移动与切图流程。
func _run() -> void:
	var map_id := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--map-id="): map_id = argument.trim_prefix("--map-id=")
	var audit: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(AUDIT_PATH))
	var allowed := false
	for row: Dictionary in audit.maps.values():
		if row.runtime_id == map_id: allowed = true
	if not allowed:
		_fail("请通过 tools/manual_map_test.py 选择本轮补齐地图")
		return
	var mounted: Dictionary = RuntimeContentBootstrap.mount_default()
	if not mounted.get("ok", false):
		_fail("素材包挂载失败：%s" % mounted)
		return
	var directory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY_PATH))
	var path := String(directory.definitions[map_id])
	var loader := MapDefinitionLoader.new()
	var definition := loader.load_file(path)
	if definition == null:
		_fail("地图定义无效：%s" % loader.errors)
		return
	var spawn := definition.spawn_by_id(definition.default_spawn_id)
	if spawn == null:
		_fail("地图缺少可用出生点")
		return
	var save_directory := "res://.godot/manual-map-tests/saves"
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_directory)) != OK:
		_fail("无法创建独立实测存档目录")
		return
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = path
	config.map_catalog_path = DIRECTORY_PATH
	config.default_spawn = spawn.position
	config.player_state_store_path = "%s/%s.json" % [save_directory, Crypto.new().generate_random_bytes(16).hex_encode()]
	root.size = Vector2i(1100, 760)
	root.title = "地图实测 · %s · 临时角色（关闭后返回选图）" % definition.display_name
	_hall = load("res://scenes/main_hall.tscn").instantiate()
	_hall.multiplayer_connect_automatically = false
	root.add_child(_hall)
	await process_frame
	var session: ClientMultiplayerSession = _hall.multiplayer_presenter.session
	if not session.network_adapter.configure_in_process_server(config):
		_fail("无法配置独立权威会话")
		return
	_hall.map_travel._initial_authoritative_world_ready = false
	_hall.initial_loading_screen.show_loading("正在进入地图实测")
	if session.connect_to_server("in-process", 0) != OK:
		_fail("实测会话连接失败")
		return
	if not await _wait_for(func() -> bool: return _hall.map_travel._initial_authoritative_world_ready \
		and _hall.active_world_controller.definition.map_id == StringName(map_id), 30.0): return
	_hall.hud.show_status("地图实测：使用独立临时角色。Tab 打开地图，关闭窗口后可重新选图。")
	print("MANUAL_MAP_READY %s save=%s" % [map_id, config.player_state_store_path])
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		var image_path := "res://.godot/manual-map-tests/%s.png" % map_id
		if root.get_texture().get_image().save_png(image_path) != OK:
			_fail("实测截图保存失败")
			return
	if "--verify" in OS.get_cmdline_user_args(): await _verify(definition)


## 经公开导航意图验证行走、原有出口和保存退出，避免只证明底图可以显示。
## [param definition] 本次选中的审计地图定义。
func _verify(definition: MapDefinition) -> void:
	var start: Vector2 = _hall.world_view.player.position
	var world: ActiveWorldController = _hall.active_world_controller
	var target := start
	for offset in [Vector2(96, 0), Vector2(-96, 0), Vector2(0, 96), Vector2(0, -96)]:
		var candidate: Vector2 = world.navigation.closest_walkable_position(start + offset)
		if candidate.distance_to(start) >= 48 and world.navigation.find_path(start, candidate).size() > 1:
			target = candidate
			break
	if target == start:
		_fail("未找到可供验证的短途路线")
		return
	_hall.hud.map_navigation_requested.emit(target, &"")
	if not await _wait_for(func() -> bool: return _hall.world_view.player.position.distance_to(start) >= 40 \
		and not _hall.local_player_controller.has_active_route(), 10.0): return
	print("MANUAL_MAP_MOVED %s" % definition.map_id)
	for transition: MapTransition in definition.enabled_transitions():
		_hall.interactions.move_to(transition.approach_point, transition.transition_id)
		if not await _wait_for(func() -> bool: return world.definition.map_id == transition.destination_map_id, 30.0): return
		print("MANUAL_MAP_EXIT %s -> %s" % [definition.map_id, world.definition.map_id])
		break
	_hall.exit_controller._quit = _confirm_exit
	_hall.exit_controller.request_exit()
	if not await _wait_for(func() -> bool: return _exit_confirmed, 15.0): return
	_hall.queue_free()
	await process_frame
	print("MANUAL_MAP_VERIFIED %s" % definition.map_id)
	quit(0)


## 接收正常退出控制器确认，测试仅替换最终进程退出动作。
func _confirm_exit() -> void:
	_exit_confirmed = true


## 等待真实会话状态变化，超时立即报错，防止停在默认大厅时被误认为成功。
## [param predicate] 需要满足的可观察状态。[param timeout] 最长等待秒数。
## 返回是否在期限内满足条件。
func _wait_for(predicate: Callable, timeout: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(timeout * 1000)
	while not predicate.call():
		if Time.get_ticks_msec() >= deadline:
			_fail("地图实测等待超时，请检查 engine.log")
			return false
		await process_frame
	return true


## 输出可诊断失败并终止当前独立测试进程。
## [param message] 初始化或实测失败原因。
func _fail(message: String) -> void:
	push_error(message)
	quit(1)
