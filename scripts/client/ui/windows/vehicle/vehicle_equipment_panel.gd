class_name VehicleEquipmentPanel
extends DraggableGameWindow

signal command_requested(command: Dictionary)

const EquipmentLayer := preload("res://scripts/client/ui/components/equipment_layer_view.gd")
const BACKGROUND := preload("res://assets/ui/windows/vehicle/background.png")
const LEGACY_PANEL_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const TEXT_COLOR := Color("f6f3e8")
const SLOT_HOVER_COLOR := Color("ffcc00")
const TEXT_FONT_SIZE := 12
const PROPULSION_SLOT_RECT := Rect2(96, 360, 68, 68)
const DISPLAY_LABELS := [
	{"id": 0, "text": "装置0", "position": Vector2(30, 122)},
	{"id": 1, "text": "装置1", "position": Vector2(101, 122), "hover_yellow": true},
	{"id": 2, "text": "旧接合 I", "position": Vector2(172, 122)},
	{"id": 3, "text": "旧接合 II", "position": Vector2(243, 122)},
	{"id": 4, "text": "发生器 I", "position": Vector2(314, 122)},
	{"id": 10, "text": "新接合 I", "position": Vector2(395, 123)},
	{"id": 11, "text": "新接合 II", "position": Vector2(395, 222)},
	{"id": 12, "text": "发生器 II", "position": Vector2(395, 318)},
	{"id": 13, "text": "", "position": Vector2(395, 343)},
	{"id": 5, "text": "宏原子", "position": Vector2(30, 342)},
	{"id": 6, "text": "推进器", "position": Vector2(101, 342)},
	{"id": 7, "text": "装置7", "position": Vector2(172, 342)},
	{"id": 8, "text": "装置8", "position": Vector2(243, 342)},
	{"id": 9, "text": "装置9", "position": Vector2(314, 342)},
]
const STAT_ROWS := [
	{"id": "max_health", "label": "最大生命", "y": 5},
	{"id": "health", "label": "当前生命", "y": 25},
	{"id": "defense", "label": "防御力", "y": 45},
	{"id": "armor_caption", "label": "护甲(前/后/左/右)", "y": 65},
	{"id": "armor_values", "label": "", "y": 85},
	{"id": "speed", "label": "速度", "y": 105},
	{"id": "energy_cannon_attack", "label": "能量炮攻击", "y": 125},
	{"id": "missile_attack", "label": "导弹攻击", "y": 145},
	{"id": "rocket_attack", "label": "火箭攻击", "y": 165},
	{"id": "propulsion", "label": "推动力", "y": 185},
	{"id": "output_power", "label": "输出功率", "y": 205},
	{"id": "weight", "label": "总重量", "y": 225},
	{"id": "self_repair_base", "label": "基础自修", "y": 245},
	{"id": "self_repair_bonus", "label": "自修加成", "y": 265},
	{"id": "extra_repair", "label": "额外维修", "y": 285},
	{"id": "reserve_energy", "label": "储备能量", "y": 305},
	{"id": "working_energy", "label": "工作能量", "y": 325},
]

var _special_panel: SpecialEquipmentPanel
var _preview_root: Control
var _slot_label_root: Control
var _slot_root: Control
var _stat_labels: Dictionary = {}
var _inventory_revision := -1
var _loadout_revision := -1


## 创建荣耀版战车装备面板、像素定位装备层与属性区。
## 设计：装备的 dialog 图既是中央整车组合层也是槽位内容，位置直接采用各装备 EquipInDlg 坐标。
func _ready() -> void:
	configure(Vector2(604, 460), BACKGROUND, Vector2(570, 40))
	_build_slot_labels()
	_slot_root = Control.new()
	_slot_root.name = "EquipmentVisuals"
	_slot_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_slot_root)
	_preview_root = _slot_root
	_build_stat_labels()
	_special_panel = SpecialEquipmentPanel.new()
	content_root.add_child(_special_panel)
	_special_panel.hide()
	_special_panel.unequip_requested.connect(_request_unequip)
	var special_button := Button.new()
	special_button.text = "特殊装备"
	special_button.position = Vector2(386, 352)
	special_button.size = Vector2(66, 30)
	special_button.add_theme_font_size_override("font_size", 12)
	special_button.pressed.connect(_special_panel.show)
	content_root.add_child(special_button)


