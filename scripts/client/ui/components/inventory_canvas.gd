class_name InventoryCanvas
extends Control

signal move_requested(instance_id: String, requested_position: Vector2i)
signal equip_requested(instance_id: String, location: int)
signal character_equip_requested(instance_id: String, slot_id: String)

const ItemView := preload("res://scripts/client/ui/windows/inventory/inventory_item_view.gd")
const GRID_SIZE := Vector2(276, 295)
const CELL_SIZE := Vector2(GRID_SIZE.x / InventoryLayout.GRID_COLUMNS, GRID_SIZE.y / InventoryLayout.GRID_ROWS)


## 初始化可嵌入窗口、商店或其他容器的像素背包区域。
func _init() -> void:
	size = GRID_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS


## 替换当前物品视图；只读取物品，不改变位置或补齐命令版本。
## [param inventory] 当前权威投影中的背包，空值清空显示。
func apply_inventory(inventory: Inventory) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if inventory == null:
		return
	var items := inventory.items()
	for item_index: int in mini(items.size(), InventoryLayout.GRID_COLUMNS * InventoryLayout.GRID_ROWS):
		var domain_item: GameItem = items[item_index]
		var item := ItemView.new()
		item.name = "Item_%s" % domain_item.instance_id.validate_node_name()
		item.configure(domain_item, CELL_SIZE, 5.0)
		item.position = Vector2(domain_item.position_px)
		item.move_requested.connect(move_requested.emit)
		item.equip_requested.connect(equip_requested.emit)
		item.character_equip_requested.connect(character_equip_requested.emit)
		add_child(item)
