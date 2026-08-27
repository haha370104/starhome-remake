class_name FreeMinimapDock
extends Control

signal layout_width_changed(width: float)

const LegacyStateButtonScript := preload("res://scripts/ui/legacy_state_button.gd")
var world_size := Vector2.ONE
var map_texture: Texture2D
var definition: Dictionary
var hud_state: HudState
var map_viewport: Control
var map_border: Panel
var map_image: TextureRect
var marker_layer: Control
var player_dot: ColorRect
var control_background: TextureRect
var coordinate_label: Label
var map_name_label: Label
var size_buttons: Dictionary = {}
var collapse_buttons: Dictionary = {}
var small_view := Rect2(1, 1, 120, 120)
var small_size := Vector2(125, 165)
var collapsed_size := Vector2(125, 41)
var control_area_position := Vector2(1, 122)
var control_area_size := Vector2(124, 41)


## 以 [param world_map_size]、[param minimap_texture] 和 [param display_name] 构建小地图，素材来自 [param asset_definition]，状态由 [param state] 驱动。
## Design: 小图模式固定玩家点并反向移动地图；大图模式固定地图并按世界比例移动玩家点。
func configure(
	world_map_size: Vector2,
	minimap_texture: Texture2D,
	display_name: String,
	asset_definition: Dictionary,
	state: HudState,
) -> void:
	name = "MinimapDock"
	world_size = Vector2(maxf(world_map_size.x, 1.0), maxf(world_map_size.y, 1.0))
	map_texture = minimap_texture
	definition = asset_definition
	hud_state = state
	small_size = _vector_from_array(definition.get("small_size", []), Vector2(125, 165))
	collapsed_size = _vector_from_array(definition.get("collapsed_size", []), Vector2(125, 41))
	var viewport_definition: Dictionary = definition.get("small_viewport", {})
	small_view = Rect2(
		_vector_from_array(viewport_definition.get("position", []), Vector2(1, 1)),
		_vector_from_array(viewport_definition.get("size", []), Vector2(120, 120)),
	)
	var control_area_definition: Dictionary = definition.get("control_area", {})
	control_area_position = _vector_from_array(
		control_area_definition.get("position", []),
		Vector2(1, 122),
	)
	control_area_size = _vector_from_array(
		control_area_definition.get("size", []),
		Vector2(124, 41),
	)
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	map_border = Panel.new()
	map_border.name = "MapBorder"
	map_border.add_theme_stylebox_override("panel", _border_style())
	map_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_border)
	map_viewport = Control.new()
	map_viewport.name = "MapViewport"
	map_viewport.clip_contents = true
	map_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(map_viewport)
	map_image = TextureRect.new()
	map_image.name = "DedicatedMapImage"
	map_image.texture = map_texture
	map_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_image.stretch_mode = TextureRect.STRETCH_KEEP
	map_image.modulate.a = 200.0 / 255.0
	map_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_image.size = map_texture.get_size() if map_texture else Vector2(300, 300)
	map_viewport.add_child(map_image)
	marker_layer = Control.new()
	marker_layer.name = "Markers"
	marker_layer.size = map_image.size
	marker_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_image.add_child(marker_layer)
	player_dot = ColorRect.new()
	player_dot.name = "PlayerDot"
	player_dot.color = Color(0.2, 1.0, 0.35)
	player_dot.size = Vector2(6, 6)
	player_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(player_dot)

	control_background = TextureRect.new()
	control_background.name = "ControlBackground"
	control_background.texture = _load_primary_texture(definition.get("control_background", {}))
	control_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	control_background.stretch_mode = TextureRect.STRETCH_KEEP
	control_background.size = _vector_from_array(
		definition.get("control_background", {}).get("size", []),
		Vector2(121, 23),
	)
	control_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(control_background)
	coordinate_label = Label.new()
	coordinate_label.name = "Coordinates"
	coordinate_label.position = _vector_from_array(definition.get("coordinate_position", []), Vector2(10, 4))
	coordinate_label.size = Vector2(75, 18)
	coordinate_label.add_theme_font_size_override("font_size", 12)
	coordinate_label.add_theme_color_override("font_color", Color.WHITE)
	coordinate_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	coordinate_label.add_theme_constant_override("shadow_offset_x", 1)
	coordinate_label.add_theme_constant_override("shadow_offset_y", 1)
	coordinate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_background.add_child(coordinate_label)
	map_name_label = Label.new()
	map_name_label.name = "MapName"
	map_name_label.text = display_name
	map_name_label.position = _vector_from_array(definition.get("map_name_position", []), Vector2(0, 24))
	map_name_label.size = Vector2(125, 18)
	map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name_label.add_theme_font_size_override("font_size", 12)
	map_name_label.add_theme_color_override("font_color", Color(0.1, 1.0, 0.25))
	map_name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	map_name_label.add_theme_constant_override("shadow_offset_x", 1)
	map_name_label.add_theme_constant_override("shadow_offset_y", 1)
	map_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control_background.add_child(map_name_label)

	_build_state_buttons()
	hud_state.minimap_size_changed.connect(_apply_layout)
	hud_state.minimap_collapsed_changed.connect(_apply_layout)
	hud_state.player_position_changed.connect(update_player_position)
	_apply_layout()
	update_player_position(hud_state.player_position)


