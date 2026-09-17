class_name InventoryPanel
extends DraggableGameWindow

signal enhancement_requested(instance_id: String, is_stone: bool)
signal vehicle_workshop_requested(instance_id: String, is_material: bool)
signal equipment_processing_requested(instance_id: String, is_material: bool)
signal equipment_maintenance_requested(instance_id: String, is_material: bool)
signal extra_attributes_requested(instance_id: String, is_material: bool)
signal equipment_strengthening_requested(instance_id: String, is_material: bool)
signal armor_refinement_requested(instance_id: String, is_material: bool)
signal clothing_improvement_requested(instance_id: String, is_material: bool)

signal command_requested(command: Dictionary)

const BACKGROUND := preload("res://assets/ui/windows/inventory/background.png")
const ARRANGE_NORMAL := preload("res://assets/ui/windows/inventory/arrange/normal.png")
const ARRANGE_HOVER := preload("res://assets/ui/windows/inventory/arrange/hover.png")
const ARRANGE_PRESSED := preload("res://assets/ui/windows/inventory/arrange/pressed.png")
const CanvasScript := preload("res://scripts/client/ui/components/inventory_canvas.gd")
const GRID_COLUMNS := InventoryLayout.GRID_COLUMNS
const GRID_ROWS := InventoryLayout.GRID_ROWS
const GRID_CAPACITY := GRID_COLUMNS * GRID_ROWS
const GRID_SIZE := Vector2(276, 295)
const CELL_SIZE := Vector2(GRID_SIZE.x / GRID_COLUMNS, GRID_SIZE.y / GRID_ROWS)
const CELL_PADDING := 5.0

var _item_canvas: Control
var _count_label: Label
var _currency_label: Label
var _revision := -1
var context_menu: InventoryContextMenu
var _food_label: Label


## 创建荣耀版像素背包固定布局和整理按钮。
func _ready() -> void:
	configure(Vector2(338, 469), BACKGROUND, Vector2(302, 40))
	_item_canvas = CanvasScript.new()
	_item_canvas.name = "ItemCanvas"
	_item_canvas.position = Vector2(28, 70)
	_item_canvas.size = GRID_SIZE
	_item_canvas.clip_contents = true
	_item_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	_item_canvas.move_requested.connect(_request_move)
	_item_canvas.equip_requested.connect(_request_equip)
	_item_canvas.character_equip_requested.connect(_request_character_equip)
	content_root.add_child(_item_canvas)
	_count_label = _label(Vector2(28, 407), Vector2(180, 18))
	_currency_label = _label(Vector2(28, 423), Vector2(180, 18))
	_food_label = _label(Vector2(182, 407), Vector2(134, 36))
	context_menu = InventoryContextMenu.new()
	context_menu.command_requested.connect(command_requested.emit)
	context_menu.enhancement_requested.connect(enhancement_requested.emit)
	context_menu.vehicle_workshop_requested.connect(vehicle_workshop_requested.emit)
	context_menu.equipment_processing_requested.connect(equipment_processing_requested.emit)
	context_menu.equipment_maintenance_requested.connect(equipment_maintenance_requested.emit)
	context_menu.extra_attributes_requested.connect(extra_attributes_requested.emit)
	context_menu.equipment_strengthening_requested.connect(equipment_strengthening_requested.emit)
	context_menu.armor_refinement_requested.connect(armor_refinement_requested.emit)
	context_menu.clothing_improvement_requested.connect(clothing_improvement_requested.emit)
	add_child(context_menu)
	visibility_changed.connect(func() -> void:
		if not visible:
			context_menu.dismiss())

	var arrange_button := TextureButton.new()
	arrange_button.name = "ArrangeButton"
	arrange_button.texture_normal = ARRANGE_NORMAL
	arrange_button.texture_hover = ARRANGE_HOVER
	arrange_button.texture_pressed = ARRANGE_PRESSED
	arrange_button.position = Vector2(252, 370)
	arrange_button.size = Vector2(65, 32)
	arrange_button.ignore_texture_size = true
	arrange_button.tooltip_text = "整理背包"
	arrange_button.pressed.connect(_request_arrange)
	content_root.add_child(arrange_button)


