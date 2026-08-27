extends Node2D

const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const NPC_CONFIG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"
const MAP_DEFINITION_PATH := "res://data/maps/yian_harbor_hall_floor_1.json"
const MAP_DIRECTORY_PATH := "res://data/maps/map_directory.json"
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const YSortedPropScript := preload("res://scripts/world/y_sorted_prop.gd")
const SemanticSceneLayerScript := preload("res://scripts/world/semantic_scene_layer.gd")
const HallHudScript := preload("res://scripts/ui/hall_hud.gd")
const NpcBaseScript := preload("res://scripts/npcs/npc_base.gd")
const ShopNpcScript := preload("res://scripts/npcs/shop_npc.gd")
const QuestNpcScript := preload("res://scripts/npcs/quest_npc.gd")
const HallMultiplayerPresenterScript := preload(
	"res://scripts/client/presentation/hall_multiplayer_presenter.gd"
)
const ClientMapPreloaderScript := preload(
	"res://scripts/client/presentation/client_map_preloader.gd"
)
const LocalPlayerControllerScript := preload(
	"res://scripts/client/gameplay/local_player_controller.gd"
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
var map_manifest: Dictionary
var map_definition: RefCounted
var map_size := Vector2.ZERO
var navigation: RefCounted = DiamondNavigationScript.new()
# Public aliases retained for diagnostics and the map validation suite.
var nav_data := PackedByteArray()
var nav_grid: AStar2D
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
var map_scene_nodes: Array[Node2D] = []
var player: Node2D
var npc_instances: Array[Node2D] = []
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


## Initializes node dependencies after the node enters the scene tree.
func _ready() -> void:
	_apply_multiplayer_command_line(OS.get_cmdline_user_args())
	character_catalog = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	npc_catalog = JSON.parse_string(FileAccess.get_file_as_string(NPC_CONFIG_PATH))
	if not _load_map_definition():
		return
	_load_navigation()
	_build_world()
	_build_hud()
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


## Loads and validates the requested resource data.
## Returns Whether the operation completed or the queried condition is satisfied.
func _load_map_definition() -> bool:
	var loader: RefCounted = MapDefinitionLoaderScript.new()
	map_definition = loader.load_file(MAP_DEFINITION_PATH)
	if map_definition == null:
		push_error("Map definition is invalid: %s" % "; ".join(loader.errors))
		return false
	map_size = map_definition.world_size
	var manifest_path := String(map_definition.resource_paths.get("scene_manifest", ""))
	if manifest_path.is_empty():
		push_error("Map definition does not provide a scene_manifest resource")
		return false
	map_manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not map_manifest is Dictionary:
		push_error("Map scene manifest is invalid: %s" % manifest_path)
		return false
	return true


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
		_move_to(world_position)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		var npc := _nearest_npc(world_position, 55.0)
		if npc:
			_show_npc_popup(npc)
		else:
			hud.hide_popup()
		get_viewport().set_input_as_handled()


## Loads and validates the requested resource data.
func _load_navigation() -> void:
	navigation.load_from(
		map_definition.navigation_data_path,
		map_definition.navigation_grid_size,
		map_definition.navigation_cell_size,
	)
	nav_data = navigation.data
	nav_grid = navigation.graph


## Performs the `move_to` operation.
## [param world_position] World-space position used by the operation.
func _move_to(world_position: Vector2) -> void:
	if _world_input_locked():
		_stop_moving("地图切换中，暂时不能移动")
		return
	var target_text := "%d, %d" % [roundi(world_position.x), roundi(world_position.y)]
	var result: Dictionary = local_player_controller.request_move(world_position)
	if not bool(result.get("ok", false)):
		if StringName(result.get("code", &"")) == &"no_reachable_point":
			hint_label.text = "目标 %s 不可到达，附近也没有可达点" % target_text
		else:
			hint_label.text = "无法找到前往 %s 的路径" % target_text
		return
	var resolved_position: Vector2 = result["resolved_position"]
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
	map_background.texture = load(String(map_definition.resource_paths["floor"]))
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
	_build_scene_props()
	_build_npcs()

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
		navigation,
		destination_marker,
		player_movement_speed,
		Vector2(730, 1330),
	)
	if controller_error != OK:
		push_error("Unable to configure local player controller: %s" % error_string(controller_error))

	camera = Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position = player.position
	camera.zoom = Vector2(0.82, 0.82)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(map_size.x)
	camera.limit_bottom = int(map_size.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	add_child(camera)
	camera.make_current()
	local_player_controller.position_changed.connect(_on_local_player_position_changed)
	local_player_controller.route_finished.connect(_on_local_player_route_finished)
	local_player_controller.route_stopped.connect(_on_local_player_route_stopped)


## Builds the requested runtime object from configuration data.
func _build_scene_props() -> void:
	var composition: Dictionary = map_manifest["composition"]
	if String(composition.get("render_strategy", "")) == "semantic_owner_layers":
		_build_semantic_scene_layers(composition)
		return
	var props: Array = map_manifest["composition"]["props"]
	for index in range(props.size()):
		var definition: Dictionary = props[index]
		var prop: Node2D = YSortedPropScript.new()
		prop.name = "SceneProp_%d" % (index + 1)
		var anchor := Vector2(definition["anchor"][0], definition["anchor"][1])
		prop.configure(
			load(String(definition["texture"])),
			anchor,
			Vector2(definition["offset"][0], definition["offset"][1]),
			float(definition.get("sort_baseline", anchor.y)),
		)
		sortable_world.add_child(prop)
		map_scene_nodes.append(prop)


## Builds the requested runtime object from configuration data.
## [param composition] World-space position used by the operation.
func _build_semantic_scene_layers(composition: Dictionary) -> void:
	for index in range(composition["semantic_layers"].size()):
		var definition: Dictionary = composition["semantic_layers"][index]
		var offset: Array = definition["pixel_offset"]
		var atlas_values: Array = definition["atlas_region"]
		var layer: Node2D = SemanticSceneLayerScript.new()
		layer.name = "SemanticSceneLayer_%d" % (index + 1)
		layer.configure(
			load(String(definition["texture"])) as Texture2D,
			Rect2(float(atlas_values[0]), float(atlas_values[1]), float(atlas_values[2]), float(atlas_values[3])),
			Vector2(float(offset[0]), float(offset[1])),
			float(definition["sort_baseline"]),
		)
		sortable_world.add_child(layer)
		map_scene_nodes.append(layer)


## Builds the requested runtime object from configuration data.
func _build_npcs() -> void:
	for definition_value in npc_catalog.get("npcs", []):
		var definition: Dictionary = definition_value
		var npc := _create_npc_for_kind(String(definition.get("kind", "ambient")))
		var appearance := String(definition.get("appearance", "npc_red"))
		npc.configure_npc(
			CharacterFactoryScript.build_character_set(character_catalog, appearance),
			definition,
			navigation,
		)
		sortable_world.add_child(npc)
		npc_instances.append(npc)


## Builds the requested runtime object from configuration data.
## [param kind] Stable identifier of the target value.
## Returns the result produced by the operation.
func _create_npc_for_kind(kind: String) -> Node2D:
	match kind:
		"shop":
			return ShopNpcScript.new()
		"quest":
			return QuestNpcScript.new()
		_:
			return NpcBaseScript.new()


## Builds the requested runtime object from configuration data.
func _build_hud() -> void:
	hud = HallHudScript.new()
	hud.configure(
		map_size,
		load(String(map_definition.resource_paths["minimap"])),
		String(map_definition.display_name),
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
	if hint_label:
		hint_label.text = message


## 在玩家停步后查找触发半径内最近的内部出口，并先预载其目标地图。
## Design: 客户端只从受控本地定义取得目标内容；真正的地图和落点仍由服务端裁决。
func _try_begin_nearby_map_transition() -> void:
	if not pending_map_transition.is_empty() or map_preloader == null:
		return
	var selected_transition: MapTransition
	var selected_distance := map_transition_trigger_radius
	for transition: MapTransition in map_definition.enabled_transitions():
		if transition.external_target or transition.destination_map_id.is_empty():
			continue
		var distance := player.position.distance_to(transition.approach_point)
		if distance <= selected_distance:
			selected_transition = transition
			selected_distance = distance
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
	var definition: MapDefinition = bundle.get("definition")
	var manifest: Dictionary = bundle.get("map_manifest", {})
	var resources: Dictionary = bundle.get("resources", {})
	var floor_texture: Texture2D = resources.get("floor") as Texture2D
	var minimap_texture: Texture2D = resources.get("minimap") as Texture2D
	if definition == null or manifest.is_empty() or floor_texture == null or minimap_texture == null:
		return false
	var staged_navigation := DiamondNavigationScript.new()
	if not staged_navigation.load_from(
		definition.navigation_data_path,
		definition.navigation_grid_size,
		definition.navigation_cell_size,
	):
		return false
	if not staged_navigation.is_walkable(spawn_position):
		return false

	_clear_map_specific_nodes()
	map_definition = definition
	map_manifest = manifest
	map_size = definition.world_size
	navigation = staged_navigation
	nav_data = navigation.data
	nav_grid = navigation.graph
	map_background.texture = floor_texture
	_build_scene_props()
	if definition.map_id == &"yian_harbor_hall_floor_1":
		_build_npcs()
	multiplayer_map_instance_id = map_instance_id
	local_player_controller.commit_map_position(navigation, spawn_position)
	camera.limit_right = int(map_size.x)
	camera.limit_bottom = int(map_size.y)
	camera.position = spawn_position
	hud.set_map(map_size, minimap_texture, definition.display_name)
	_set_player_action("stand")
	hint_label.text = "已进入%s" % definition.display_name
	map_commit_failure_locked = false
	pending_map_transition.clear()
	pending_map_bundle.clear()
	return true


## 清除旧地图的场景图层与 NPC，但保留玩家、远端玩家、摄像机和 HUD。
func _clear_map_specific_nodes() -> void:
	hud.hide_popup()
	active_npc = null
	for npc in npc_instances:
		if is_instance_valid(npc):
			npc.free()
	npc_instances.clear()
	for scene_node in map_scene_nodes:
		if is_instance_valid(scene_node):
			scene_node.free()
	map_scene_nodes.clear()


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
