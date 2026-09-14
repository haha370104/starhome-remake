extends Node2D

const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const NPC_CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const MAP_DEFINITION_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/glory_map_directory_v1.json"
const RuntimeContentBootstrapScript := preload(
	"res://scripts/content/runtime_content_bootstrap.gd"
)
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const HallHudScript := preload("res://scripts/ui/hall_hud.gd")
const HallMultiplayerPresenterScript := preload(
	"res://scripts/client/presentation/hall_multiplayer_presenter.gd"
)
const ClientMapPreloaderScript := preload(
	"res://scripts/client/presentation/client_map_preloader.gd"
)
const RuntimeMapRouteResolverScript := preload(
	"res://scripts/maps/runtime_map_route_resolver.gd"
)
const LocalPlayerControllerScript := preload(
	"res://scripts/client/gameplay/local_player_controller.gd"
)
const ActiveWorldControllerScript := preload(
	"res://scripts/client/world/active_world_controller.gd"
)
const GameWindowManagerScript := preload(
	"res://scripts/client/ui/windows/game_window_manager.gd"
)
const InitialLoadingScreenScript := preload(
	"res://scripts/client/ui/initial_loading_screen.gd"
)
const VehicleDestroyedDialogScript := preload(
	"res://scripts/ui/vehicle_destroyed_dialog.gd"
)
const CombatActions := preload("res://scripts/client/gameplay/client_combat_actions.gd")
const TACTICAL_ACTION_BY_DEFINITION := {
	"starter_rocket_launcher": "rocket_launcher",
	"starter_missile": "missile",
}

# Player tuning is intentionally local to the world_view.player. NPC patrol motion has its
# own configuration and must not inherit these values when world_view.player progression,
# equipment or accessibility settings change them later.
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

var combat := CombatInteractionController.new()
var map_travel := MapTravelController.new()
var world_view: ClientWorldView
var character_catalog: Dictionary
var npc_catalog: Dictionary
var active_world_controller: Node

# Public aliases delegate to ActiveWorldController so map diagnostics keep a
# stable surface without creating a second owner for activity state.
var map_manifest: Dictionary:
	get:
		return active_world_controller.map_manifest if active_world_controller else {}
var map_definition: RefCounted:
	get:
		return active_world_controller.definition if active_world_controller else null
var map_size: Vector2:
	get:
		return active_world_controller.map_size if active_world_controller else Vector2.ZERO
var navigation: RefCounted:
	get:
		return active_world_controller.navigation if active_world_controller else null
var nav_data: PackedByteArray:
	get:
		return navigation.data if navigation else PackedByteArray()
var nav_grid: AStar2D:
	get:
		return navigation.graph if navigation else null
var local_player_controller: Node

# Diagnostic compatibility properties expose the controller's one true state
# to existing validation fixtures without retaining a second route model here.
var path_points: PackedVector2Array:
	get:
		return local_player_controller.path_points if local_player_controller else PackedVector2Array()
	set(value):
		if local_player_controller:
			local_player_controller.path_points = value
var path_index: int:
	get:
		return local_player_controller.path_index if local_player_controller else 0
	set(value):
		if local_player_controller:
			local_player_controller.path_index = value
var current_direction: int:
	get:
		return local_player_controller.current_direction if local_player_controller else 6
	set(value):
		if local_player_controller:
			local_player_controller.current_direction = value

var map_scene_nodes: Array[Node2D]:
	get:
		return active_world_controller.scene_nodes if active_world_controller else []
var npc_instances: Array[Node2D]:
	get:
		return active_world_controller.npc_instances if active_world_controller else []
var facility_instances: Array[Node2D]:
	get:
		return active_world_controller.facility_instances if active_world_controller else []
var active_npc: Node2D
var hud: CanvasLayer
var multiplayer_presenter: Node
var map_preloader: Node
var map_route_resolver: RefCounted
var active_movement_input_sequence: int:
	get:
		return local_player_controller.active_movement_input_sequence if local_player_controller else 0
	set(value):
		if local_player_controller:
			local_player_controller.active_movement_input_sequence = value