## 把 [param world_position] 投影到小地图像素并更新坐标文本。
func update_player_position(world_position: Vector2) -> void:
	if not map_viewport:
		return
	var map_pixel := world_position / world_size * map_image.size
	if hud_state.minimap_size == "large" and not hud_state.minimap_collapsed:
		map_image.position = Vector2.ZERO
		player_dot.position = map_viewport.position + map_pixel - player_dot.size * 0.5
	else:
		map_image.position = map_viewport.size * 0.5 - map_pixel
		player_dot.position = map_viewport.position + map_viewport.size * 0.5 - player_dot.size * 0.5
	coordinate_label.text = "%d,%d" % [roundi(world_position.x), roundi(world_position.y)]


## 原子替换当前地图尺寸、[param minimap_texture] 与 [param display_name]，并重新投影玩家点。
## [param world_map_size] 新地图的世界像素尺寸。
## Design: 外框、大小模式及收起状态属于 HUD 偏好，不随地图切换重建。
func set_map(
	world_map_size: Vector2,
	minimap_texture: Texture2D,
	display_name: String,
) -> void:
	world_size = Vector2(maxf(world_map_size.x, 1.0), maxf(world_map_size.y, 1.0))
	map_texture = minimap_texture
	map_image.texture = map_texture
	map_image.size = map_texture.get_size() if map_texture else Vector2(300, 300)
	marker_layer.size = map_image.size
	map_name_label.text = display_name
	_apply_layout()


## 构建大小切换和展开/收起两组状态按钮并绑定 HUD 状态。
func _build_state_buttons() -> void:
	var toggle_size: Dictionary = definition.get("toggle_size", {})
	for config in [
		{"id": "to_large", "definition": toggle_size.get("to_large", {}), "callback": hud_state.set_minimap_size.bind("large")},
		{"id": "to_small", "definition": toggle_size.get("to_small", {}), "callback": hud_state.set_minimap_size.bind("small")},
	]:
		var button := _state_button(config["definition"], config["id"], "切换小地图大小")
		button.pressed.connect(config["callback"])
		control_background.add_child(button)
		size_buttons[config["id"]] = button
	var toggle_visibility: Dictionary = definition.get("toggle_visibility", {})
	for config in [
		{"id": "collapse", "definition": toggle_visibility.get("collapse", {}), "callback": hud_state.set_minimap_collapsed.bind(true)},
		{"id": "expand", "definition": toggle_visibility.get("expand", {}), "callback": hud_state.set_minimap_collapsed.bind(false)},
	]:
		var button := _state_button(config["definition"], config["id"], "收起/显示小地图")
		button.pressed.connect(config["callback"])
		control_background.add_child(button)
		collapse_buttons[config["id"]] = button


## 根据 HUD 状态重新排布地图与控制区；[param _unused] 用于兼容无关信号载荷。
func _apply_layout(_unused: Variant = null) -> void:
	var collapsed := hud_state.minimap_collapsed
	var large := hud_state.minimap_size == "large"
	var map_size := map_image.size if large else small_view.size
	var control_position := Vector2(
		control_area_position.x,
		0.0 if collapsed else (map_size.y if large else control_area_position.y),
	)
	var total_size := collapsed_size if collapsed else (
		Vector2(map_size.x, map_size.y + control_area_size.y) if large else small_size
	)
	size = total_size
	offset_left = -total_size.x
	offset_right = 0.0
	offset_top = 0.0
	offset_bottom = total_size.y
	map_viewport.visible = not collapsed
	map_border.visible = not collapsed
	player_dot.visible = not collapsed
	map_viewport.position = Vector2.ZERO if large else small_view.position
	map_viewport.size = map_size
	map_border.position = map_viewport.position - Vector2.ONE
	map_border.size = map_viewport.size + Vector2(2, 2)
	control_background.position = control_position
	map_name_label.size.x = maxf(total_size.x, 125.0)
	size_buttons["to_large"].visible = not large and not collapsed
	size_buttons["to_small"].visible = large and not collapsed
	collapse_buttons["collapse"].visible = not collapsed
	collapse_buttons["expand"].visible = collapsed
	var size_position := _vector_from_array(definition.get("toggle_size", {}).get("position", []), Vector2(90, 5))
	var visibility_position := _vector_from_array(definition.get("toggle_visibility", {}).get("position", []), Vector2(105, 5))
	for button in size_buttons.values():
		button.place_at(size_position)
	for button in collapse_buttons.values():
		button.place_at(visibility_position)
	update_player_position(hud_state.player_position)
	layout_width_changed.emit(total_size.x)


## 用 [param asset] 创建名为 [param node_name] 且提示为 [param tooltip] 的状态按钮。
## Returns 配置后的旧版像素按钮控件。
func _state_button(asset: Dictionary, node_name: String, tooltip: String) -> Control:
	var button := LegacyStateButtonScript.new()
	button.name = node_name.to_pascal_case()
	button.configure(asset)
	button.hit_button.tooltip_text = tooltip
	return button


## 加载 [param asset] 指向的主纹理。
## Returns 路径有效时返回纹理，否则返回 `null`。
func _load_primary_texture(asset: Dictionary) -> Texture2D:
	var path := String(asset.get("path", asset.get("texture", "")))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 创建小地图视口使用的青色像素边框样式。
## Returns 新建的边框样式。
func _border_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0.12, 0.14, 0.45)
	style.border_color = Color(0.0, 0.75, 0.8)
	style.set_border_width_all(1)
	return style


## 将 [param value] 的前两个数值元素转换为坐标，格式不合法时返回 [param fallback]。
## Returns 解析后的二维向量。
func _vector_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
