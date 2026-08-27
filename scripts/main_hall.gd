extends Node2D

const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const NPC_CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const MAP_DEFINITION_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/map_directory.json"
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const HallHudScript := preload("res://scripts/ui/hall_hud.gd")
const HallMultiplayerPresenterScript := preload(
	"res://scripts/client/presentation/hall_multiplayer_presenter.gd"
)
const ClientMapPreloaderScript := preload(
	"res://scripts/client/presentation/client_map_preloader.gd"
)
const LocalPlayerControllerScript := preload(
	"res://scripts/client/gameplay/local_player_controller.gd"
)
const ActiveWorldControllerScript := preload(
	"res://scripts/client/world/active_world_controller.gd"
)

# Player tuning is intentionally local to the player. NPC patrol motion has its
# own configuration and must not inherit these values when player progression,
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

var sortable_world: Node2D
var map_background: Sprite2D
var map_scene_nodes: Array[Node2D]:
	get:
		return active_world_controller.scene_nodes if active_world_controller else []
var player: Node2D
var npc_instances: Array[Node2D]:
	get:
		return active_world_controller.npc_instances if active_world_controller else []
var active_npc: Node2D
var camera: Camera2D
var destination_marker: Polygon2D
var hud: CanvasLayer
var hint_label: Label
var popup: PanelContainer
var minimap_player_dot: ColorRect
var multiplayer_presenter: Node
var map_preloader: Node
var active_movement_input_sequence: int:
	get:
		return local_player_controller.active_movement_input_sequence if local_player_controller else 0
	set(value):
		if local_player_controller:
			local_player_controller.active_movement_input_sequence = value
var pending_map_transition: Dictionary = {}
var pending_map_bundle: Dictionary = {}
var pending_authoritative_join: Dictionary = {}
var map_commit_failure_locked := false
var selected_transition_id: StringName = &""


