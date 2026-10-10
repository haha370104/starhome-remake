extends Node2D

const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const NPC_CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const MAP_DEFINITION_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

# 本地人物移动与动画配置独立于 NPC 巡逻。
@export_range(1.0, 600.0, 1.0) var player_movement_speed := 203.0
@export_range(0.1, 4.0, 0.05) var player_animation_speed_scale := 1.0

@export_category("Multiplayer")
@export var multiplayer_offline_debug_enabled := true
@export var multiplayer_connect_automatically := true
@export var multiplayer_server_host := "127.0.0.1"
@export_range(1, 65535, 1) var multiplayer_server_port := ClientNetworkAdapter.DEFAULT_PORT
@export var multiplayer_local_entity_id: StringName = &"player.local"
@export var multiplayer_map_instance_id := "yian_harbor_hall_floor_1.instance.1"

@export_category("Login")
@export var login_human_display_name := "玩家1"
@export var login_llm_display_name := "Riko"
@export var login_llm_actor_id := "llm.player2"

var interactions := WorldInteractionController.new()
var player_binding := PlayerPresentationBinding.new()
var combat := CombatInteractionController.new()
var settings_controller := ClientSettingsController.new()
var audio: ClientAudioController
var map_travel := MapTravelController.new()
var world_view: ClientWorldView
var character_catalog: Dictionary
var npc_catalog: Dictionary
var active_world_controller: ActiveWorldController

var local_player_controller: LocalPlayerController

var hud: HallHud
var multiplayer_presenter: HallMultiplayerPresenter
var map_preloader: ClientMapPreloader
var map_route_resolver: RuntimeMapRouteResolver
var panel_session: PlayerPanelSession
var game_window_manager: GameWindowManager
var exit_controller := ClientExitController.new()
var initial_loading_screen: CanvasLayer
var player_login_screen: PlayerLoginScreen
var _startup_started_at_usec := 0
var _game_initialization_started := false
var _llm_login_requested := false
var _llm_spawn_completed := false
var _initial_map_ready := false


## 节点进入场景树后初始化运行依赖。
func _ready() -> void:
	_startup_started_at_usec = Time.get_ticks_usec()
	if get_tree().current_scene == self:
		var telemetry_lifecycle := get_node_or_null("/root/PerformanceTelemetryLifecycle")
		if telemetry_lifecycle != null:
			_startup_started_at_usec = int(
				telemetry_lifecycle.call("take_client_startup_started_at_usec")
			)
	_apply_multiplayer_command_line(OS.get_cmdline_user_args())
	add_child(map_travel)
	add_child(combat)
	add_child(interactions)
	add_child(exit_controller)
	add_child(settings_controller)
	_build_player_login_screen()
	if get_tree().current_scene != self:
		call_deferred("_on_login_requested", false)


## 创建首屏登录选择；地图和网络会话在用户确认后才开始初始化。
func _build_player_login_screen() -> void:
	player_login_screen = PlayerLoginScreen.new()
	player_login_screen.name = "PlayerLoginScreen"
	add_child(player_login_screen)
	player_login_screen.configure(login_human_display_name, login_llm_display_name)
	player_login_screen.login_requested.connect(_on_login_requested)


## 接受角色选择后才进入地图、会话和可选 LLM 玩家初始化阶段。
func _on_login_requested(include_llm: bool) -> void:
	if _game_initialization_started:
		return
	_game_initialization_started = true
	_llm_login_requested = include_llm
	player_login_screen.set_busy("正在准备游戏资源")
	call_deferred("_initialize_game_after_login")


