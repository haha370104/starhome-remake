extends Node2D

const MAP_SIZE := Vector2(1800.0, 1920.0)
# Movement and walk animation are both 1.4x the original prototype timing, so
# each gait cycle still covers the same map distance without foot sliding.
const GAMEPLAY_SPEED_SCALE := 1.4
const PLAYER_SPEED := 145.0 * GAMEPLAY_SPEED_SCALE
const CHARACTER_CATALOG_PATH := "res://assets/characters/character_atlases.json"
const MAP_MANIFEST_PATH := "res://assets/maps/yian_harbor/hall_floor_1/map_manifest.json"
const MAP_TEXTURE_PATH := "res://assets/maps/yian_harbor/hall_floor_1/roomsvr1_base.png"
const MINIMAP_TEXTURE_PATH := "res://assets/maps/yian_harbor/hall_floor_1/roomsvr1_minimap.jpg"
const NAV_DATA_PATH := "res://assets/maps/yian_harbor/hall_floor_1/roomsvr1_collision.bin"
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const CharacterFactoryScript := preload("res://scripts/characters/character_factory.gd")
const WorldCharacterScript := preload("res://scripts/characters/world_character.gd")
const YSortedPropScript := preload("res://scripts/world/y_sorted_prop.gd")
const HallHudScript := preload("res://scripts/ui/hall_hud.gd")

var character_catalog: Dictionary
var map_manifest: Dictionary
var navigation: RefCounted = DiamondNavigationScript.new()
# Public aliases retained for diagnostics and the map validation suite.
var nav_data := PackedByteArray()
var nav_grid: AStar2D
var path_points := PackedVector2Array()
var path_index := 0
var current_direction := 6

var sortable_world: Node2D
var player: Node2D
var admin: Node2D
var camera: Camera2D
var destination_marker: Polygon2D
var hud: CanvasLayer
var hint_label: Label
var popup: PanelContainer
var minimap_player_dot: ColorRect


func _ready() -> void:
	character_catalog = JSON.parse_string(FileAccess.get_file_as_string(CHARACTER_CATALOG_PATH))
	map_manifest = JSON.parse_string(FileAccess.get_file_as_string(MAP_MANIFEST_PATH))
	_load_navigation()
	_build_world()
	_build_hud()
	_set_player_action("stand")
	_sync_player_nodes()


func _process(delta: float) -> void:
	if path_index >= path_points.size():
		return
	var waypoint := path_points[path_index]
	var delta_to_target := waypoint - player.position
	var distance := delta_to_target.length()
	if distance <= PLAYER_SPEED * delta:
		player.position = waypoint
		path_index += 1
		if path_index >= path_points.size():
			destination_marker.visible = false
			_set_player_action("stand")
		else:
			_begin_current_path_segment()
	else:
		var motion := delta_to_target.normalized() * PLAYER_SPEED * delta
		var next_position := player.position + motion
		if not _is_walkable(next_position):
			_stop_moving("路径被阻挡")
			return
		player.position = next_position
	_sync_player_nodes()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var mouse_event := event as InputEventMouseButton
	var world_position := get_global_mouse_position()
	if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
		_move_to(world_position)
		get_viewport().set_input_as_handled()
	elif mouse_event.button_index == MOUSE_BUTTON_LEFT:
		if world_position.distance_to(admin.position) <= 55.0:
			_show_admin_popup()
		else:
			hud.hide_popup()
		get_viewport().set_input_as_handled()


func _load_navigation() -> void:
	navigation.load_from(NAV_DATA_PATH)
	nav_data = navigation.data
	nav_grid = navigation.graph


func _move_to(world_position: Vector2) -> void:
	var target_text := "%d, %d" % [roundi(world_position.x), roundi(world_position.y)]
	var resolved_position := world_position
	var used_nearest_walkable := false
	if not navigation.is_walkable(world_position):
		resolved_position = navigation.closest_reachable_position(player.position, world_position)
		used_nearest_walkable = true
		if not resolved_position.is_finite():
			hint_label.text = "目标 %s 不可到达，附近也没有可达点" % target_text
			return
	path_points = navigation.find_path(player.position, resolved_position)
	if path_points.is_empty():
		hint_label.text = "无法找到前往 %s 的路径" % target_text
		return
	path_index = 1 if path_points.size() > 1 else 0
	_begin_current_path_segment()
	destination_marker.position = resolved_position
	destination_marker.visible = true
	if used_nearest_walkable:
		hint_label.text = "目标 %s 不可到达，正在前往附近 %d, %d" % [
			target_text,
			roundi(resolved_position.x),
			roundi(resolved_position.y),
		]
	else:
		hint_label.text = "正在前往 %s" % target_text
	hud.hide_popup()