## Initializes node dependencies after the node enters the scene tree.
func _ready() -> void:
	_apply_multiplayer_command_line(OS.get_cmdline_user_args())
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
	_build_world()
	_build_hud(initial_bundle)
	var configure_error: Error = active_world_controller.configure(
		self,
		sortable_world,
		map_background,
		local_player_controller,
		camera,
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


## 将 [param arguments] 中的联机启动参数覆盖到大厅导出配置。
## Design: 编辑器默认保持离线调试；正式联机必须显式传入 `--online`，避免无服务器时影响美术预览。
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


## Advances frame-based presentation state.
## [param delta] Elapsed time in seconds for this update.
func _process(delta: float) -> void:
	if local_player_controller:
		local_player_controller.advance(delta)


## Routes unhandled player input into gameplay interactions.
## [param event] Input event to inspect.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if _world_input_locked():
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
		else:
			hud.hide_popup()
		get_viewport().set_input_as_handled()


## 处理世界坐标 [param world_position] 的右键请求；传送视图命中时改走其可行走 approach point。
## Design: 图标锚点仅用于渲染/命中，绝不能替代地图定义中的接近点。
func _handle_world_right_click(world_position: Vector2) -> void:
	var transition_view: Node2D = active_world_controller.transition_view_at(world_position)
	if transition_view != null:
		_move_to(transition_view.approach_point, transition_view.transition_id)
	else:
		_move_to(world_position)


## Performs the `move_to` operation.
## [param world_position] 玩家真正要到达的可行走坐标。
## [param transition_id] 非空时表示该目标来自传送视图，抵达后只提交此业务出口。
func _move_to(world_position: Vector2, transition_id: StringName = &"") -> void:
	if _world_input_locked():
		_stop_moving("地图切换中，暂时不能移动")
		return
	selected_transition_id = &""
	var target_text := "%d, %d" % [roundi(world_position.x), roundi(world_position.y)]
	var result: Dictionary = local_player_controller.request_move(world_position)
	if not bool(result.get("ok", false)):
		if StringName(result.get("code", &"")) == &"no_reachable_point":
			hint_label.text = "目标 %s 不可到达，附近也没有可达点" % target_text
		else:
			hint_label.text = "无法找到前往 %s 的路径" % target_text
		return
	var resolved_position: Vector2 = result["resolved_position"]
	selected_transition_id = transition_id
	if bool(result["used_nearest_walkable"]):
		hint_label.text = "目标 %s 不可到达，正在前往附近 %d, %d" % [
			target_text,
			roundi(resolved_position.x),
			roundi(resolved_position.y),
		]
	else:
		hint_label.text = "正在前往 %s" % target_text
	hud.hide_popup()


## Performs the `begin_current_path_segment` operation.
func _begin_current_path_segment() -> void:
	if local_player_controller:
		local_player_controller.refresh_route_direction()


## Performs the `stop_moving` operation.
## [param message] Serialized input received at the subsystem boundary.
func _stop_moving(message: String) -> void:
	if local_player_controller:
		local_player_controller.cancel_route()
	selected_transition_id = &""
	if hint_label:
		hint_label.text = message


## Performs the `direction_index` operation.
## [param motion] Input value consumed by the operation.
## Returns the computed integer value.
func _direction_index(motion: Vector2) -> int:
	return LocalPlayerControllerScript.direction_index(motion)


## Updates the managed state with the supplied value.
## [param action] Input value consumed by the operation.
func _set_player_action(action: String) -> void:
	if local_player_controller:
		local_player_controller.set_character_action(StringName(action))


## Performs the `sync_player_nodes` operation.
func _sync_player_nodes() -> void:
	if not player:
		return
	camera.position = player.position
	_update_minimap_dot()


## Builds the requested runtime object from configuration data.
func _build_world() -> void:
	map_background = Sprite2D.new()
	map_background.name = "MapBase"
	map_background.centered = false
	map_background.position = Vector2.ZERO
	map_background.z_index = -100
	add_child(map_background)

	destination_marker = Polygon2D.new()
	destination_marker.name = "DestinationMarker"
	destination_marker.polygon = PackedVector2Array(
		[Vector2(0, -10), Vector2(18, 0), Vector2(0, 10), Vector2(-18, 0)]
	)
	destination_marker.color = Color(0.1, 1.0, 0.55, 0.72)
	destination_marker.visible = false
	destination_marker.z_index = -20
	add_child(destination_marker)

	sortable_world = Node2D.new()
	sortable_world.name = "YSortedWorld"
	sortable_world.y_sort_enabled = true
	add_child(sortable_world)

	player = WorldCharacterScript.new()
	player.name = "Player"
	player.configure(
		CharacterFactoryScript.build_character_set(character_catalog, "player"),
		"H番茄花园",
		Color(0.35, 1.0, 0.92),
		Vector2(-66, -158),
	)
	player.set_animation_speed_scale(player_animation_speed_scale)
	sortable_world.add_child(player)

	local_player_controller = LocalPlayerControllerScript.new()
	local_player_controller.name = "LocalPlayerController"
	add_child(local_player_controller)
	var controller_error: Error = local_player_controller.configure(
		player,
		DiamondNavigationScript.new(),
		destination_marker,
		player_movement_speed,
		Vector2.ZERO,
	)
	if controller_error != OK:
		push_error("Unable to configure local player controller: %s" % error_string(controller_error))

	camera = Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position = player.position
	camera.zoom = Vector2(0.82, 0.82)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = 0
	camera.limit_bottom = 0
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	add_child(camera)
	camera.make_current()
	local_player_controller.position_changed.connect(_on_local_player_position_changed)
	local_player_controller.route_finished.connect(_on_local_player_route_finished)
	local_player_controller.route_stopped.connect(_on_local_player_route_stopped)


## 以已验证 [param initial_bundle] 创建固定 HUD 外壳；后续地图内容由活动世界控制器更新。
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
	hint_label = hud.hint_label
	popup = hud.popup
	minimap_player_dot = hud.minimap_player_dot
	hud.popup_closed.connect(_on_npc_popup_closed)
	hud.npc_action_requested.connect(_on_npc_action_requested)


## 创建大厅客户端会话表现器，并以显式配置选择离线调试或真实网络入口。
## Design: 大厅保留输入、导航与动画职责；表现器仅将预测/权威状态投影到角色节点。
func _build_multiplayer_presentation() -> void:
	map_preloader = ClientMapPreloaderScript.new()
	map_preloader.name = "ClientMapPreloader"
	map_preloader.configure(_load_map_directory_definitions())
	map_preloader.map_preload_ready.connect(_on_map_preload_ready)
	map_preloader.map_preload_failed.connect(_on_map_preload_failed)
	add_child(map_preloader)

	multiplayer_presenter = HallMultiplayerPresenterScript.new()
	multiplayer_presenter.name = "HallMultiplayerPresenter"
	multiplayer_presenter.configure(player, sortable_world, character_catalog, hint_label)
	multiplayer_presenter.local_character_state_applied.connect(
		_on_multiplayer_local_character_state_applied
	)
	multiplayer_presenter.map_joined.connect(_on_authoritative_map_joined)
	multiplayer_presenter.map_change_failed.connect(_on_authoritative_map_change_failed)
	add_child(multiplayer_presenter)
	var start_error: Error = multiplayer_presenter.start({
		"offline_debug_enabled": multiplayer_offline_debug_enabled,
		"connect_automatically": multiplayer_connect_automatically,
		"server_host": multiplayer_server_host,
		"server_port": multiplayer_server_port,
		"local_entity_id": multiplayer_local_entity_id,
		"map_id": map_definition.map_id,
		"map_instance_id": multiplayer_map_instance_id,
		"initial_position": player.position,
		"remote_appearance": "player",
		"remote_animation_speed_scale": player_animation_speed_scale,
	})
	if start_error != OK:
		push_warning("Unable to start hall multiplayer presentation: %s" % error_string(start_error))
	local_player_controller.set_multiplayer_presenter(multiplayer_presenter)


## 读取受控地图目录的 `definitions` 映射，格式错误时返回仅包含当前大厅的安全目录。
## Returns 业务 map_id 到本地 `res://` 定义路径的映射。
## Design: 网络消息不能提供资源路径；所有预载目标必须先存在于版本化目录。
func _load_map_directory_definitions() -> Dictionary:
	var fallback := {StringName(map_definition.map_id): MAP_DEFINITION_PATH}
	if not FileAccess.file_exists(MAP_DIRECTORY_PATH):
		return fallback
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_DIRECTORY_PATH))
	if not parsed is Dictionary or not parsed.get("definitions", {}) is Dictionary:
		return fallback
	return parsed["definitions"].duplicate(true)