## 登录界面已经让出主线程后，构造实际游戏世界。
func _initialize_game_after_login() -> void:
	_build_initial_loading_screen()
	player_login_screen.visible = false
	var phase_started_at := PerformanceTelemetryScript.begin(&"client_startup_runtime_content")
	var content_result: Dictionary = RuntimeContentBootstrap.mount_default()
	if not bool(content_result.get("ok", false)):
		_login_initialization_failed("无法读取游戏资源：%s" % content_result.get("message", ""))
		return
	PerformanceTelemetryScript.end(&"client_startup_runtime_content", phase_started_at)
	phase_started_at = PerformanceTelemetryScript.begin(&"client_startup_content_catalogs")
	ItemPresentationTextureResolver.prepare()
	character_catalog = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	npc_catalog = JSON.parse_string(FileAccess.get_file_as_string(NPC_CONFIG_PATH))
	PerformanceTelemetryScript.end(&"client_startup_content_catalogs", phase_started_at)
	active_world_controller = ActiveWorldController.new()
	active_world_controller.name = "ActiveWorldController"
	active_world_controller.active_world_will_replace.connect(interactions.clear_interaction)
	add_child(active_world_controller)
	phase_started_at = PerformanceTelemetryScript.begin(&"client_startup_initial_map_bundle")
	var initial_bundle: Dictionary = active_world_controller.prepare_initial_bundle(MAP_DEFINITION_PATH)
	if initial_bundle.is_empty():
		_login_initialization_failed("无法准备初始地图")
		return
	PerformanceTelemetryScript.end(&"client_startup_initial_map_bundle", phase_started_at)
	world_view = ClientWorldView.new()
	add_child(world_view)
	phase_started_at = PerformanceTelemetryScript.begin(&"client_startup_world_view")
	world_view.configure(character_catalog, player_animation_speed_scale)
	PerformanceTelemetryScript.end(&"client_startup_world_view", phase_started_at)
	local_player_controller = LocalPlayerController.new()
	add_child(local_player_controller)
	local_player_controller.configure(world_view.player, DiamondNavigation.new(), player_movement_speed, Vector2.ZERO)
	local_player_controller.position_changed.connect(player_binding.sync_position)
	local_player_controller.route_finished.connect(map_travel.try_begin_nearby_map_transition)
	local_player_controller.route_stopped.connect(interactions.on_local_player_route_stopped)
	_build_hud(initial_bundle)
	player_binding.configure(world_view, local_player_controller, active_world_controller, hud, character_catalog)
	interactions.configure(world_view, active_world_controller, local_player_controller, hud, map_travel, combat)
	active_world_controller.active_world_will_replace.connect(world_view.clear_map_effects)
	phase_started_at = PerformanceTelemetryScript.begin(&"client_startup_world_binding")
	var configure_error: Error = active_world_controller.configure(
		world_view,
		world_view.sortable_world,
		world_view.map_background,
		world_view.player,
		local_player_controller,
		world_view.camera,
		hud,
		character_catalog,
		npc_catalog,
		world_view.item_catalog,
	)
	if configure_error != OK:
		_login_initialization_failed("无法配置游戏世界：%s" % error_string(configure_error))
		return
	var initial_definition: MapDefinition = initial_bundle["definition"]
	var initial_spawn: MapSpawnPoint = initial_definition.spawn_by_id(initial_definition.default_spawn_id)
	if initial_spawn == null or not active_world_controller.commit_bundle(initial_bundle, initial_spawn.position):
		_login_initialization_failed("无法提交初始地图")
		return
	PerformanceTelemetryScript.end(&"client_startup_world_binding", phase_started_at)
	phase_started_at = PerformanceTelemetryScript.begin(&"client_startup_presentation_setup")
	_build_multiplayer_presentation()
	PerformanceTelemetryScript.end(&"client_startup_presentation_setup", phase_started_at)
	local_player_controller.set_character_action("stand")
	player_binding.sync_position(world_view.player.position)
	if not multiplayer_connect_automatically:
		map_travel.finish_initial_loading()
		_initial_map_ready = true
		_llm_spawn_completed = true
		_finish_login()


## 初始化失败时保留登录界面，避免把半初始化的世界当作已登录状态。
func _login_initialization_failed(message: String) -> void:
	push_error(message)
	if initial_loading_screen != null:
		initial_loading_screen.visible = false
	if player_login_screen != null:
		player_login_screen.visible = true
		player_login_screen.show_error(message)
	_game_initialization_started = false


## 创建启动遮罩，阻止默认大厅在持久化角色地图尚未恢复时提前露出。
func _build_initial_loading_screen() -> void:
	if initial_loading_screen != null:
		initial_loading_screen.show_loading("正在读取角色与地图数据")
		return
	initial_loading_screen = InitialLoadingScreen.new()
	initial_loading_screen.name = "InitialLoadingScreen"
	add_child(initial_loading_screen)
	initial_loading_screen.visibility_changed.connect(_on_initial_loading_visibility_changed)
	initial_loading_screen.show_loading("正在读取角色与地图数据")


