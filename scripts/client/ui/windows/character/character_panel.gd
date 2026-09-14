class_name CharacterPanel
extends DraggableGameWindow

signal command_requested(command: Dictionary)
signal skill_panel_requested

const EquipmentLayer := preload("res://scripts/client/ui/components/equipment_layer_view.gd")
const BACKGROUND := preload("res://assets/ui/windows/character/background.png")
const PORTRAIT_BACKGROUND := preload("res://assets/ui/windows/character/portrait_background.jpg")
const BODY_MALE := preload("res://assets/ui/windows/character/body_male.png")
const BODY_FEMALE := preload("res://assets/ui/windows/character/body_female.png")
const LEGACY_PANEL_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const TEXT_COLOR := Color("faf0c8")
const TEXT_FONT_SIZE := 12

var _portrait_body: TextureRect
var _field_labels: Dictionary = {}
var _description_label: Label
var _buff_root: GridContainer
var _equipment_layers: Control
var _skill_button: Button
var _inventory_revision := -1
var _state_revision := -1


## 创建荣耀版人物面板的固定像素布局与查看技能入口。
## 设计：人物立绘按 ALE 锚点组合，资料字段独立定位，避免多行 Label 的字体度量造成错位。
func _ready() -> void:
	configure(Vector2(355, 450), BACKGROUND, Vector2(327, 39))
	_build_portrait()
	_build_identity_fields()
	_description_label = _create_label(Vector2(30, 310), Vector2(295, 58), 12)
	_description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_buff_root = GridContainer.new()
	_buff_root.name = "BuffGrid"
	_buff_root.columns = 8
	_buff_root.position = Vector2(69, 382)
	_buff_root.size = Vector2(168, 44)
	_buff_root.add_theme_constant_override("h_separation", 0)
	_buff_root.add_theme_constant_override("v_separation", 0)
	content_root.add_child(_buff_root)


## 应用权威 CharacterPanelSnapshot。
## [param snapshot] 服务端返回的身份、成长、技能、穿着和 buff 快照。
func apply_snapshot(snapshot: Dictionary) -> void:
	_state_revision = int(snapshot.get("revision", -1))
	var sex := String(snapshot.get("sex", "male"))
	_portrait_body.texture = BODY_FEMALE if sex == "female" else BODY_MALE
	_portrait_body.position = Vector2(52, 73) if sex == "female" else Vector2(56, 64)
	_set_field("display_name", "姓名：%s" % String(snapshot.get("display_name", "未知")))
	_set_field("level", "综合等级：%d" % int(snapshot.get("level", 10)))
	_set_field("profession", "职业：%s" % String(snapshot.get("profession", "未知")))
	_set_field("faction", "阵营：%s" % String(snapshot.get("faction", "未知")))
	_set_field("residence", "居所：%s" % String(snapshot.get("residence", "未知")))
	_set_field("health", "生命：%d / %d" % [
		int(snapshot.get("health", 0)), int(snapshot.get("max_health", 0)),
	])
	_set_field("experience", "经验：%d" % int(snapshot.get("experience", 0)))
	_description_label.text = String(snapshot.get("description", ""))
	_replace_equipment_layers(snapshot.get("worn_items", []))
	_replace_buffs(snapshot.get("buffs", []))


## 同步背包 revision，使人物卸装命令可进行乐观锁校验。
## [param inventory_revision] 当前权威背包 revision。
func set_inventory_revision(inventory_revision: int) -> void:
	_inventory_revision = inventory_revision