## 将表现器发布的 [param state] 交给本地玩家唯一位置写入者处理。
func _on_multiplayer_local_character_state_applied(state: Dictionary) -> void:
	local_player_controller.apply_authoritative_presentation(state)


## 在控制器采用 [param _position] 后同步摄像机和小地图投影。
func _on_local_player_position_changed(_position: Vector2) -> void:
	_sync_player_nodes()


## 在本地路线自然完成后检查脚点附近是否存在地图出口。
func _on_local_player_route_finished() -> void:
	_try_begin_nearby_map_transition()


## 将控制器停止路线的 [param message] 显示到大厅状态栏。
func _on_local_player_route_stopped(message: String) -> void:
	selected_transition_id = &""
	if hint_label:
		hint_label.text = message


## 在活动世界原子替换前结束旧 NPC 交互，并清除仅属于旧地图的传送选择。
func _on_active_world_will_replace() -> void:
	if active_npc and is_instance_valid(active_npc):
		active_npc.set_interaction_active(false)
	active_npc = null
	selected_transition_id = &""


## 在玩家停步后查找触发半径内最近的内部出口，并先预载其目标地图。
## Design: 客户端只从受控本地定义取得目标内容；真正的地图和落点仍由服务端裁决。
func _try_begin_nearby_map_transition() -> void:
	if not pending_map_transition.is_empty() or map_preloader == null:
		return
	var selected_transition: MapTransition
	var selected_distance := map_transition_trigger_radius
	if not selected_transition_id.is_empty():
		var requested_transition: MapTransition = map_definition.transition_by_id(selected_transition_id)
		if requested_transition != null:
			var requested_distance := player.position.distance_to(requested_transition.approach_point)
			if requested_distance <= selected_distance:
				selected_transition = requested_transition
				selected_distance = requested_distance
	else:
		for transition: MapTransition in map_definition.enabled_transitions():
			if transition.external_target or transition.destination_map_id.is_empty():
				continue
			var distance := player.position.distance_to(transition.approach_point)
			if distance <= selected_distance:
				selected_transition = transition
				selected_distance = distance
	selected_transition_id = &""
	if selected_transition == null:
		return
	pending_map_transition = {
		"transition_id": selected_transition.transition_id,
		"destination_map_id": selected_transition.destination_map_id,
		"destination_entry_number": selected_transition.destination_entry_number,
	}
	hint_label.text = "正在准备前往%s…" % selected_transition.label
	var preload_error: Error = map_preloader.preload_map(
		selected_transition.destination_map_id
	)
	if preload_error != OK and not pending_map_transition.is_empty():
		pending_map_transition.clear()