## 记录启动关键路径到地图和角色就绪、加载遮罩消失的总耗时。
func _on_initial_loading_visibility_changed() -> void:
	if initial_loading_screen.visible or _startup_started_at_usec <= 0:
		return
	PerformanceTelemetryScript.record_duration(
		&"client_startup_to_ready", Time.get_ticks_usec() - _startup_started_at_usec
	)
	_startup_started_at_usec = 0


## 以命令行覆盖编辑器的运行模式与连接配置。
## [param arguments] 用户传给游戏进程的参数列表。
## 设计：编辑器默认保持离线调试；正式联机必须显式传入 `--online`，避免无服务器时影响美术预览。
func _apply_multiplayer_command_line(arguments: PackedStringArray) -> void:
	for argument in arguments:
		if argument == "--online":
			multiplayer_offline_debug_enabled = false
		elif argument == "--offline-debug":
			multiplayer_offline_debug_enabled = true
		elif argument == "--no-auto-connect":
			multiplayer_connect_automatically = false
		elif argument.begins_with("--server-host="):
			multiplayer_server_host = argument.trim_prefix("--server-host=")
		elif argument.begins_with("--server-port="):
			var requested_port := int(argument.trim_prefix("--server-port="))
			if requested_port >= 1 and requested_port <= 65535:
				multiplayer_server_port = requested_port


## 按渲染帧推进当前节点的表现状态。
## [param delta] 本次渲染帧经过的秒数，仅推进本地表现。
func _process(delta: float) -> void:
	if local_player_controller:
		local_player_controller.advance(delta)
		if audio != null:
			audio.set_moving(local_player_controller.has_active_route())


## 创建地图 HUD、业务信号连接及战车击毁对话框。
## [param initial_bundle] 初始地图已验证的定义和资源，用于构造 HUD。
func _build_hud(initial_bundle: Dictionary) -> void:
	var initial_definition: MapDefinition = initial_bundle["definition"]
	var initial_resources: Dictionary = initial_bundle["resources"]
	hud = HallHud.new()
	hud.configure(
		initial_definition.world_size,
		initial_resources["minimap"],
		String(initial_definition.display_name),
	)
	add_child(hud)
	hud.popup_closed.connect(interactions.on_npc_popup_closed)
	hud.npc_action_requested.connect(interactions.on_npc_action_requested)
	hud.player_action_requested.connect(interactions.on_player_action_requested)
	hud.hud_action_requested.connect(interactions.on_hud_action_requested)
	combat.configure(world_view, local_player_controller, hud, map_travel)
	combat.vehicle_destroyed_dialog = VehicleDestroyedDialog.new()
	combat.vehicle_destroyed_dialog.configure()
	combat.vehicle_destroyed_dialog.wait_selected.connect(combat.on_destroyed_wait_selected)
	combat.vehicle_destroyed_dialog.return_to_base_requested.connect(combat.request_vehicle_recovery)
	hud.add_overlay(combat.vehicle_destroyed_dialog)