## 从当前玩家聚合的背包对象重建物品视图。
## [param inventory] 已由权威快照还原的领域背包，内部保留具体 GameItem 实例。
## 设计：背包和地面表现消费同一种物品类型；本面板不再渲染第二套物品字典。
func apply_inventory(inventory: Inventory) -> void:
	if inventory == null:
		return
	_revision = inventory.revision
	var items := inventory.items()
	_count_label.text = "物品：%d / %d" % [
		items.size(), inventory.capacity,
	]
	_currency_label.text = "金币：%d" % inventory.currency
	_item_canvas.apply_inventory(inventory)


## 在物品区域优先打开上下文菜单，空白处保留右键关闭习惯。
## [param point] 视口鼠标位置。
## 返回物品菜单是否已消费点击。
func handle_context_click(point: Vector2) -> bool:
	var item: GameItem = _item_canvas.item_at(point)
	if item == null:
		return false
	context_menu.open_for(item, _revision, point)
	return true


## 显示同事务体力和当前食品效果，具体数值放在悬停说明中。
## [param status] 只读食品状态投影。
func apply_food_status(status: FoodStatus) -> void:
	context_menu.food_status = status
	var descriptions := PackedStringArray()
	var now := int(Time.get_unix_time_from_system())
	for effect: FoodEffect in status.active:
		if effect.expires_at > now:
			descriptions.append("%s，剩余%d秒" % [effect.description(), effect.expires_at - now])
	_food_label.text = "体力：%d/100\n食品效果：%d" % [status.physical, descriptions.size()]
	_food_label.tooltip_text = "\n".join(descriptions)
	_food_label.mouse_filter = Control.MOUSE_FILTER_STOP


## 提交背包整理意图及当前 revision。
func _request_arrange() -> void:
	if _revision < 0:
		return
	command_requested.emit({
		"type": "arrange_inventory",
		"inventory_revision": _revision,
	})


## 提交自由坐标移动意图，不自动吸附，也不检查其他物品是否重叠。
## [param instance_id] 稳定物品实例标识。
## [param requested_position] 物品左上角的容器局部坐标；容器外落点取消拖动。
func _request_move(instance_id: String, requested_position: Vector2i) -> void:
	if _revision < 0 or not Rect2(Vector2.ZERO, GRID_SIZE).has_point(Vector2(requested_position)):
		return
	command_requested.emit({
		"type": "move_inventory_item",
		"instance_id": instance_id,
		"position_px": [requested_position.x, requested_position.y],
		"inventory_revision": _revision,
	})


## 将双击可装备物品转换为战车安装命令。
## [param instance_id] 稳定物品实例标识。
## [param location] 目录指定的战车 Location。
func _request_equip(instance_id: String, location: int) -> void:
	command_requested.emit({
		"type": "equip_vehicle_item",
		"instance_id": instance_id,
		"location": location,
		"inventory_revision": _revision,
		"requires_loadout_revision": true,
	})


## 将双击服装转换为人物换装命令。
## [param instance_id] 稳定服装实例标识。
## [param slot_id] 人物业务槽位名。
func _request_character_equip(instance_id: String, slot_id: String) -> void:
	command_requested.emit({
		"type": "equip_character_item",
		"instance_id": instance_id,
		"character_slot": slot_id,
		"inventory_revision": _revision,
		"requires_state_revision": true,
	})


## 创建背包底部统计标签。
## [param label_position] 标签位置。
## [param label_size] 标签尺寸。
## 返回已加入内容根节点的 Label。
func _label(label_position: Vector2, label_size: Vector2) -> Label:
	var label := Label.new()
	label.position = label_position
	label.size = label_size
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	content_root.add_child(label)
	return label
