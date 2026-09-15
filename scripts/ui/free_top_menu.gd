class_name FreeTopMenu
extends Control

signal action_requested(action_id: String)

const LegacyStateButtonScript := preload("res://scripts/ui/legacy_state_button.gd")
const BUTTONS := {
	"party": "队伍", "return_base": "返回基地", "self_repair": "自维修", "summon_guard": "召唤守卫",
	"smart_assistant": "智脑系统", "central_controller": "中枢控制", "mercenary": "佣兵任务", "experience": "人物历练",
}

var minimap_width := 125.0
var hud_state: HudState
var background: Panel
var collapse_button: Control
var expand_button: Control
var action_buttons: Dictionary = {}
var expanded_size := Vector2(326, 82)
var collapsed_size := Vector2(12, 26)


## 执行 `configure` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：八个语义按钮排列为两行四列，依据小地图宽度重新锚定。
func configure(definition: Dictionary, state: HudState) -> void:
	name = "TopMenu"
	hud_state = state
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expanded_size = Vector2(326, 82)
	collapsed_size = Vector2(12, 26)
	background = Panel.new()
	background.name = "Background"
	background.size = expanded_size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("142631e8")
	style.border_color = Color("397c90")
	style.set_border_width_all(1)
	style.set_corner_radius_all(5)
	background.add_theme_stylebox_override("panel", style)
	add_child(background)
	var index := 0
	for action_id: String in BUTTONS:
		var button := Button.new()
		button.name = action_id.to_pascal_case()
		button.text = BUTTONS[action_id]
		button.tooltip_text = BUTTONS[action_id] + ("（Z）" if action_id == "self_repair" else "")
		button.position = Vector2(18 + (index % 4) * 76, 5 + floori(float(index) / 4.0) * 37)
		button.size = Vector2(73, 34)
		button.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_font.tres"))
		button.add_theme_font_size_override("font_size", 14)
		button.pressed.connect(func() -> void: action_requested.emit(action_id))
		add_child(button)
		action_buttons[action_id] = button
		index += 1

	var collapse_definition: Dictionary = definition.get("collapse_button", {})
	collapse_button = _build_button(collapse_definition, "collapse", "收起顶部工具栏")
	collapse_button.place_at(_vector_from_array(collapse_definition.get("position", []), Vector2(1, 1)))
	collapse_button.pressed.connect(hud_state.set_top_menu_expanded.bind(false))
	add_child(collapse_button)
	var expand_definition: Dictionary = definition.get("expand_button", {})
	expand_button = _build_button(expand_definition, "expand", "展开顶部工具栏")
	expand_button.place_at(_vector_from_array(expand_definition.get("position", []), Vector2(1, 1)))
	expand_button.pressed.connect(hud_state.set_top_menu_expanded.bind(true))
	add_child(expand_button)
	hud_state.top_menu_expanded_changed.connect(_apply_expanded)
	_apply_expanded(hud_state.top_menu_expanded)


## 执行 `set_minimap_width` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_minimap_width(value: float) -> void:
	minimap_width = value
	_update_anchor()


## 执行 `apply_expanded` 对应的模块操作。
## [param expanded] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _apply_expanded(expanded: bool) -> void:
	background.visible = expanded
	for button in action_buttons.values():
		button.visible = expanded
	collapse_button.visible = expanded
	expand_button.visible = not expanded
	_update_anchor()


## 按当前控件尺寸与小地图宽度更新顶部菜单锚点偏移。
func _update_anchor() -> void:
	var target_size := expanded_size if hud_state.top_menu_expanded else collapsed_size
	offset_left = -minimap_width - target_size.x
	offset_right = -minimap_width
	offset_top = 0.0
	offset_bottom = target_size.y


## 执行 `build_button` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param tooltip] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _build_button(definition: Dictionary, action_id: String, tooltip: String) -> Control:
	var button := LegacyStateButtonScript.new()
	button.name = action_id.to_pascal_case()
	button.configure(definition)
	button.hit_button.tooltip_text = tooltip
	if action_id not in ["collapse", "expand"]:
		button.pressed.connect(func() -> void: action_requested.emit(action_id))
	return button


## 执行 `load_primary_texture` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_primary_texture(definition: Dictionary) -> Texture2D:
	var path := String(definition.get("path", definition.get("texture", "")))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 执行 `vector_from_array` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fallback] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _vector_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