## 创建荣耀版十四条固定视觉槽位文字。
## 设计：display_id 仅负责外观，逻辑 Location 由领域槽位注册表和快照元数据维护。
func _build_slot_labels() -> void:
	_slot_label_root = Control.new()
	_slot_label_root.name = "EquipmentSlotLabels"
	_slot_label_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slot_label_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_slot_label_root)
	for raw_definition: Dictionary in DISPLAY_LABELS:
		var label := Label.new()
		label.name = "DisplaySlot_%d" % int(raw_definition["id"])
		label.text = String(raw_definition["text"])
		label.position = raw_definition["position"]
		label.size = Vector2(68, 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		label.add_theme_font_override("font", LEGACY_PANEL_FONT)
		label.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
		label.add_theme_color_override("font_color", TEXT_COLOR)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		var hover_yellow := bool(raw_definition.get("hover_yellow", false))
		label.mouse_entered.connect(_set_slot_label_hover.bind(label, true, hover_yellow))
		label.mouse_exited.connect(_set_slot_label_hover.bind(label, false, hover_yellow))
		_slot_label_root.add_child(label)


## 切换固定槽位文字的原版式黄色悬停反馈。
## [param label] 需要更新字体颜色的槽位标签。
## [param hovered] 当前鼠标是否位于标签范围内。
## [param hover_yellow] 原版是否为该条文字配置黄色进入色。
func _set_slot_label_hover(label: Label, hovered: bool, hover_yellow: bool) -> void:
	label.add_theme_color_override(
		"font_color", SLOT_HOVER_COLOR if hovered and hover_yellow else TEXT_COLOR
	)


## 应用权威 VehicleAssemblySnapshot 并按 z_layer 重建装备表现。
## [param snapshot] 服务端返回的装备、revision 与统一战车统计。
func apply_snapshot(snapshot: Dictionary) -> void:
	_loadout_revision = int(snapshot.get("revision", -1))
	for child in _slot_root.get_children():
		child.queue_free()
	var equipped_value: Variant = snapshot.get("equipped", [])
	if equipped_value is Array:
		var equipped: Array = (equipped_value as Array).duplicate(true)
		equipped.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("z_layer", 0)) < int(right.get("z_layer", 0))
		)
		for raw_equipment: Variant in equipped:
			if raw_equipment is Dictionary:
				_add_equipment_visual(raw_equipment)
	_special_panel.apply_equipment(equipped_value if equipped_value is Array else [])
	var stats_value: Variant = snapshot.get("stats", {})
	_update_stat_labels(stats_value if stats_value is Dictionary else {})


## 同步背包 revision，使卸装命令可进行双 revision 乐观锁校验。
## [param inventory_revision] 当前权威背包 revision。
func set_inventory_revision(inventory_revision: int) -> void:
	_inventory_revision = inventory_revision


## 创建右侧以 20 像素为行距的独立属性标签。
func _build_stat_labels() -> void:
	for raw_row: Dictionary in STAT_ROWS:
		var label := Label.new()
		label.name = "Stat_%s" % String(raw_row["id"])
		label.position = Vector2(454, 57 + int(raw_row["y"]))
		label.size = Vector2(134, 18)
		label.add_theme_font_override("font", LEGACY_PANEL_FONT)
		label.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
		label.add_theme_color_override("font_color", TEXT_COLOR)
		label.add_theme_color_override("font_shadow_color", Color.BLACK)
		label.add_theme_constant_override("shadow_offset_x", 1)
		label.add_theme_constant_override("shadow_offset_y", 1)
		content_root.add_child(label)
		_stat_labels[String(raw_row["id"])] = label


## 按旧客户端装备类提供的对话框锚点添加一件已装备物品。
## [param equipment] 带 dialog_texture、anchor、origin、层级和属性的装备快照。
func _add_equipment_visual(equipment: Dictionary) -> void:
	var visual := EquipmentLayer.new()
	var location := int(equipment.get("location", -1))
	if not EquipmentSlotRegistry.special_series(location).is_empty():
		visual.free()
		return
	var slot_rect := PROPULSION_SLOT_RECT if location == 3 else Rect2()
	var attachment_rects := {
		16: Rect2(166, 58, 68, 60), 17: Rect2(237, 58, 68, 60),
		14: Rect2(308, 58, 68, 60), 32: Rect2(386, 62, 62, 56),
		33: Rect2(386, 161, 62, 56), 34: Rect2(386, 257, 62, 56),
	}
	if attachment_rects.has(location):
		slot_rect = attachment_rects[location]
	if not visual.configure(equipment, Vector2(170, 200), slot_rect):
		visual.free()
		return
	visual.name = "Location_%d_%s" % [location, String(equipment.get("definition_id", "equipment"))]
	visual.z_index = int(equipment.get("z_layer", 0))
	visual.gui_input.connect(_on_equipment_gui_input.bind(location))
	_slot_root.add_child(visual)


