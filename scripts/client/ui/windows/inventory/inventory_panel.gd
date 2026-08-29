class_name InventoryPanel
extends DraggableGameWindow

signal command_requested(command: Dictionary)

const BACKGROUND := preload("res://assets/ui/windows/inventory/background.png")
const ARRANGE_NORMAL := preload("res://assets/ui/windows/inventory/arrange/normal.png")
const ARRANGE_HOVER := preload("res://assets/ui/windows/inventory/arrange/hover.png")
const ARRANGE_PRESSED := preload("res://assets/ui/windows/inventory/arrange/pressed.png")
const ItemViewScript := preload("res://scripts/client/ui/windows/inventory/inventory_item_view.gd")

var _item_canvas: Control
var _count_label: Label
var _currency_label: Label
var _revision := -1


## 创建荣耀版像素背包固定布局和整理按钮。
func _ready() -> void:
	configure(Vector2(338, 469), BACKGROUND, Vector2(302, 40))
	_item_canvas = Control.new()
	_item_canvas.name = "ItemCanvas"
	_item_canvas.position = Vector2(28, 70)
	_item_canvas.size = Vector2(276, 295)
	_item_canvas.clip_contents = true
	_item_canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	content_root.add_child(_item_canvas)
	_count_label = _label(Vector2(28, 407), Vector2(180, 18))
	_currency_label = _label(Vector2(28, 423), Vector2(180, 18))

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
	for child in _item_canvas.get_children():
		child.queue_free()
	for domain_item: GameItem in items:
		var item := ItemViewScript.new()
		item.name = "Item_%s" % domain_item.instance_id.validate_node_name()
		item.configure(domain_item)
		item.position = Vector2(domain_item.position_px)
		item.move_requested.connect(_request_move)
		item.equip_requested.connect(_request_equip)
		item.character_equip_requested.connect(_request_character_equip)
		_item_canvas.add_child(item)


## 提交背包整理意图及当前 revision。
func _request_arrange() -> void:
	if _revision < 0:
		return
	command_requested.emit({
		"type": "arrange_inventory",
		"inventory_revision": _revision,
	})


## 提交单个物品移动意图。
## [param instance_id] 稳定物品实例标识。
## [param requested_position] 容器局部像素坐标。
func _request_move(instance_id: String, requested_position: Vector2i) -> void:
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