func _begin_current_path_segment() -> void:
	if path_index >= path_points.size() or not player:
		return
	var segment_motion := path_points[path_index] - player.position
	if segment_motion.length_squared() <= 0.01:
		return
	# The actual vector remains continuous; only the nearest source animation is
	# selected once at the beginning of each unobstructed line segment.
	current_direction = _direction_index(segment_motion)
	_set_player_action("move")


func _stop_moving(message: String) -> void:
	path_points = PackedVector2Array()
	path_index = 0
	destination_marker.visible = false
	_set_player_action("stand")
	if hint_label:
		hint_label.text = message


func _direction_index(motion: Vector2) -> int:
	# Source rows: E, NE, N, NW, W, SW, S, SE.
	return posmod(-roundi(motion.angle() / (PI / 4.0)), 8)


func _set_player_action(action: String) -> void:
	if player:
		player.set_action(action, current_direction)


func _sync_player_nodes() -> void:
	if not player:
		return
	camera.position = player.position
	_update_minimap_dot()


func _build_world() -> void:
	var background := Sprite2D.new()
	background.name = "MapBase"
	background.texture = load(MAP_TEXTURE_PATH)
	background.centered = false
	background.position = Vector2.ZERO
	background.z_index = -100
	add_child(background)

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

	_add_npc("兑换矩阵校验晶片", Vector2(570, 1040), false)
	_add_npc("能量石兑换员", Vector2(400, 1210), true)
	_add_npc("迁移礼包大使", Vector2(965, 920), true)
	_add_npc("星际邮递员", Vector2(1115, 1040), true)
	_add_npc("龙腾精英回归专员", Vector2(1290, 1060), true)
	_add_npc("精英老兵·维斯", Vector2(1440, 925), true)
	_add_npc("兑换超群校徽晶片", Vector2(690, 1135), false)
	_add_npc("怀旧战斗指挥官", Vector2(1045, 835), true)
	admin = _add_npc("管理员", Vector2(845, 1190), true)

	player = WorldCharacterScript.new()
	player.name = "Player"
	player.configure(
		CharacterFactoryScript.build_character_set(character_catalog, "player"),
		"H番茄花园",
		Color(0.35, 1.0, 0.92),
		Vector2(-66, -158),
	)
	player.position = Vector2(730, 1330)
	sortable_world.add_child(player)

	camera = Camera2D.new()
	camera.name = "PlayerCamera"
	camera.position = player.position
	camera.zoom = Vector2(0.82, 0.82)
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(MAP_SIZE.x)
	camera.limit_bottom = int(MAP_SIZE.y)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.5
	add_child(camera)
	camera.make_current()


func _build_scene_props() -> void:
	var props: Array = map_manifest["composition"]["props"]
	for index in range(props.size()):
		var definition: Dictionary = props[index]
		var prop: Node2D = YSortedPropScript.new()
		prop.name = "Display_%d" % (index + 1)
		prop.position = Vector2(definition["anchor"][0], definition["anchor"][1])
		prop.configure(
			load(String(definition["texture"])),
			Vector2(definition["offset"][0], definition["offset"][1]),
		)
		sortable_world.add_child(prop)


func _add_npc(display_name: String, position_value: Vector2, red: bool) -> Node2D:
	var npc: Node2D = WorldCharacterScript.new()
	npc.name = display_name
	var key := "npc_red" if red else "npc_blue"
	npc.configure(
		CharacterFactoryScript.build_character_set(character_catalog, key),
		display_name,
		Color.WHITE,
		Vector2(-64, -88),
	)
	npc.position = position_value
	sortable_world.add_child(npc)
	return npc


func _build_hud() -> void:
	hud = HallHudScript.new()
	hud.configure(MAP_SIZE, load(MINIMAP_TEXTURE_PATH))
	add_child(hud)
	hint_label = hud.hint_label
	popup = hud.popup
	minimap_player_dot = hud.minimap_player_dot


func _show_admin_popup() -> void:
	_stop_moving("正在与管理员交互")
	hud.show_admin_popup()


func _update_minimap_dot() -> void:
	if hud and player:
		hud.update_player_dot(player.position)


# Diagnostic compatibility wrappers keep map tests focused on behavior while
# the implementation lives in DiamondNavigation.
func _world_to_cell(world_position: Vector2) -> Vector2i:
	return navigation.world_to_cell(world_position)


func _cell_to_world(cell: Vector2i) -> Vector2:
	return navigation.cell_to_world(cell)


func _cell_id(cell: Vector2i) -> int:
	return navigation.cell_id(cell)


func _raw_cell_walkable(cell: Vector2i) -> bool:
	return navigation.raw_cell_walkable(cell)


func _is_walkable(world_position: Vector2) -> bool:
	return navigation.is_walkable(world_position)


func _simplify_path(raw_path: PackedVector2Array) -> PackedVector2Array:
	return navigation.simplify_path(raw_path)


func _segment_is_walkable(from_position: Vector2, to_position: Vector2) -> bool:
	return navigation.segment_is_walkable(from_position, to_position)
