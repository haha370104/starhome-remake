class_name FreeBottomMainBar
extends Control

signal action_requested(action_id: String)

const LegacyStateButtonScript := preload("res://scripts/ui/legacy_state_button.gd")
const DESIGN_SIZE := Vector2(1024, 29)
const MENU_BUTTONS := {
	"character": "人物属性",
	"inventory": "背包",
	"vehicle_equipment": "战车装备",
	"friends": "好友列表",
	"scene_players": "当前场景玩家",
	"missions": "任务日志",
	"system": "系统设置",
	"achievements": "成就系统",
	"premium_shop": "商城",
}
const WEAPON_TOOLTIPS := {
	"energy_cannon": "能量炮",
	"mining_arm": "采掘臂",
	"repair_arm": "维修臂",
	"missile": "导弹",
	"rocket_launcher": "火箭炮",
	"stealth": "隐身器",
	"radar": "雷达",
}

var hud_state: HudState
var design_surface: Control
var reserve_energy_clip: Control
var reserve_energy_fill: TextureRect
var weapon_buttons: Dictionary = {}
var primary_definitions: Dictionary = {}
var primary_position := Vector2.ZERO
var tactical_definition: Dictionary = {}
var tactical_button: Control
var tactical_count_label: Label
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
	primary_definitions = (weapons.get("primary_modes", {}) as Dictionary).duplicate(true)
	primary_definitions["energy_cannon"] = weapons.get("energy_cannon", {})
	primary_position = _vector_from_array(primary_definitions.energy_cannon.get("position", []), Vector2(178, 8))
	tactical_definition = weapons.get("tactical", {})

	var buttons: Dictionary = definition.get("menu_buttons", {})
	for action_id in MENU_BUTTONS:
		var button_definition: Dictionary = buttons.get(action_id, {})
		if action_id in ["achievements", "premium_shop"]:
			var slot := TextureRect.new()
			slot.texture = preload("res://assets/ui/free_hud/bottom_main/menu_buttons/empty_slot.tres")
			slot.position = _vector_from_array(button_definition.get("position", []), Vector2.ZERO)
			slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			design_surface.add_child(slot)
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
	hud_state.tactical_action_changed.connect(_update_tactical_action)
	hud_state.primary_device_changed.connect(_update_primary_device)
	hud_state.shortcut_visibility_changed.connect(_update_shortcut_visibility_button)
	_update_reserve_energy(hud_state.reserve_energy, hud_state.reserve_energy_capacity)
	_update_tactical_action(hud_state.tactical_action_id, hud_state.tactical_action_count)
	_update_primary_device(hud_state.primary_device_kind)
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
## 返回已按免费版布局创建但尚未加入父节点的武器按钮。
func _build_weapon_button(
	action_id: String,
	definition: Dictionary
) -> Control:
	var anchor := _vector_from_array(definition.get("position", []), Vector2.ZERO)
	var button := _build_state_button(definition, action_id, WEAPON_TOOLTIPS.get(action_id, action_id))
	button.place_at(anchor)
	button.pressed.connect(hud_state.set_selected_action_slot.bind(action_id))
	design_surface.add_child(button)
	weapon_buttons[action_id] = button
	return button


## 依据 Location 13 的权威装备动态创建或清空唯一战术按钮。
## [param action_id] 当前战术装备对应的操作标识，空值表示卸下。
## [param count] 该战术物品的权威可用数量。
func _update_tactical_action(action_id: String, count: int) -> void:
	if tactical_button != null and String(tactical_button.name).to_snake_case() == action_id and tactical_count_label != null and count >= 0:
		tactical_count_label.text = str(count)
		return
	if tactical_button != null:
		weapon_buttons.erase(String(tactical_button.name).to_snake_case())
		tactical_button.free()
		tactical_button = null
	if tactical_count_label != null:
		tactical_count_label.free()
		tactical_count_label = null
	if action_id.is_empty():
		_update_selected_weapon(hud_state.selected_action_slot)
		return
	var modes: Dictionary = tactical_definition.get("modes", {})
	var mode_definition: Dictionary = (modes.get(action_id, {}) as Dictionary).duplicate(true)
	if mode_definition.is_empty():
		return
	mode_definition["position"] = tactical_definition.get("position", [206, 8])
	tactical_button = _build_weapon_button(action_id, mode_definition)
	if count >= 0:
		tactical_count_label = Label.new()
		tactical_count_label.name = "TacticalCount"
		tactical_count_label.text = str(count)
		tactical_count_label.position = _vector_from_array(mode_definition["position"], Vector2.ZERO) + Vector2(2, 10)
		tactical_count_label.add_theme_font_size_override("font_size", 13)
		tactical_count_label.add_theme_color_override("font_color", Color.WHITE)
		tactical_count_label.add_theme_color_override("font_outline_color", Color.BLACK)
		tactical_count_label.add_theme_constant_override("outline_size", 3)
		tactical_count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		design_surface.add_child(tactical_count_label)
	_update_selected_weapon(hud_state.selected_action_slot)


## 按主装置类型重建主槽按钮，保留当前槽选中状态与既有输入协议。
## [param device_kind] 主装置语义类型；空值或无素材时清空，不冒充能量炮。
func _update_primary_device(device_kind: String) -> void:
	var previous: Control = weapon_buttons.get("energy_cannon")
	if previous != null:
		weapon_buttons.erase("energy_cannon")
		previous.hide()
		previous.queue_free()
	var definition: Dictionary = (primary_definitions.get(device_kind, {}) as Dictionary).duplicate(true)
	if definition.is_empty():
		return
	definition["position"] = [primary_position.x, primary_position.y]
	var button := _build_weapon_button("energy_cannon", definition)
	button.hit_button.tooltip_text = WEAPON_TOOLTIPS[device_kind]
	_update_selected_weapon(hud_state.selected_action_slot)


## 执行 `update_shortcut_visibility_button` 对应的模块操作。
## [param should_show] 当前快捷栏是否展开。
func _update_shortcut_visibility_button(should_show: bool) -> void:
	shortcut_visibility_buttons["collapse"].visible = should_show
	shortcut_visibility_buttons["expand"].visible = not should_show


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
