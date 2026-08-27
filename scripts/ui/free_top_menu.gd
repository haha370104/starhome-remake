class_name FreeTopMenu
extends Control

signal action_requested(action_id: String)

const LegacyStateButtonScript := preload("res://scripts/ui/legacy_state_button.gd")
const BUTTONS := {
	"system_messages": "系统消息",
	"help": "帮助",
	"party": "队伍",
	"return_base": "返回基地",
	"self_repair": "自我维修",
}

var minimap_width := 125.0
var hud_state: HudState
var background: TextureRect
var collapse_button: Control
var expand_button: Control
var action_buttons: Dictionary = {}
var expanded_size := Vector2(330, 54)
var collapsed_size := Vector2(12, 26)


## 用 [param definition] 构建免费版顶部菜单，并绑定共享的 [param state]。
## Design: 菜单保持原始像素尺寸，只依据小地图宽度重新锚定，不参与视口缩放。
func configure(definition: Dictionary, state: HudState) -> void:
	name = "TopMenu"
	hud_state = state
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expanded_size = _vector_from_array(definition.get("expanded_size", []), Vector2(330, 54))
	collapsed_size = _vector_from_array(definition.get("collapsed_size", []), Vector2(12, 26))
	background = TextureRect.new()
	background.name = "Background"
	background.texture = _load_primary_texture(definition.get("background", {}))
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP
	background.size = _vector_from_array(
		definition.get("background", {}).get("size", []),
		Vector2(327, 54),
	)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var button_definitions: Dictionary = definition.get("buttons", {})
	for action_id in BUTTONS:
		var button_definition: Dictionary = button_definitions.get(action_id, {})
		var button := _build_button(button_definition, action_id, BUTTONS[action_id])
		button.place_at(_vector_from_array(button_definition.get("position", []), Vector2.ZERO))
		add_child(button)
		action_buttons[action_id] = button

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


## 接收相邻小地图的 [param value] 宽度并重新计算右上角锚点。
func set_minimap_width(value: float) -> void:
	minimap_width = value
	_update_anchor()


## 应用 [param expanded] 展开状态，切换菜单内容与展开/收起按钮。
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


## 从 [param definition] 构建动作 [param action_id] 的按钮并设置 [param tooltip]。
## Returns 已配置且会发出菜单动作信号的按钮控件。
func _build_button(definition: Dictionary, action_id: String, tooltip: String) -> Control:
	var button := LegacyStateButtonScript.new()
	button.name = action_id.to_pascal_case()
	button.configure(definition)
	button.hit_button.tooltip_text = tooltip
	if action_id not in ["collapse", "expand"]:
		button.pressed.connect(func() -> void: action_requested.emit(action_id))
	return button


## 加载 [param definition] 指向的主状态纹理。
## Returns 存在时返回纹理，否则返回 `null`。
func _load_primary_texture(definition: Dictionary) -> Texture2D:
	var path := String(definition.get("path", definition.get("texture", "")))
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 将 [param value] 的前两个数值元素转换为坐标，格式不合法时返回 [param fallback]。
## Returns 解析后的二维向量。
func _vector_from_array(value: Variant, fallback: Vector2) -> Vector2:
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return fallback