## 创建大厅客户端会话表现器，并以显式配置选择离线调试或真实网络入口。
## 设计：先连接全部状态订阅者再启动会话，允许进程内传输同步回调。
func _build_multiplayer_presentation() -> void:
	map_preloader = ClientMapPreloader.new()
	map_preloader.name = "ClientMapPreloader"
	var map_definition_paths := _load_map_directory_definitions()
	map_preloader.configure(map_definition_paths)
	map_preloader.map_preload_ready.connect(map_travel.on_map_preload_ready)
	map_preloader.map_preload_failed.connect(map_travel.on_map_preload_failed)
	add_child(map_preloader)
	map_route_resolver = RuntimeMapRouteResolver.new()
	if not map_route_resolver.configure(map_definition_paths):
		push_error("Unable to configure runtime map routes: %s" % "; ".join(
			map_route_resolver.errors
		))

	multiplayer_presenter = HallMultiplayerPresenter.new()
	multiplayer_presenter.name = "HallMultiplayerPresenter"
	multiplayer_presenter.configure(world_view.player, world_view.sortable_world, character_catalog, world_view.item_catalog)
	multiplayer_presenter.network_notice_requested.connect(hud.show_network_notice)
	multiplayer_presenter.local_character_state_applied.connect(
		local_player_controller.apply_authoritative_presentation
	)
	multiplayer_presenter.map_joined.connect(map_travel.on_authoritative_map_joined)
	multiplayer_presenter.map_joined.connect(_on_login_map_joined)
	multiplayer_presenter.connection_failed.connect(map_travel.on_initial_connection_failed)
	multiplayer_presenter.map_change_failed.connect(map_travel.on_authoritative_map_change_failed)
	multiplayer_presenter.combat_snapshot_received.connect(combat.on_combat_snapshot_received)
	multiplayer_presenter.combat_event_received.connect(combat.on_combat_event_received)
	multiplayer_presenter.vehicle_recovery_scheduled.connect(
		combat.on_vehicle_recovery_scheduled
	)
	multiplayer_presenter.vehicle_recovery_failed.connect(combat.on_vehicle_recovery_failed)
	multiplayer_presenter.system_message_requested.connect(hud.show_system_message)
	add_child(multiplayer_presenter)
	map_travel.configure(active_world_controller, local_player_controller, world_view.player, hud)
	map_travel.bind_session(multiplayer_presenter, map_preloader, map_route_resolver, initial_loading_screen)
	map_travel.multiplayer_map_instance_id = multiplayer_map_instance_id
	map_travel.map_committed.connect(player_binding.refresh_local_movement_availability)
	map_travel.map_committed.connect(_on_login_map_committed)
	_build_game_windows()
	multiplayer_presenter.combat_snapshot_received.connect(
		game_window_manager.vehicle_panel.apply_combat_snapshot
	)
	multiplayer_presenter.synchronization_started.connect(panel_session.begin_sync)
	multiplayer_presenter.synchronization_started.connect(game_window_manager.request_social_sync)
	multiplayer_presenter.synchronization_started.connect(_on_local_session_synchronized)
	multiplayer_presenter.player_change_received.connect(panel_session.apply_change)
	panel_session.attributes_changed.connect(player_binding.refresh_local_movement_availability)
	combat.bind_session(multiplayer_presenter, panel_session)
	interactions.bind_player_windows(game_window_manager)
	map_travel.map_committed.connect(interactions.refresh_garden)
	exit_controller.configure(multiplayer_presenter, panel_session, combat, game_window_manager.navigation_windows["system"])
	settings_controller.configure(game_window_manager, hud, interactions)
	audio = ClientAudioController.new()
	audio.name = "ClientAudioController"
	add_child(audio)
	audio.configure(world_view.player)
	game_window_manager.slot_machine_window.effect_requested.connect(audio.play_effect)
	audio.connect_ui_buttons()
	multiplayer_presenter.combat_snapshot_received.connect(audio.on_combat_snapshot)
	multiplayer_presenter.combat_event_received.connect(audio.on_combat_event)
	multiplayer_presenter.skill_level_up_received.connect(audio.on_skill_level_up)
	panel_session.player_changed.connect(audio.on_player_changed)
	panel_session.equipment_changed.connect(audio.on_player_changed)
	map_travel.map_committed.connect(_sync_audio_map)
	local_player_controller.set_multiplayer_presenter(multiplayer_presenter)
	var start_error: Error = multiplayer_presenter.start({
		"offline_debug_enabled": multiplayer_offline_debug_enabled,
		"connect_automatically": multiplayer_connect_automatically,
		"server_host": multiplayer_server_host,
		"server_port": multiplayer_server_port,
		"local_entity_id": multiplayer_local_entity_id,
		"local_display_name": login_human_display_name,
		"map_id": active_world_controller.definition.map_id,
		"map_instance_id": multiplayer_map_instance_id,
		"initial_position": world_view.player.position,
		"remote_appearance": "player",
		"remote_animation_speed_scale": player_animation_speed_scale,
	})
	if start_error != OK:
		var message := multiplayer_presenter.last_connection_error_message
		if message.is_empty():
			message = error_string(start_error)
			map_travel.on_initial_connection_failed(message)
		push_warning("Unable to start hall multiplayer presentation: %s" % message)
	_sync_audio_map()


## 在已提交地图上选择原客户端指定的配乐。
func _sync_audio_map() -> void:
	if audio != null and active_world_controller != null:
		audio.set_map(active_world_controller.definition)


