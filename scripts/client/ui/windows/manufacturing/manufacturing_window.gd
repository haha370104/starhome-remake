class_name ManufacturingWindow
extends DraggableGameWindow

signal command_requested(command: Dictionary)

const REGULAR_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const BOLD_FONT := preload("res://assets/ui/fonts/legacy_panel_bold_font.tres")
const WINDOW_SIZE := Vector2(560, 450)
const TEXT_COLOR := Color("faf0c8")

var _station_id := "tailoring"
var _snapshot: Dictionary = {}
var _inventory_revision := -1
var _title_label: Label
var _recipe_list: VBoxContainer
var _detail_label: Label
var _status_label: Label


## 创建非模态生产窗口的固定布局。
func _ready() -> void:
	configure(WINDOW_SIZE, null, Vector2(532, 12))
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(panel)
	_title_label = _label("Title", Vector2(34, 12), Vector2(492, 24), 16, BOLD_FONT)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(16, 54)
	scroll.size = Vector2(300, 346)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content_root.add_child(scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recipe_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_recipe_list)
	_detail_label = _label("RecipeDetail", Vector2(330, 58), Vector2(214, 300), 12, REGULAR_FONT)
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_status_label = _label("Status", Vector2(20, 410), Vector2(520, 20), 12, REGULAR_FONT)


## 打开指定设施窗口并请求权威配方与背包状态。
## [param requested_station_id] 由当前地图机器声明的生产设施类型。
func open_station(requested_station_id: String) -> void:
	_station_id = requested_station_id
	_snapshot.clear()
	_inventory_revision = -1
	visible = true
	move_to_front()
	_render()
	command_requested.emit({"type": "query_manufacturing", "station_id": _station_id})


## 应用权威服务器返回的生产与背包组合快照。
## [param bundle] 含 manufacturing 和 inventory 的面板 bundle。
func apply_manufacturing_bundle(bundle: Dictionary) -> void:
	var value: Variant = bundle.get("manufacturing", {})
	if not value is Dictionary:
		return
	if String(value.get("station_id", "")) != _station_id:
		return
	_snapshot = (value as Dictionary).duplicate(true)
	_station_id = String(_snapshot.get("station_id", _station_id))
	var inventory_value: Variant = bundle.get("inventory", {})
	if inventory_value is Dictionary:
		_inventory_revision = int((inventory_value as Dictionary).get("revision", -1))
	_render()


## 读取当前生产窗口绑定的设施标识，供运行时回归测试使用。
## 返回当前生产设施类型。
func station_id() -> String:
	return _station_id


## 按最新快照重建配方按钮、详情和生产结果。
func _render() -> void:
	if not is_node_ready():
		return
	_title_label.text = String(_snapshot.get(
		"display_name", "正在读取生产配方…"
	))
	for child: Node in _recipe_list.get_children():
		child.queue_free()
	var recipes_value: Variant = _snapshot.get("recipes", [])
	if recipes_value is Array:
		for value: Variant in recipes_value:
			if value is Dictionary:
				_recipe_list.add_child(_recipe_button(value as Dictionary))
	_detail_label.text = "选择配方查看所需材料"
	var operation: Dictionary = _snapshot.get("operation", {})
	if String(operation.get("action", "")) == "craft":
		_status_label.text = "制作成功" if bool(operation.get("succeeded", false)) else "制作失败，材料已消耗"
	else:
		_status_label.text = "配方与结算由权威服务器控制"


## 为一条配方创建可悬浮查看、可点击制作的按钮。
## [param recipe] 服务端投影的配方状态。
## 返回已绑定交互的按钮。
func _recipe_button(recipe: Dictionary) -> Button:
	var button := Button.new()
	button.text = "%3d级  %s" % [
		int(recipe.get("required_skill_level", 0)),
		String(recipe.get("display_name", "未知配方")),
	]
	button.custom_minimum_size = Vector2(282, 26)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_override("font", REGULAR_FONT)
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.disabled = not bool(recipe.get("can_craft", false))
	button.mouse_entered.connect(_show_recipe.bind(recipe.duplicate(true)))
	button.pressed.connect(_request_craft.bind(recipe.duplicate(true)))
	return button


## 在右栏展示配方等级、成功率和逐项材料进度。
## [param recipe] 当前悬浮的配方快照。
func _show_recipe(recipe: Dictionary) -> void:
	var lines := PackedStringArray([
		String(recipe.get("display_name", "")),
		"需求等级：%d（当前 %d）" % [
			int(recipe.get("required_skill_level", 0)),
			int(recipe.get("effective_skill_level", 0)),
		],
		"成功率：%d%%" % roundi(float(recipe.get("success_probability", 0.0)) * 100.0),
		"产量：%d" % int(recipe.get("output_quantity", 1)),
		"",
		"所需材料：",
	])
	for value: Variant in recipe.get("materials", []):
		if value is Dictionary:
			var material_view: Dictionary = value
			lines.append("%s  %d/%d" % [
				String(material_view.get("display_name", "材料")),
				int(material_view.get("owned", 0)),
				int(material_view.get("required", 0)),
			])
	_detail_label.text = "\n".join(lines)


## 提交只含配方 ID、设施 ID 和背包 revision 的生产意图。
## [param recipe] 被点击的权威配方快照。
func _request_craft(recipe: Dictionary) -> void:
	if _inventory_revision < 0:
		return
	command_requested.emit({
		"type": "craft_recipe",
		"station_id": _station_id,
		"recipe_id": String(recipe.get("recipe_id", "")),
		"inventory_revision": _inventory_revision,
	})


## 创建生产窗口内的统一文本控件。
## [param label_name] 节点名称。
## [param label_position] 窗口局部坐标。
## [param label_size] 固定显示尺寸。
## [param font_size] 字号。
## [param font] 使用的字体资源。
## 返回加入 content_root 的 Label。
func _label(
	label_name: String,
	label_position: Vector2,
	label_size: Vector2,
	font_size: int,
	font: Font,
) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = label_position
	label.size = label_size
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(label)
	return label


## 创建与现有免费版窗口一致的深蓝描边背景。
## 返回窗口背景样式。
func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("00182df4")
	style.border_color = Color("45bee9")
	style.set_border_width_all(2)
	style.shadow_color = Color(0, 0, 0, 0.8)
	style.shadow_size = 5
	return style
