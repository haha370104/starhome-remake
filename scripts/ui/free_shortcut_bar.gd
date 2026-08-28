class_name FreeShortcutBar
extends Control

signal item_slot_requested(slot_index: int)
signal skill_slot_requested(slot_index: int)

var hud_state: HudState
var item_slots: Array[TextureButton] = []
var skill_slots: Array[TextureButton] = []
var item_page_label: Label
var skill_page_label: Label
var item_page_count := 2
var skill_page_count := 2


## 执行 `configure` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：物品槽与技能槽分别分页和发出业务索引，控件不持有实际物品或技能对象。
func configure(definition: Dictionary, state: HudState) -> void:
	name = "GeneralShortcutBar"
	hud_state = state
	var bar_size := _vector_from_array(definition.get("size", []), Vector2(415, 40))
	item_page_count = maxi(int(definition.get("item_page_count", 2)), 1)
	skill_page_count = maxi(int(definition.get("skill_page_count", 2)), 1)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -bar_size.x * 0.5
	offset_right = bar_size.x * 0.5
	offset_top = -29.0 - bar_size.y
	offset_bottom = -29.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var background := TextureRect.new()
	background.name = "Background"
	background.texture = _load_primary_texture(definition.get("background", {}))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP
	background.size = bar_size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	for index in range(5):
		var slot := _empty_slot("ItemSlot%d" % (index + 1), Vector2(27 + 36 * index, 4), Vector2(31, 31))
		slot.pressed.connect(_emit_item_slot.bind(index))
		add_child(slot)
		item_slots.append(slot)
	for index in range(7):
		var slot := _empty_slot("SkillSlot%d" % (index + 1), Vector2(207 + 26 * index, 2), Vector2(26, 36))
		slot.pressed.connect(_emit_skill_slot.bind(index))
		add_child(slot)
		skill_slots.append(slot)

	_build_page_controls(definition, "item")
	_build_page_controls(definition, "skill")
	hud_state.shortcut_visibility_changed.connect(_apply_visibility)
	hud_state.shortcut_page_changed.connect(_update_page_labels)
	_apply_visibility(hud_state.shortcut_visible)


## 执行 `build_page_controls` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param kind] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _build_page_controls(definition: Dictionary, kind: String) -> void:
	var up_definition: Dictionary = definition.get("page_up", {})
	var down_definition: Dictionary = definition.get("page_down", {})
	var up := _texture_button(up_definition, "%sPageUp" % kind.to_pascal_case())
	up.position = _page_control_position(definition, up_definition, kind, true)
	up.size = _vector_from_array(up_definition.get("size", []), Vector2(10, 9))
	up.pressed.connect(_change_page.bind(kind, -1))
	add_child(up)
	var down := _texture_button(down_definition, "%sPageDown" % kind.to_pascal_case())
	down.position = _page_control_position(definition, down_definition, kind, false)
	down.size = _vector_from_array(down_definition.get("size", []), Vector2(10, 9))
	down.pressed.connect(_change_page.bind(kind, 1))
	add_child(down)
	var page_label := Label.new()
	page_label.name = "%sPage" % kind.to_pascal_case()
	page_label.text = "1"
	page_label.position = Vector2(up.position.x - 1, 12)
	page_label.size = Vector2(12, 16)
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.add_theme_font_size_override("font_size", 9)
	page_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page_label)
	if kind == "item":
		item_page_label = page_label
	else:
		skill_page_label = page_label


## 执行 `change_page` 对应的模块操作。
## [param kind] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _change_page(kind: String, delta: int) -> void:
	var current := hud_state.item_shortcut_page if kind == "item" else hud_state.skill_shortcut_page
	var page_count := item_page_count if kind == "item" else skill_page_count
	hud_state.set_shortcut_page(kind, posmod(current + delta, page_count))


## 执行 `update_page_labels` 对应的模块操作。
## [param kind] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param page] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _update_page_labels(kind: String, page: int) -> void:
	if kind == "item":
		item_page_label.text = str(page + 1)
	else:
		skill_page_label.text = str(page + 1)


## 执行 `apply_visibility` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _apply_visibility(value: bool) -> void:
	visible = value


## 执行 `emit_item_slot` 对应的模块操作。
## [param index] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _emit_item_slot(index: int) -> void:
	item_slot_requested.emit(hud_state.item_shortcut_page * 5 + index)


## 执行 `emit_skill_slot` 对应的模块操作。
## [param index] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _emit_skill_slot(index: int) -> void:
	skill_slot_requested.emit(hud_state.skill_shortcut_page * 7 + index)


## 执行 `empty_slot` 对应的模块操作。
## [param node_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param position_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param size_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _empty_slot(node_name: String, position_value: Vector2, size_value: Vector2) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.position = position_value
	button.size = size_value
	button.ignore_texture_size = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


## 执行 `texture_button` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param node_name] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _texture_button(definition: Dictionary, node_name: String) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	var states: Dictionary = definition.get("states", {})
	var path := String(states.get("normal", definition.get("path", "")))
	button.texture_normal = load(path) as Texture2D if ResourceLoader.exists(path) else null
	button.texture_hover = button.texture_normal
	button.texture_pressed = button.texture_normal
	button.ignore_texture_size = true
	button.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return button


## 执行 `load_primary_texture` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_primary_texture(definition: Dictionary) -> Texture2D:
	var path := String(definition.get("path", definition.get("texture", "")))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 执行 `page_control_position` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param button_definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param kind] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param is_up] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _page_control_position(
	definition: Dictionary,
	button_definition: Dictionary,
	kind: String,
	is_up: bool,
) -> Vector2:
	if kind == "item":
		return _vector_from_array(button_definition.get("position", []), Vector2(15, 4 if is_up else 20))
	var key := "skill_page_up_position" if is_up else "skill_page_down_position"
	return _vector_from_array(definition.get(key, []), Vector2(391, 4 if is_up else 20))


## 执行 `vector_from_array` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fallback] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _vector_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