## 当前权威会话已完成初始握手；此时进程内服务器才允许生成 LLM 玩家。
func _on_local_session_synchronized(_sync_id: String) -> void:
	if not _llm_login_requested or _llm_spawn_completed:
		_llm_spawn_completed = true
		_finish_login()
		return
	_spawn_selected_llm_player()


## 在普通玩家初始地图提交后标记地图就绪；跨地图恢复会由 map_committed 标记。
func _on_login_map_joined(map_id: StringName, _map_instance_id: String, _spawn_position: Vector2, _definition_version: int) -> void:
	if active_world_controller != null and active_world_controller.definition.map_id == map_id:
		_initial_map_ready = true
		_finish_login()


## 地图资源异步预载完成并提交后，允许关闭登录加载遮罩。
func _on_login_map_committed() -> void:
	_initial_map_ready = true
	_finish_login()


## 仅在进程内权威服务器中创建客户端勾选的独立 LLM 玩家。
func _spawn_selected_llm_player() -> void:
	if not multiplayer_offline_debug_enabled:
		initial_loading_screen.set_status("联机模式下 LLM 玩家需要由权威服务器启动")
		_llm_spawn_completed = true
		_finish_login()
		return
	var server: Node = multiplayer_presenter.session.network_adapter.in_process_authoritative_server()
	if server == null:
		initial_loading_screen.set_status("未找到进程内权威服务器，LLM 玩家未上线")
		_llm_spawn_completed = true
		_finish_login()
		return
	var provider_result = server.call("create_openai_llm_provider")
	if not provider_result.is_ok:
		initial_loading_screen.set_status("LLM 玩家未上线：%s" % provider_result.error_message)
		_llm_spawn_completed = true
		_finish_login()
		return
	var controller := LlmPlayerController.new()
	var spawned = server.call(
		"spawn_llm_player",
		login_llm_actor_id,
		controller,
		Callable(server, "resolve_llm_area"),
		provider_result.value,
		login_llm_display_name,
	)
	if not spawned.is_ok:
		initial_loading_screen.set_status("LLM 玩家未上线：%s" % spawned.error_message)
		_llm_spawn_completed = true
		_finish_login()
		return
	_llm_spawn_completed = true
	initial_loading_screen.set_status("LLM 玩家已上线，正在进入游戏")
	_finish_login()


## 地图和可选 LLM 都就绪后关闭登录遮罩，进入可操作大厅。
func _finish_login() -> void:
	if not _initial_map_ready or not _llm_spawn_completed:
		return
	if initial_loading_screen != null:
		initial_loading_screen.finish_loading()


## 创建人物、背包和战车单例窗口并接入唯一客户端会话。
## 设计：窗口不知道底层是 ENet 还是进程内传输，只消费相同的权威面板消息。
func _build_game_windows() -> void:
	game_window_manager = GameWindowManager.new()
	game_window_manager.name = "GameWindowManager"
	hud.add_overlay(game_window_manager)
	game_window_manager.notice_requested.connect(hud.show_system_message)
	panel_session = PlayerPanelSession.new(
		Callable(multiplayer_presenter, "request_player_panel_command"),
		world_view.item_catalog,
	)
	multiplayer_presenter.player_panel_bundle_received.connect(
		panel_session.apply_bundle
	)
	panel_session.player_changed.connect(player_binding.on_current_player_changed)
	panel_session.equipment_changed.connect(player_binding.on_current_player_changed)
	game_window_manager.configure(panel_session)
	game_window_manager.social_command_requested.connect(multiplayer_presenter.request_social_command)
	multiplayer_presenter.social_event_received.connect(game_window_manager.apply_social_event)
	player_binding.panel_session = panel_session
	multiplayer_presenter.skill_level_up_received.connect(player_binding.on_skill_level_up)


## 读取受控地图目录的 `definitions` 映射，格式错误时返回仅包含当前大厅的安全目录。
## 返回业务地图 ID 到受控定义路径的映射。
## 设计：网络消息不能提供资源路径；所有预载目标必须先存在于版本化目录。
func _load_map_directory_definitions() -> Dictionary:
	var fallback := {StringName(active_world_controller.definition.map_id): MAP_DEFINITION_PATH}
	if not FileAccess.file_exists(MAP_DIRECTORY_PATH):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY_PATH))
	if not parsed is Dictionary or not parsed.get("definitions", {}) is Dictionary:
		return fallback
	return parsed["definitions"].duplicate(true)
