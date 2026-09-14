extends Node2D

const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const NPC_CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const MAP_DEFINITION_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"

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
@export_range(1.0, 200.0, 1.0) var map_transition_trigger_radius := 64.0

var interactions := WorldInteractionController.new()
var player_binding := PlayerPresentationBinding.new()
var combat := CombatInteractionController.new()
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
var initial_loading_screen: CanvasLayer


## 节点进入场景树后初始化运行依赖。
func _ready() -> void:
	_apply_multiplayer_command_line(OS.get_cmdline_user_args())
	add_child(map_travel)
	add_child(combat)
	add_child(interactions)
	_build_initial_loading_screen()
	var content_result: Dictionary = RuntimeContentBootstrap.mount_default()
	if not bool(content_result.get("ok", false)):
		push_error("Unable to mount Glory runtime content: %s" % content_result.get("message", ""))
		return
	character_catalog = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	npc_catalog = JSON.parse_string(FileAccess.get_file_as_string(NPC_CONFIG_PATH))
	active_world_controller = ActiveWorldController.new()
	active_world_controller.name = "ActiveWorldController"
	active_world_controller.active_world_will_replace.connect(interactions.clear_interaction)
	add_child(active_world_controller)
	var initial_bundle: Dictionary = active_world_controller.prepare_initial_bundle(MAP_DEFINITION_PATH)
	if initial_bundle.is_empty():
		push_error("Unable to prepare initial map bundle")
		return
	world_view = ClientWorldView.new()
	add_child(world_view)
	world_view.configure(character_catalog, player_animation_speed_scale)
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
	)
	if configure_error != OK:
		push_error("Unable to configure active world: %s" % error_string(configure_error))
		return
	var initial_definition: MapDefinition = initial_bundle["definition"]
	var initial_spawn: MapSpawnPoint = initial_definition.spawn_by_id(initial_definition.default_spawn_id)
	if initial_spawn == null or not active_world_controller.commit_bundle(initial_bundle, initial_spawn.position):
		push_error("Unable to commit initial map bundle")
		return
	_build_multiplayer_presentation()
	local_player_controller.set_character_action("stand")
	player_binding.sync_position(world_view.player.position)
	if not multiplayer_connect_automatically:
		map_travel.finish_initial_loading()


## 创建启动遮罩，阻止默认大厅在持久化角色地图尚未恢复时提前露出。
func _build_initial_loading_screen() -> void:
	initial_loading_screen = InitialLoadingScreen.new()
	initial_loading_screen.name = "InitialLoadingScreen"
	add_child(initial_loading_screen)
	initial_loading_screen.show_loading("正在读取角色与地图数据")


## 执行 `apply_multiplayer_command_line` 对应的模块操作。
## [param arguments] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	if local_player_controller:
		local_player_controller.advance(delta)


## 执行 `build_hud` 对应的模块操作。
## [param initial_bundle] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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
	hud.hud_action_requested.connect(interactions.on_hud_action_requested)
	combat.configure(world_view, local_player_controller, hud, map_travel)
	hud.selected_action_changed.connect(combat.on_weapon_slot_selected)
	combat.on_weapon_slot_selected(hud.selected_action())
	combat.vehicle_destroyed_dialog = VehicleDestroyedDialog.new()
	combat.vehicle_destroyed_dialog.configure()
	combat.vehicle_destroyed_dialog.wait_selected.connect(combat.on_destroyed_wait_selected)
	combat.vehicle_destroyed_dialog.return_to_base_requested.connect(combat.request_vehicle_recovery)
	hud.add_overlay(combat.vehicle_destroyed_dialog)


## 创建大厅客户端会话表现器，并以显式配置选择离线调试或真实网络入口。
## 设计：大厅保留输入、导航与动画职责；表现器仅将预测/权威状态投影到角色节点。
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
	multiplayer_presenter.configure(world_view.player, world_view.sortable_world, character_catalog)
	multiplayer_presenter.network_notice_requested.connect(hud.show_network_notice)
	multiplayer_presenter.local_character_state_applied.connect(
		local_player_controller.apply_authoritative_presentation
	)
	multiplayer_presenter.map_joined.connect(map_travel.on_authoritative_map_joined)
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
	map_travel.map_transition_trigger_radius = map_transition_trigger_radius
	map_travel.map_committed.connect(player_binding.refresh_local_movement_availability)
	_build_game_windows()
	combat.bind_session(multiplayer_presenter, panel_session)
	local_player_controller.set_multiplayer_presenter(multiplayer_presenter)
	var start_error: Error = multiplayer_presenter.start({
		"offline_debug_enabled": multiplayer_offline_debug_enabled,
		"connect_automatically": multiplayer_connect_automatically,
		"server_host": multiplayer_server_host,
		"server_port": multiplayer_server_port,
		"local_entity_id": multiplayer_local_entity_id,
		"map_id": active_world_controller.definition.map_id,
		"map_instance_id": multiplayer_map_instance_id,
		"initial_position": world_view.player.position,
		"remote_appearance": "player",
		"remote_animation_speed_scale": player_animation_speed_scale,
	})
	if start_error != OK:
		push_warning("Unable to start hall multiplayer presentation: %s" % error_string(start_error))
		map_travel.on_initial_connection_failed(error_string(start_error))


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
	game_window_manager.configure(panel_session)
	player_binding.panel_session = panel_session
	interactions.game_window_manager = game_window_manager
	multiplayer_presenter.skill_level_up_received.connect(player_binding.on_skill_level_up)


## 读取受控地图目录的 `definitions` 映射，格式错误时返回仅包含当前大厅的安全目录。
## 返回该函数计算、查询或操作得到的结果。
## 设计：网络消息不能提供资源路径；所有预载目标必须先存在于版本化目录。
func _load_map_directory_definitions() -> Dictionary:
	var fallback := {StringName(active_world_controller.definition.map_id): MAP_DEFINITION_PATH}
	if not FileAccess.file_exists(MAP_DIRECTORY_PATH):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY_PATH))
	if not parsed is Dictionary or not parsed.get("definitions", {}) is Dictionary:
		return fallback
	return parsed["definitions"].duplicate(true)
