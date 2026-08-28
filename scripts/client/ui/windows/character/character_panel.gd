class_name CharacterPanel
extends DraggableGameWindow

signal command_requested(command: Dictionary)

const BACKGROUND := preload("res://assets/ui/windows/character/background.png")
const PORTRAIT_BACKGROUND := preload("res://assets/ui/windows/character/portrait_background.jpg")
const BODY_MALE := preload("res://assets/ui/windows/character/body_male.png")
const BODY_FEMALE := preload("res://assets/ui/windows/character/body_female.png")

var _portrait_body: TextureRect
var _info_label: Label
var _description_label: Label
var _buff_root: GridContainer
var _equipment_layers: Control
var _worn_root: HBoxContainer
var _inventory_revision := -1
var _state_revision := -1


## 创建荣耀版人物面板固定布局。
## 设计：人物详情使用独立 dialog 立绘组合，不复用世界八向动画。
func _ready() -> void:
	configure(Vector2(355, 450), BACKGROUND, Vector2(327, 39))
	_build_portrait()
	_equipment_layers = Control.new()
	_equipment_layers.name = "EquipmentLayers"
	_equipment_layers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_equipment_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_equipment_layers)
	_worn_root = HBoxContainer.new()
	_worn_root.position = Vector2(24, 275)
	_worn_root.size = Vector2(160, 24)
	content_root.add_child(_worn_root)
	_info_label = _label(Vector2(193, 55), Vector2(145, 245), 13)
	_description_label = _label(Vector2(30, 310), Vector2(295, 58), 12)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buff_root = GridContainer.new()
	_buff_root.name = "BuffGrid"
	_buff_root.columns = 8
	_buff_root.position = Vector2(15, 373)
	_buff_root.size = Vector2(310, 60)
	_buff_root.add_theme_constant_override("h_separation", 15)
	_buff_root.add_theme_constant_override("v_separation", 8)
	content_root.add_child(_buff_root)


## 应用权威 CharacterPanelSnapshot。
## [param snapshot] 服务端返回的身份、成长、穿着和 buff 快照。
func apply_snapshot(snapshot: Dictionary) -> void:
	_state_revision = int(snapshot.get("revision", -1))
	var sex := String(snapshot.get("sex", "male"))
	_portrait_body.texture = BODY_FEMALE if sex == "female" else BODY_MALE
	_info_label.text = "姓名：%s\n等级：%d\n职业：%s\n阵营：%s\n居所：%s\n生命：%d / %d\n经验：%d" % [
		String(snapshot.get("display_name", "未知")),
		int(snapshot.get("level", 1)),
		String(snapshot.get("profession", "未知")),
		String(snapshot.get("faction", "未知")),
		String(snapshot.get("residence", "未知")),
		int(snapshot.get("health", 0)),
		int(snapshot.get("max_health", 0)),
		int(snapshot.get("experience", 0)),
	]
	_description_label.text = String(snapshot.get("description", ""))
	for child in _equipment_layers.get_children():
		child.queue_free()
	for child in _worn_root.get_children():
		child.queue_free()
	var worn_items: Array = snapshot.get("worn_items", [])
	worn_items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("z_layer", 0)) < int(right.get("z_layer", 0))
	)
	for raw_item: Variant in worn_items:
		if raw_item is Dictionary:
			_add_equipment_layer(raw_item)
			_add_worn_button(raw_item)
	for child in _buff_root.get_children():
		child.queue_free()
	var buffs: Array = snapshot.get("buffs", [])
	buffs.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("priority", 0)) > int(right.get("priority", 0))
	)
	for raw_buff: Variant in buffs.slice(0, 16):
		if not raw_buff is Dictionary:
			continue
		var buff := ColorRect.new()
		buff.custom_minimum_size = Vector2(21, 21)
		buff.color = Color(0.2, 0.65, 1.0, 0.7)
		buff.tooltip_text = String(raw_buff.get("tooltip", "状态效果"))
		_buff_root.add_child(buff)


## 同步背包 revision，使人物卸装命令可进行乐观锁校验。
## [param inventory_revision] 当前权威背包 revision。
func set_inventory_revision(inventory_revision: int) -> void:
	_inventory_revision = inventory_revision


## 将一件服装的 dialog 图按 ALE origin 叠加到人物立绘。
## [param equipment] 带 dialog_texture、anchor 和 origin 的穿着快照。
func _add_equipment_layer(equipment: Dictionary) -> void:
	var texture_path := String(equipment.get("dialog_texture", ""))
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path):
		return
	var anchor_value: Array = equipment.get("dialog_anchor", [91, 274])
	var origin_value: Array = equipment.get("dialog_origin", [0, 0])
	var texture := load(texture_path) as Texture2D
	var layer := TextureRect.new()
	layer.texture = texture
	layer.position = Vector2(
		float(anchor_value[0]) + float(origin_value[0]),
		float(anchor_value[1]) + float(origin_value[1]),
	)
	layer.size = texture.get_size()
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_equipment_layers.add_child(layer)


## 创建可双击卸下的穿着槽位按钮。
## [param equipment] 当前穿着装备快照。
func _add_worn_button(equipment: Dictionary) -> void:
	var button := Button.new()
	button.text = String(equipment.get("display_name", "服装"))
	button.custom_minimum_size = Vector2(150, 22)
	button.tooltip_text = "双击脱下"
	button.gui_input.connect(_on_worn_gui_input.bind(String(equipment.get("slot_id", "upper_body"))))
	_worn_root.add_child(button)


## 处理穿着槽位双击并提交卸装命令。
## [param event] Godot GUI 输入事件。
## [param slot_id] 人物业务槽位名。
func _on_worn_gui_input(event: InputEvent, slot_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.double_click:
		command_requested.emit({
			"type": "unequip_character_item",
			"character_slot": slot_id,
			"inventory_revision": _inventory_revision,
			"state_revision": _state_revision,
		})


## 创建人物立绘背景与基础身体层。
func _build_portrait() -> void:
	var portrait_background := TextureRect.new()
	portrait_background.texture = PORTRAIT_BACKGROUND
	portrait_background.position = Vector2(17, 44)
	portrait_background.size = Vector2(173, 259)
	portrait_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(portrait_background)
	_portrait_body = TextureRect.new()
	_portrait_body.name = "Body"
	_portrait_body.texture = BODY_MALE
	_portrait_body.position = Vector2(74 - 35, 231 - 211)
	_portrait_body.size = Vector2(59, 228)
	_portrait_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_body.stretch_mode = TextureRect.STRETCH_KEEP
	_portrait_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_portrait_body)


## 创建统一风格的只读文字标签。
## [param label_position] 标签左上角。
## [param label_size] 标签尺寸。
## [param font_size] 字号。
## 返回已加入面板内容根节点的 Label。
func _label(label_position: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	content_root.add_child(label)
	return label