## 处理装备表现双击并提交卸载意图。
## [param event] Godot GUI 输入事件。
## [param location] 对应战车 Location。
func _on_equipment_gui_input(event: InputEvent, location: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.double_click:
		_request_unequip(location)


## 从主面板或特殊装备区统一提交卸载命令。
## [param location] 实际装配位置。
func _request_unequip(location: int) -> void:
	command_requested.emit({
		"type": "unequip_vehicle_item", "location": location,
		"inventory_revision": _inventory_revision, "loadout_revision": _loadout_revision,
	})


## 刷新右侧属性文字与基础值/附加值提示。
## [param stats] 服务端计算的统一战车统计。
func _update_stat_labels(stats: Dictionary) -> void:
	_set_stat("max_health", "最大生命：%s" % _format_number(stats.get("max_health", 0)),
		_breakdown_tooltip(stats, "max_health"))
	_set_stat("health", "当前生命：%s" % _format_number(stats.get("health", 0)))
	_set_stat("defense", "防御力：%s" % _format_number(stats.get("defense", 0)),
		_breakdown_tooltip(stats, "defense"))
	_set_stat("armor_caption", "护甲(前/后/左/右)：")
	_set_stat("armor_values", "%s / %s / %s / %s" % [
		_format_number(stats.get("armor_front", 0)),
		_format_number(stats.get("armor_rear", 0)),
		_format_number(stats.get("armor_left", 0)),
		_format_number(stats.get("armor_right", 0)),
	])
	for stat_id: String in [
		"speed", "energy_cannon_attack", "missile_attack", "rocket_attack", "propulsion",
		"output_power", "weight", "self_repair_base", "self_repair_bonus", "extra_repair",
	]:
		var row := _row_for(stat_id)
		var value_text := _format_number(stats.get(stat_id, 0), stat_id == "output_power")
		_set_stat(stat_id, "%s：%s" % [String(row.get("label", stat_id)), value_text],
			_breakdown_tooltip(stats, stat_id))
	_set_stat("reserve_energy", "储备能量：%s / %s" % [
		_format_number(stats.get("reserve_energy", 0)),
		_format_number(stats.get("reserve_energy_capacity", 0)),
	])
	_set_stat("working_energy", "工作能量：%s / %s" % [
		_format_number(stats.get("working_energy", 0)),
		_format_number(stats.get("working_energy_capacity", 0)),
	])


## 设置属性标签文本与可选拆分提示。
## [param stat_id] 属性标识。
## [param text] 主显示文本。
## [param tooltip] 基础值与附加值提示；空字符串表示无提示。
func _set_stat(stat_id: String, text: String, tooltip: String = "") -> void:
	var label := _stat_labels.get(stat_id) as Label
	if label == null:
		return
	label.text = text
	label.tooltip_text = tooltip


## 查询属性行的静态布局定义。
## [param stat_id] 属性标识。
## 返回对应行；不存在时返回空字典。
func _row_for(stat_id: String) -> Dictionary:
	for raw_row: Dictionary in STAT_ROWS:
		if String(raw_row["id"]) == stat_id:
			return raw_row
	return {}


## 构造旧客户端 NewEquipAttrText 的基础值与附加值说明。
## [param stats] 权威统计字典。
## [param stat_id] 需要拆分的总值标识。
## 返回存在拆分字段时的提示文本。
func _breakdown_tooltip(stats: Dictionary, stat_id: String) -> String:
	var base_key := "%s_base" % stat_id
	var bonus_key := "%s_bonus" % stat_id
	if not stats.has(base_key) and not stats.has(bonus_key):
		return ""
	return "基础：%s\n附加：+%s" % [
		_format_number(stats.get(base_key, stats.get(stat_id, 0))),
		_format_number(stats.get(bonus_key, 0)),
	]


## 格式化战车属性数值。
## [param value] 整型或浮点型属性。
## [param force_decimal] 是否像原输出功率一样固定保留一位小数。
## 返回适合属性栏的紧凑文本。
func _format_number(value: Variant, force_decimal: bool = false) -> String:
	var number := float(value)
	if force_decimal:
		return "%.1f" % number
	if is_equal_approx(number, floorf(number)):
		return str(int(number))
	return "%.1f" % number