var transition_choice_ids: Dictionary = {}
var panel_session: PlayerPanelSession
var game_window_manager: GameWindowManager
var initial_loading_screen: CanvasLayer


## 节点进入场景树后初始化运行依赖。
func _ready() -> void:
	_apply_multiplayer_command_line(OS.get_cmdline_user_args())
	add_child(map_travel)
	add_child(combat)
	_build_initial_loading_screen()
	var content_result: Dictionary = RuntimeContentBootstrapScript.mount_default()
	if not bool(content_result.get("ok", false)):
		push_error("Unable to mount Glory runtime content: %s" % content_result.get("message", ""))
		return
	character_catalog = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	npc_catalog = JSON.parse_string(FileAccess.get_file_as_string(NPC_CONFIG_PATH))
	active_world_controller = ActiveWorldControllerScript.new()
	active_world_controller.name = "ActiveWorldController"
	active_world_controller.active_world_will_replace.connect(_on_active_world_will_replace)
	add_child(active_world_controller)
	var initial_bundle: Dictionary = active_world_controller.prepare_initial_bundle(MAP_DEFINITION_PATH)
	if initial_bundle.is_empty():
		push_error("Unable to prepare initial map bundle")
		return
	world_view = ClientWorldView.new()
	add_child(world_view)
	world_view.configure(character_catalog, player_animation_speed_scale)
	local_player_controller = LocalPlayerControllerScript.new()
	add_child(local_player_controller)
	local_player_controller.configure(world_view.player, DiamondNavigationScript.new(), player_movement_speed, Vector2.ZERO)
	local_player_controller.position_changed.connect(_on_local_player_position_changed)
	local_player_controller.route_finished.connect(_on_local_player_route_finished)
	local_player_controller.route_stopped.connect(_on_local_player_route_stopped)
	_build_hud(initial_bundle)
	var configure_error: Error = active_world_controller.configure(
		self,
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
	_set_player_action("stand")
	_sync_player_nodes()
	if not multiplayer_connect_automatically:
		map_travel.finish_initial_loading()


## 创建启动遮罩，阻止默认大厅在持久化角色地图尚未恢复时提前露出。
func _build_initial_loading_screen() -> void:
	initial_loading_screen = InitialLoadingScreenScript.new()
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


## 接收并分发当前节点负责的输入事件。
## [param event] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo and key_event.keycode == KEY_Z:
			combat.request_self_repair()
			get_viewport().set_input_as_handled()
		return
	if not event is InputEventMouseButton or not event.pressed:
		return
	if combat.is_input_locked():
		get_viewport().set_input_as_handled()
		return
	var mouse_event := event as InputEventMouseButton
	var world_position := get_global_mouse_position()
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_handle_world_right_click(world_position)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var npc := _nearest_npc(world_position, 55.0)
		if npc:
			_show_npc_popup(npc)
		elif world_view.player != null and world_view.player.is_combat_actor_active():
			combat.handle_world_combat_left_click(world_position)
		else:
			hud.hide_popup()
		get_viewport().set_input_as_handled()


## 执行 `handle_world_right_click` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：先在实际点击点播放原版反馈；图标锚点仅用于命中，不能替代可行走接近点。
func _handle_world_right_click(world_position: Vector2) -> void:
	world_view.movement_click_effects.present(world_position)
	var transition_view: Node2D = active_world_controller.transition_view_at(world_position)
	if transition_view != null:
		var transition: MapTransition = map_definition.transition_by_id(transition_view.transition_id)
		if transition != null and transition.kind == MapTransition.Kind.MULTI_CHOICE:
			_show_transition_choices(transition, world_position)
			return
		_move_to(transition_view.approach_point, transition_view.transition_id)
	else:
		_move_to(world_position)


## 执行 `move_to` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _move_to(world_position: Vector2, transition_id: StringName = &"") -> void:
	if combat.is_input_locked():
		map_travel.stop_moving("地图切换中，暂时不能移动")
		return
	map_travel.selected_transition_id = &""
	var target_text := "%d, %d" % [roundi(world_position.x), roundi(world_position.y)]
	var result: Dictionary = local_player_controller.request_move(world_position)
	if not bool(result.get("ok", false)):
		var error_code := StringName(result.get("code", &""))
		if error_code == &"movement.no_propulsion":
			var error_message := PlayerErrorMessages.describe(error_code)
			hud.show_status(error_message)
			hud.show_system_message(error_message)
		elif error_code == &"no_reachable_point":
			hud.show_status("目标 %s 不可到达，附近也没有可达点" % target_text)
		else:
			hud.show_status("无法找到前往 %s 的路径" % target_text)
		return
	var resolved_position: Vector2 = result["resolved_position"]
	map_travel.selected_transition_id = transition_id
	if bool(result["used_nearest_walkable"]):
		hud.show_status("目标 %s 不可到达，正在前往附近 %d, %d" % [
			target_text,
			roundi(resolved_position.x),
			roundi(resolved_position.y),
		])
	else:
		hud.show_status("正在前往 %s" % target_text)
	hud.hide_popup()


## 执行 `begin_current_path_segment` 对应的模块操作。
func _begin_current_path_segment() -> void:
	if local_player_controller:
		local_player_controller.refresh_route_direction()


## 执行 `direction_index` 对应的模块操作。
## [param motion] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _direction_index(motion: Vector2) -> int:
	return LocalPlayerControllerScript.direction_index(motion)


## 设置或恢复 `set_player_action` 对应的模块状态。
## [param action] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _set_player_action(action: String) -> void:
	if local_player_controller:
		local_player_controller.set_character_action(StringName(action))


## 执行 `sync_player_nodes` 对应的模块操作。
func _sync_player_nodes() -> void:
	if not world_view.player:
		return
	world_view.camera.position = world_view.player.position
	_update_minimap_dot()


## 执行 `build_hud` 对应的模块操作。
## [param initial_bundle] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _build_hud(initial_bundle: Dictionary) -> void:
	var initial_definition: MapDefinition = initial_bundle["definition"]
	var initial_resources: Dictionary = initial_bundle["resources"]
	hud = HallHudScript.new()
	hud.configure(
		initial_definition.world_size,
		initial_resources["minimap"],
		String(initial_definition.display_name),
	)
	add_child(hud)
	hud.popup_closed.connect(_on_npc_popup_closed)
	hud.npc_action_requested.connect(_on_npc_action_requested)
	hud.hud_action_requested.connect(_on_hud_action_requested)
	combat.configure(world_view, local_player_controller, hud, map_travel)
	hud.selected_action_changed.connect(combat.on_weapon_slot_selected)
	combat.on_weapon_slot_selected(hud.selected_action())
	combat.vehicle_destroyed_dialog = VehicleDestroyedDialogScript.new()
	combat.vehicle_destroyed_dialog.configure()
	combat.vehicle_destroyed_dialog.wait_selected.connect(combat.on_destroyed_wait_selected)
	combat.vehicle_destroyed_dialog.return_to_base_requested.connect(combat.request_vehicle_recovery)
	hud.add_overlay(combat.vehicle_destroyed_dialog)


## 创建大厅客户端会话表现器，并以显式配置选择离线调试或真实网络入口。
## 设计：大厅保留输入、导航与动画职责；表现器仅将预测/权威状态投影到角色节点。
func _build_multiplayer_presentation() -> void:

	map_preloader = ClientMapPreloaderScript.new()
	map_preloader.name = "ClientMapPreloader"
	var map_definition_paths := _load_map_directory_definitions()
	map_preloader.configure(map_definition_paths)
	map_preloader.map_preload_ready.connect(map_travel.on_map_preload_ready)
	map_preloader.map_preload_failed.connect(map_travel.on_map_preload_failed)
	add_child(map_preloader)
	map_route_resolver = RuntimeMapRouteResolverScript.new()
	if not map_route_resolver.configure(map_definition_paths):
		push_error("Unable to configure runtime map routes: %s" % "; ".join(
			map_route_resolver.errors
		))

	multiplayer_presenter = HallMultiplayerPresenterScript.new()
	multiplayer_presenter.name = "HallMultiplayerPresenter"
	multiplayer_presenter.configure(world_view.player, world_view.sortable_world, character_catalog)
	multiplayer_presenter.network_notice_requested.connect(hud.show_network_notice)
	multiplayer_presenter.local_character_state_applied.connect(
		_on_multiplayer_local_character_state_applied
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
	map_travel.map_committed.connect(_refresh_local_movement_availability)
	_build_game_windows()
	combat.bind_session(multiplayer_presenter, panel_session)
	local_player_controller.set_multiplayer_presenter(multiplayer_presenter)
	var start_error: Error = multiplayer_presenter.start({
		"offline_debug_enabled": multiplayer_offline_debug_enabled,
		"connect_automatically": multiplayer_connect_automatically,
		"server_host": multiplayer_server_host,
		"server_port": multiplayer_server_port,
		"local_entity_id": multiplayer_local_entity_id,
		"map_id": map_definition.map_id,
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
	game_window_manager = GameWindowManagerScript.new()
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
	panel_session.player_changed.connect(_on_current_player_changed)
	game_window_manager.configure(panel_session)
	multiplayer_presenter.skill_level_up_received.connect(_on_skill_level_up)


## 将线上或离线权威升级事件格式化为荣耀版原句式并交给 HUD 排队。
## [param event] 含 skill_id 与 new_level 的权威升级事件。
func _on_skill_level_up(event: Dictionary) -> void:
	if hud == null:
		return
	hud.show_system_message(SkillLevelMessageFormatter.format(
		String(event.get("skill_id", "")), int(event.get("new_level", 0))
	))


## 将客户端唯一 CurrentPlayer 的服装对象同步到世界人物表现。
## [param current_player] 刚应用同事务权威快照的当前玩家聚合。
func _on_current_player_changed(current_player: Player) -> void:
	if world_view.player != null:
		world_view.player.apply_character_equipment(
			current_player.character_equipment,
			character_catalog,
		)
		world_view.player.apply_vehicle_equipment(current_player.vehicle)
	if hud != null:
		var primary_device: VehicleEquipment = current_player.vehicle.loadout.at(1)
		hud.set_primary_device("" if primary_device == null else primary_device.primary_device_kind())
		var tactical_equipment: VehicleEquipment = current_player.vehicle.loadout.at(13)
		var action_id := "" if tactical_equipment == null else String(
			TACTICAL_ACTION_BY_DEFINITION.get(tactical_equipment.definition_id, "")
		)
		hud.set_tactical_action(action_id)
	_refresh_local_movement_availability(current_player)


## 根据活动地图与权威玩家装配刷新本地预测移动许可。
## 室内始终按人物移动；野外必须存在提供正推进力的引擎。
## [param current_player] 最新玩家聚合；为空时从当前面板投影读取。
func _refresh_local_movement_availability(current_player: Player = null) -> void:
	if local_player_controller == null or map_definition == null:
		return
	var player_state := current_player
	if player_state == null and game_window_manager != null:
		player_state = panel_session.current_player
	var movement_enabled := true
	if map_definition.category == "field":
		movement_enabled = player_state != null \
			and int(player_state.calculate_vehicle_stats().get("propulsion", 0)) > 0
	local_player_controller.set_movement_enabled(movement_enabled)


## 读取受控地图目录的 `definitions` 映射，格式错误时返回仅包含当前大厅的安全目录。
## 返回该函数计算、查询或操作得到的结果。
## 设计：网络消息不能提供资源路径；所有预载目标必须先存在于版本化目录。
func _load_map_directory_definitions() -> Dictionary:
	var fallback := {StringName(map_definition.map_id): MAP_DEFINITION_PATH}
	if not FileAccess.file_exists(MAP_DIRECTORY_PATH):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY_PATH))
	if not parsed is Dictionary or not parsed.get("definitions", {}) is Dictionary:
		return fallback
	return parsed["definitions"].duplicate(true)


## 处理 `_on_multiplayer_local_character_state_applied` 对应的信号回调。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_multiplayer_local_character_state_applied(state: Dictionary) -> void:
	local_player_controller.apply_authoritative_presentation(state)


## 处理 `_on_local_player_position_changed` 对应的信号回调。
## [param _position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_local_player_position_changed(_position: Vector2) -> void:
	_sync_player_nodes()


## 在本地路线自然完成后检查脚点附近是否存在地图出口。
func _on_local_player_route_finished() -> void:
	map_travel.try_begin_nearby_map_transition()


## 处理 `_on_local_player_route_stopped` 对应的信号回调。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_local_player_route_stopped(message: String) -> void:
	map_travel.selected_transition_id = &""
	if hud:
		hud.show_status(message)


## 在活动世界原子替换前结束旧 NPC 交互，并清除仅属于旧地图的传送选择。
func _on_active_world_will_replace() -> void:
	if active_npc and is_instance_valid(active_npc):
		active_npc.set_interaction_active(false)
	active_npc = null
	map_travel.selected_transition_id = &""
	transition_choice_ids.clear()
	if world_view.movement_click_effects != null:
		world_view.movement_click_effects.clear_effects()
	for controller: Node in world_view.combat_attack_controllers.values():
		controller.clear_effects()
	if world_view.monster_world_controller != null:
		world_view.monster_world_controller.clear()
	if world_view.mineral_world_controller != null:
		world_view.mineral_world_controller.clear()
	world_view.mining_visual_controller.clear()


## 查找鼠标点命中的最近 NPC 或生产设施。
## [param world_position] 鼠标对应的地图世界坐标。
## [param maximum_distance] NPC 默认点选距离；设施使用各自配置的命中半径。
## 返回最近的可交互节点；没有命中时返回 null。
func _nearest_npc(world_position: Vector2, maximum_distance: float) -> Node2D:
	var result: Node2D
	var closest_distance := INF
	for npc in npc_instances:
		var distance := npc.position.distance_to(world_position)
		if distance <= maximum_distance and distance < closest_distance:
			closest_distance = distance
			result = npc
	for facility in facility_instances:
		var distance := facility.position.distance_to(world_position)
		if facility.hit_test(world_position) and distance < closest_distance:
			closest_distance = distance
			result = facility
	return result


## 执行 `show_npc_popup` 对应的模块操作。
## [param npc] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _show_npc_popup(npc: Node2D) -> void:
	map_travel.stop_moving("正在与%s交互" % String(npc.get_interaction_data()["title"]))
	if active_npc and active_npc != npc:
		active_npc.set_interaction_active(false)
	active_npc = npc
	active_npc.set_interaction_active(true)
	var screen_position := get_viewport().get_canvas_transform() * active_npc.global_position
	hud.show_npc_popup(active_npc.get_interaction_data(), screen_position)


## 处理 `_on_npc_popup_closed` 对应的信号回调。
func _on_npc_popup_closed() -> void:
	if active_npc:
		active_npc.set_interaction_active(false)
		active_npc = null


## 将交互菜单动作分派到传送、制造、商店或 NPC 业务处理器。
## [param action_id] 当前菜单发出的业务动作标识。
## 设计：关闭菜单会同步清空 active_npc，窗口所需的标识和标题必须在关闭前读取。
func _on_npc_action_requested(action_id: String) -> void:
	if transition_choice_ids.has(action_id):
		var transition_id := StringName(transition_choice_ids[action_id])
		var transition: MapTransition = map_definition.transition_by_id(transition_id)
		transition_choice_ids.clear()
		hud.hide_popup()
		if transition != null:
			_move_to(transition.approach_point, transition.transition_id)
		return
	if is_instance_valid(active_npc):
		var interaction_title := String(active_npc.get_interaction_data()["title"])
		if action_id == "manufacture" and active_npc is WorldFacilityInteraction:
			var station_id := (active_npc as WorldFacilityInteraction).station_id
			if station_id.is_empty():
				return
			hud.hide_popup()
			game_window_manager.open_manufacturing(station_id)
			hud.show_status("正在使用%s" % interaction_title)
			return
		var npc_id := String(active_npc.get("npc_id"))
		var npc_definition: Variant = active_npc.get("npc_definition")
		var interaction_service := String(npc_definition.get("interaction_service", "")) \
			if npc_definition is Dictionary else ""
		if interaction_service == "commerce" \
				and action_id in ["buy", "sell", "task"]:
			hud.hide_popup()
			game_window_manager.open_weapon_merchant(action_id, npc_id)
			hud.show_status("正在与%s交互" % interaction_title)
			return
		hud.show_status(active_npc.handle_action(action_id))


## 显示同一原版 transport2 锚点的目标选择菜单。
## [param selected] 鼠标命中的任一多目标传送定义。
## [param world_position] 右键点击的地图世界坐标。
## 设计：选择只决定 transition_id；寻路、预载和最终切图仍走既有权威传送链。
func _show_transition_choices(selected: MapTransition, world_position: Vector2) -> void:
	transition_choice_ids.clear()
	var actions: Array[Dictionary] = []
	for transition: MapTransition in map_definition.enabled_transitions():
		if transition.kind != MapTransition.Kind.MULTI_CHOICE \
				or not transition.source_anchor.is_equal_approx(selected.source_anchor):
			continue
		var action_id := "transition_%s" % String(transition.transition_id)
		transition_choice_ids[action_id] = transition.transition_id
		actions.append({"id": action_id, "label": transition.label})
	var screen_position := get_viewport().get_canvas_transform() * world_position
	hud.show_npc_popup({
		"title": "选择目的地",
		"body": "",
		"actions": actions,
	}, screen_position)


## 将底栏导航交给窗口管理器；好友功能未开放时显示屏幕中央提示。
## [param action_id] 免费版底栏发出的业务动作标识。
func _on_hud_action_requested(action_id: String) -> void:
	if action_id == "friends":
		hud.show_system_message("好友列表暂未实现")
		return
	if action_id == "return_base" and combat.vehicle_destroyed:
		combat.request_vehicle_recovery()
		return
	if action_id == CombatActions.SELF_REPAIR_ABILITY_ID:
		combat.request_self_repair()
		return
	if game_window_manager != null and game_window_manager.toggle(action_id):
		return


## 推进并更新 `update_minimap_dot` 对应的模块状态。
func _update_minimap_dot() -> void:
	if hud and world_view.player:
		hud.update_player_dot(world_view.player.position)


# Diagnostic compatibility wrappers keep map tests focused on behavior while
# the implementation lives in DiamondNavigation.
## 执行 `world_to_cell` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _world_to_cell(world_position: Vector2) -> Vector2i:
	return navigation.world_to_cell(world_position)


## 执行 `cell_to_world` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _cell_to_world(cell: Vector2i) -> Vector2:
	return navigation.cell_to_world(cell)


## 执行 `cell_id` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _cell_id(cell: Vector2i) -> int:
	return navigation.cell_id(cell)


## 执行 `raw_cell_walkable` 对应的模块操作。
## [param cell] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _raw_cell_walkable(cell: Vector2i) -> bool:
	return navigation.raw_cell_walkable(cell)


## 判断 `is_walkable` 对应的模块状态。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _is_walkable(world_position: Vector2) -> bool:
	return navigation.is_walkable(world_position)


## 执行 `simplify_path` 对应的模块操作。
## [param raw_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _simplify_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	return navigation.simplify_path(raw_path)


## 执行 `segment_is_walkable` 对应的模块操作。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _segment_is_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	return navigation.segment_is_walkable(from_position, to_position)
