class_name FreeBottomMainBar
extends Control

signal action_requested(action_id: String)

const LegacyStateButtonScript := preload("res://scripts/ui/legacy_state_button.gd")
const DESIGN_SIZE := Vector2(1024, 29)
const MENU_BUTTONS := {
	"character": "人物",
	"inventory": "背包",
	"vehicle_equipment": "战车装备",
	"friends": "好友",
	"scene_players": "当前场景玩家",
	"missions": "任务",
	"star_map": "星图",
	"system": "系统",
}

var hud_state: HudState
var design_surface: Control
var reserve_energy_clip: Control
var reserve_energy_fill: TextureRect
var weapon_buttons: Dictionary = {}
var shortcut_visibility_buttons: Dictionary = {}


## 执行 `configure` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param shortcut_definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：中央 1024×29 设计面保持原始像素；宽屏两侧透明，不伪造免费版不存在的蓝色底板。
func configure(definition: Dictionary, shortcut_definition: Dictionary, state: HudState) -> void:
	name = "BottomMainBar"
	hud_state = state
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -29.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background_definition: Dictionary = definition.get("background", {})
	design_surface = Control.new()
	design_surface.name = "DesignSurface"
	design_surface.set_anchors_preset(Control.PRESET_CENTER)
	design_surface.offset_left = -512.0
	design_surface.offset_right = 512.0
	design_surface.offset_top = -14.5
	design_surface.offset_bottom = 14.5
	design_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(design_surface)

	var background := TextureRect.new()
	background.name = "Background"
	background.texture = _load_primary_texture(background_definition)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP
	background.size = DESIGN_SIZE
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	design_surface.add_child(background)

	_build_reserve_energy(definition.get("reserve_energy", {}))
	var weapons: Dictionary = definition.get("weapons", {})
	_build_weapon_button("energy_cannon", weapons.get("energy_cannon", {}), "")
	_build_weapon_button("missile", weapons.get("missile", {}), "1700")
	_build_weapon_button("third_action", weapons.get("third_action", {}), "")

	var buttons: Dictionary = definition.get("menu_buttons", {})
	for action_id in MENU_BUTTONS:
		var button_definition: Dictionary = buttons.get(action_id, {})
		var button := _build_state_button(button_definition, action_id, MENU_BUTTONS[action_id])
		button.place_at(_vector_from_array(button_definition.get("position", []), Vector2.ZERO))
		button.pressed.connect(func() -> void: action_requested.emit(action_id))
		design_surface.add_child(button)

	var toggle_position := _vector_from_array(
		definition.get("shortcut_visibility_button_position", []),
		Vector2(475, 2),
	)
	for toggle_id in ["collapse", "expand"]:
		var toggle_definition: Dictionary = shortcut_definition.get("%s_button" % toggle_id, {})
		var shortcut_toggle := _build_state_button(
			toggle_definition,
			"shortcut_%s" % toggle_id,
			"隐藏快捷栏" if toggle_id == "collapse" else "显示快捷栏",
		)
		shortcut_toggle.place_at(toggle_position)
		shortcut_toggle.pressed.connect(hud_state.set_shortcut_visible.bind(toggle_id == "expand"))
		design_surface.add_child(shortcut_toggle)
		shortcut_visibility_buttons[toggle_id] = shortcut_toggle

	hud_state.reserve_energy_changed.connect(_update_reserve_energy)
	hud_state.selected_action_slot_changed.connect(_update_selected_weapon)
	hud_state.shortcut_visibility_changed.connect(_update_shortcut_visibility_button)
	_update_reserve_energy(hud_state.reserve_energy, hud_state.reserve_energy_capacity)
	_update_selected_weapon(hud_state.selected_action_slot)
	_update_shortcut_visibility_button(hud_state.shortcut_visible)


## 执行 `build_reserve_energy` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _build_reserve_energy(definition: Dictionary) -> void:
	reserve_energy_clip = Control.new()
	reserve_energy_clip.name = "ReserveEnergyClip"
	reserve_energy_clip.position = _vector_from_array(definition.get("position", []), Vector2(125, 3))
	reserve_energy_clip.size = Vector2(
		float(definition.get("crop_width", 323)),
		float(definition.get("crop_height", 3)),
	)
	reserve_energy_clip.clip_contents = true
	reserve_energy_clip.mouse_filter = Control.MOUSE_FILTER_STOP
	design_surface.add_child(reserve_energy_clip)
	reserve_energy_fill = TextureRect.new()
	reserve_energy_fill.name = "ReserveEnergyFill"
	reserve_energy_fill.texture = _load_primary_texture(definition)
	reserve_energy_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reserve_energy_fill.stretch_mode = TextureRect.STRETCH_KEEP
	reserve_energy_fill.size = reserve_energy_clip.size
	reserve_energy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reserve_energy_clip.add_child(reserve_energy_fill)


## 执行 `build_weapon_button` 对应的模块操作。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param count_text] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _build_weapon_button(
	action_id: String,
	definition: Dictionary,
	count_text: String,
) -> void:
	var anchor := _vector_from_array(definition.get("position", []), Vector2.ZERO)
	var button := _build_state_button(definition, action_id, action_id)
	button.place_at(anchor)
	button.pressed.connect(hud_state.set_selected_action_slot.bind(action_id))
	design_surface.add_child(button)
	weapon_buttons[action_id] = button
	if not count_text.is_empty():
		var label := Label.new()
		label.name = "%sAmmo" % action_id.to_pascal_case()
		label.text = count_text
		label.position = anchor + Vector2(2, 10)
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color.RED)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		design_surface.add_child(label)


## 执行 `update_shortcut_visibility_button` 对应的模块操作。
## [param visible] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _update_shortcut_visibility_button(visible: bool) -> void:
	shortcut_visibility_buttons["collapse"].visible = visible
	shortcut_visibility_buttons["expand"].visible = not visible


## 执行 `update_reserve_energy` 对应的模块操作。
## [param current] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param capacity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _update_reserve_energy(current: float, capacity: float) -> void:
	var ratio := clampf(current / capacity, 0.0, 1.0) if capacity > 0.0 else 0.0
	reserve_energy_clip.size.x = 323.0 * ratio
	reserve_energy_clip.tooltip_text = "储备能量 %.0f/%.0f" % [current, capacity]


## 执行 `update_selected_weapon` 对应的模块操作。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _update_selected_weapon(action_id: String) -> void:
	for button_id in weapon_buttons:
		var button: Control = weapon_buttons[button_id]
		button.set_base_state("selected" if button_id == action_id else "normal")


## 执行 `build_state_button` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param tooltip] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _build_state_button(definition: Dictionary, action_id: String, tooltip: String) -> Control:
	var button := LegacyStateButtonScript.new()
	button.name = action_id.to_pascal_case()
	button.configure(definition)
	button.hit_button.tooltip_text = tooltip
	return button


## 执行 `load_primary_texture` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_primary_texture(definition: Dictionary) -> Texture2D:
	var path := String(definition.get("path", definition.get("texture", "")))
	if path.is_empty():
		var frames: Variant = definition.get("frames", [])
		if frames is Array and not frames.is_empty():
			path = String(frames[0])
		elif frames is Dictionary:
			path = String(frames.get("steady", frames.values()[0] if not frames.is_empty() else ""))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 执行 `vector_from_array` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fallback] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _vector_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