## 接收 [param map_id] 的完整 [param bundle]；预载先于权威请求，或补偿重连后的目标地图。
func _on_map_preload_ready(map_id: StringName, bundle: Dictionary) -> void:
	if (
		not pending_authoritative_join.is_empty()
		and StringName(pending_authoritative_join.get("map_id", &"")) == map_id
	):
		var join := pending_authoritative_join.duplicate(true)
		pending_authoritative_join.clear()
		var joined_spawn_position: Vector2 = join["spawn_position"]
		if not _commit_map_bundle(bundle, joined_spawn_position, String(join["map_instance_id"])):
			_handle_map_commit_failure("权威地图资源提交失败")
		return
	if (
		pending_map_transition.is_empty()
		or StringName(pending_map_transition.get("destination_map_id", &"")) != map_id
	):
		return
	pending_map_bundle = bundle
	if multiplayer_offline_debug_enabled:
		var definition: MapDefinition = bundle["definition"]
		var spawn_point: MapSpawnPoint = definition.spawn_for_entry(
			int(pending_map_transition["destination_entry_number"])
		)
		if spawn_point == null:
			_on_map_preload_failed(map_id, "目标地图没有可用入口")
			return
		var instance_id := "%s.instance.1" % definition.map_id
		if _commit_map_bundle(bundle, spawn_point.position, instance_id):
			multiplayer_presenter.session.current_map_id = definition.map_id
			multiplayer_presenter.session.configure_map_instance(instance_id)
			multiplayer_presenter.session.initialize_local_player(spawn_point.position)
			pending_map_transition.clear()
			pending_map_bundle.clear()
		return
	var request: Dictionary = multiplayer_presenter.request_map_change(
		StringName(pending_map_transition["transition_id"]),
		int(pending_map_transition["destination_entry_number"]),
	)
	if request.is_empty():
		hint_label.text = "当前无法提交地图切换请求"
		pending_map_transition.clear()
		pending_map_bundle.clear()


## 在 [param map_id] 预载失败时保留旧场景，并显示 [param message]。
func _on_map_preload_failed(map_id: StringName, message: String) -> void:
	if not pending_authoritative_join.is_empty():
		pending_authoritative_join.clear()
		_handle_map_commit_failure("地图%s加载失败：%s" % [map_id, message])
		return
	hint_label.text = "地图%s尚不可用：%s" % [map_id, message]
	pending_map_transition.clear()
	pending_map_bundle.clear()