## 创建人物背景、裸体底模与服装叠层容器。
## 设计：裸体底模坐标来自 humanequipwnd 的局部锚点再叠加窗口偏移；服装坐标来自 WearInDlg 的窗口坐标。
func _build_portrait() -> void:
	var portrait_background := TextureRect.new()
	portrait_background.texture = PORTRAIT_BACKGROUND
	portrait_background.position = Vector2(13, 48)
	portrait_background.size = PORTRAIT_BACKGROUND.get_size()
	portrait_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_background.stretch_mode = TextureRect.STRETCH_KEEP
	portrait_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(portrait_background)
	_portrait_body = TextureRect.new()
	_portrait_body.name = "Body"
	_portrait_body.texture = BODY_MALE
	_portrait_body.position = Vector2(56, 64)
	_portrait_body.size = BODY_MALE.get_size()
	_portrait_body.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_body.stretch_mode = TextureRect.STRETCH_KEEP
	_portrait_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_portrait_body)
	_equipment_layers = Control.new()
	_equipment_layers.name = "EquipmentLayers"
	_equipment_layers.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_equipment_layers.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(_equipment_layers)


## 创建右侧每个独立定位的资料字段和查看技能按钮。
func _build_identity_fields() -> void:
	var field_ids := ["display_name", "level", "profession", "faction", "residence", "health", "experience"]
	for index in field_ids.size():
		_field_labels[field_ids[index]] = _create_label(
			Vector2(195, 60 + index * 18), Vector2(140, 18), TEXT_FONT_SIZE
		)
	_skill_button = Button.new()
	_skill_button.name = "ShowSkillsButton"
	_skill_button.text = "查看技能"
	_skill_button.position = Vector2(195, 280)
	_skill_button.size = Vector2(56, 18)
	_skill_button.flat = true
	_skill_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_skill_button.add_theme_font_override("font", LEGACY_PANEL_FONT)
	_skill_button.add_theme_font_size_override("font_size", TEXT_FONT_SIZE)
	_skill_button.add_theme_color_override("font_color", TEXT_COLOR)
	_skill_button.add_theme_color_override("font_hover_color", Color("ffd6df"))
	_skill_button.pressed.connect(func() -> void: skill_panel_requested.emit())
	content_root.add_child(_skill_button)


## 按权威穿着快照重建服装叠层。
## [param worn_items_value] 穿着装备数组。
func _replace_equipment_layers(worn_items_value: Variant) -> void:
	for child in _equipment_layers.get_children():
		child.queue_free()
	if not worn_items_value is Array:
		return
	var worn_items: Array = (worn_items_value as Array).duplicate(true)
	worn_items.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("z_layer", 0)) < int(right.get("z_layer", 0))
	)
	for raw_item: Variant in worn_items:
		if raw_item is Dictionary:
			_add_equipment_layer(raw_item)


## 将一件服装的对话框图按 ALE origin 叠加并绑定悬浮属性。
## [param equipment] 带表现锚点、属性和持久化实例信息的穿着快照。
func _add_equipment_layer(equipment: Dictionary) -> void:
	var layer := EquipmentLayer.new()
	if not layer.configure(equipment, Vector2(91, 274)):
		layer.free()
		return
	layer.name = "Clothing_%s" % String(equipment.get("definition_id", "unknown"))
	layer.gui_input.connect(_on_worn_gui_input.bind(String(equipment.get("slot_id", "upper_body"))))
	_equipment_layers.add_child(layer)


## 处理服装叠层双击并提交卸装命令。
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


## 替换人物增益图标。
## [param buffs_value] 权威增益数组。
func _replace_buffs(buffs_value: Variant) -> void:
	for child in _buff_root.get_children():
		child.queue_free()
	if not buffs_value is Array:
		return
	var buffs: Array = (buffs_value as Array).duplicate(true)
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




## 设置一个已创建资料字段的文本。
## [param field_id] 字段标识。
## [param text] 待显示文本。
func _set_field(field_id: String, text: String) -> void:
	var label := _field_labels.get(field_id) as Label
	if label != null:
		label.text = text


## 创建统一的旧客户端资料文字标签。
## [param label_position] 标签左上角。
## [param label_size] 标签尺寸。
## [param font_size] 像素字号。
## 返回已加入面板内容根节点的 Label。
func _create_label(label_position: Vector2, label_size: Vector2, font_size: int) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_override("font", LEGACY_PANEL_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	content_root.add_child(label)
	return label