## 处理服务端确认的 [param map_id]、[param map_instance_id] 与 [param spawn_position]。
## [param _definition_version] 已由会话层契约校验；资源版本由本地目录控制。
func _on_authoritative_map_joined(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
	_definition_version: int,
) -> void:
	if map_definition.map_id == map_id:
		_stop_moving("正在载入权威地图…")
		map_commit_failure_locked = false
		multiplayer_map_instance_id = map_instance_id
		local_player_controller.set_position(spawn_position)
		_stop_moving("已进入%s" % map_definition.display_name)
		pending_map_transition.clear()
		pending_map_bundle.clear()
		return
	if (
		not pending_map_bundle.is_empty()
		and pending_map_bundle["definition"].map_id == map_id
	):
		if not _commit_map_bundle(pending_map_bundle, spawn_position, map_instance_id):
			_handle_map_commit_failure("权威地图资源提交失败")
		return
	_hold_old_map_for_authoritative_join(map_id, map_instance_id, spawn_position)
	var preload_error: Error = map_preloader.preload_map(map_id)
	if preload_error != OK and not pending_authoritative_join.is_empty():
		_handle_map_commit_failure("客户端缺少权威地图资源")


## 暂存 [param map_id] 的权威加入信息，并在 [param map_instance_id] 资源提交前保持旧图脚点。
## [param map_id] 服务端已经迁入的目标业务地图。
## [param map_instance_id] 服务端分配的目标地图实例。
## [param spawn_position] 服务端裁决的目标地图出生点。
## Design: 立即终止旧路径；新出生点由 session 持有，但旧场景直到 bundle 提交前不呈现它。
func _hold_old_map_for_authoritative_join(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
) -> void:
	var held_player_position: Vector2 = local_player_controller.position()
	local_player_controller.hold_position_for_map_commit()
	hint_label.text = "正在载入权威地图…"
	pending_authoritative_join = {
		"map_id": map_id,
		"map_instance_id": map_instance_id,
		"spawn_position": spawn_position,
		"held_player_position": held_player_position,
	}


## 在权威切图拒绝时清空对应预载包；旧地图画面和导航保持不变。
## [param _transition_id] 被拒绝的出口业务标识。
## [param _code] 服务端稳定错误码；表现器已负责显示。
## [param _message] 服务端可读原因；表现器已负责显示。
func _on_authoritative_map_change_failed(
	_transition_id: StringName,
	_code: StringName,
	_message: String,
) -> void:
	pending_map_transition.clear()
	pending_map_bundle.clear()
	pending_authoritative_join.clear()


## 验证并原子提交 [param bundle]，把玩家放到 [param spawn_position] 并采用 [param map_instance_id]。
## Returns 新导航、贴图和清单全部有效且提交成功时返回 `true`。
## Design: 所有可失败加载均先暂存，当前场景直到验证完成才被清理。
func _commit_map_bundle(
	bundle: Dictionary,
	spawn_position: Vector2,
	map_instance_id: String,
) -> bool:
	if not active_world_controller.commit_bundle(bundle, spawn_position):
		return false
	multiplayer_map_instance_id = map_instance_id
	_set_player_action("stand")
	hint_label.text = "已进入%s" % map_definition.display_name
	map_commit_failure_locked = false
	pending_map_transition.clear()
	pending_map_bundle.clear()
	return true


## 报告不可恢复的客户端地图提交 [param message] 并停止网络会话，避免在错误地图上发输入。
func _handle_map_commit_failure(message: String) -> void:
	map_commit_failure_locked = true
	_stop_moving(message)
	pending_map_transition.clear()
	pending_map_bundle.clear()
	pending_authoritative_join.clear()
	if not multiplayer_offline_debug_enabled and multiplayer_presenter:
		multiplayer_presenter.stop()


## 报告旧地图世界输入是否必须暂停，直到切图完成、失败回滚或会话被安全关闭。
## Returns 预载、权威确认、会话切图或不可恢复提交失败期间返回 `true`。
## Design: 闸门只冻结本地世界交互；服务端拒绝会清空 pending 并恢复旧地图输入。
func _world_input_locked() -> bool:
	if map_commit_failure_locked:
		return true
	if (
		not pending_map_transition.is_empty()
		or not pending_authoritative_join.is_empty()
	):
		return true
	if multiplayer_presenter == null or multiplayer_presenter.session == null:
		return false
	return multiplayer_presenter.session.is_map_change_pending()


## Resolves the best matching value for the supplied query.
## [param world_position] World-space position used by the operation.
## [param maximum_distance] Input value consumed by the operation.
## Returns the result produced by the operation.
func _nearest_npc(world_position: Vector2, maximum_distance: float) -> Node2D:
	var result: Node2D
	var closest_distance := maximum_distance
	for npc in npc_instances:
		var distance := npc.position.distance_to(world_position)
		if distance <= closest_distance:
			closest_distance = distance
			result = npc
	return result


## Performs the `show_npc_popup` operation.
## [param npc] Input value consumed by the operation.
func _show_npc_popup(npc: Node2D) -> void:
	_stop_moving("正在与%s交互" % String(npc.get_interaction_data()["title"]))
	if active_npc and active_npc != npc:
		active_npc.set_interaction_active(false)
	active_npc = npc
	active_npc.set_interaction_active(true)
	hud.show_npc_popup(active_npc.get_interaction_data())


## Handles the signal callback for `on_npc_popup_closed`.
func _on_npc_popup_closed() -> void:
	if active_npc:
		active_npc.set_interaction_active(false)
		active_npc = null


## Handles the signal callback for `on_npc_action_requested`.
## [param action_id] Stable identifier of the target value.
func _on_npc_action_requested(action_id: String) -> void:
	if active_npc:
		hint_label.text = active_npc.handle_action(action_id)


## Advances the managed state using the supplied update.
func _update_minimap_dot() -> void:
	if hud and player:
		hud.update_player_dot(player.position)


# Diagnostic compatibility wrappers keep map tests focused on behavior while
# the implementation lives in DiamondNavigation.
## Converts coordinates between world and navigation-grid space.
## [param world_position] World-space position used by the operation.
## Returns the resolved coordinate.
func _world_to_cell(world_position: Vector2) -> Vector2i:
	return navigation.world_to_cell(world_position)


## Converts coordinates between world and navigation-grid space.
## [param cell] Navigation-grid cell used by the operation.
## Returns the resolved coordinate.
func _cell_to_world(cell: Vector2i) -> Vector2:
	return navigation.cell_to_world(cell)


## Performs the `cell_id` operation.
## [param cell] Navigation-grid cell used by the operation.
## Returns the computed integer value.
func _cell_id(cell: Vector2i) -> int:
	return navigation.cell_id(cell)


## Reports whether the requested condition is satisfied.
## [param cell] Navigation-grid cell used by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
func _raw_cell_walkable(cell: Vector2i) -> bool:
	return navigation.raw_cell_walkable(cell)


## Reports whether the requested condition is satisfied.
## [param world_position] World-space position used by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
func _is_walkable(world_position: Vector2) -> bool:
	return navigation.is_walkable(world_position)


## Performs the `simplify_path` operation.
## [param raw_path] Resource or movement path consumed by the operation.
## Returns the resolved movement path.
func _simplify_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	return navigation.simplify_path(raw_path)


## Performs the `segment_is_walkable` operation.
## [param from_position] World-space position used by the operation.
## [param to_position] World-space position used by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
func _segment_is_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	return navigation.segment_is_walkable(from_position, to_position)
