class_name InventoryCanvas
extends Control

signal move_requested(instance_id: String, requested_position: Vector2i)
signal transfer_requested(instance_id: String, source: InventoryCanvas, requested_position: Vector2i)
signal equip_requested(instance_id: String, location: int)
signal character_equip_requested(instance_id: String, slot_id: String)

const ItemView := preload("res://scripts/client/ui/windows/inventory/inventory_item_view.gd")
var _views: Dictionary[String, InventoryItemView] = {}

const GRID_SIZE := Vector2(InventoryLayout.MAIN_SIZE)
const CELL_SIZE := Vector2(InventoryLayout.GRID_RECT.size) / Vector2(
	InventoryLayout.GRID_COLUMNS, InventoryLayout.GRID_ROWS
)


## 按绘制顺序查找鼠标命中的最上层物品，容器裁切外不接受点击。
## [param point] 视口坐标。
## 返回命中的领域物品；空白处返回空。
func item_at(point: Vector2) -> GameItem:
	if not is_visible_in_tree() or not get_global_rect().has_point(point):
		return null
	for index in range(get_child_count() - 1, -1, -1):
		var view := get_child(index) as InventoryItemView
		if view != null and view.get_global_rect().has_point(point):
			view.prepare_context_menu()
			return view.item
	return null


## 初始化可嵌入窗口、商店或其他容器的像素背包区域。
func _init() -> void:
	size = GRID_SIZE
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS


## 替换当前物品视图；只读取物品，不改变位置或补齐命令版本。
## [param inventory] 当前权威投影中的背包，空值清空显示。
func apply_inventory(inventory: Inventory) -> void:
	var previous: Dictionary = {}
	for child in get_children():
		var view := child as InventoryItemView
		previous[view.item.instance_id] = view
	var items: Array[GameItem] = []
	if inventory != null:
		items = inventory.items()
	for item_index: int in mini(items.size(), InventoryLayout.GRID_COLUMNS * InventoryLayout.GRID_ROWS):
		var domain_item: GameItem = items[item_index]
		var item := previous.get(domain_item.instance_id) as InventoryItemView
		previous.erase(domain_item.instance_id)
		if item != null and not item.update_stack(domain_item):
			remove_child(item)
			item.queue_free()
			item = null
		if item == null:
			item = _create_item_view(domain_item)
		else:
			item.item = domain_item
		_views[domain_item.instance_id] = item
		_place_item(item, domain_item.position_px)
		if item.get_index() != item_index:
			move_child(item, item_index)
	for view: InventoryItemView in previous.values():
		_views.erase(view.item.instance_id)
		remove_child(view)
		view.queue_free()


## 只更新本帧入账的物品，避免遍历并重新投影全部装备。
## [param inventory] 已提交的背包。[param item_ids] 新增或数量变化的实例。
func apply_changes(inventory: Inventory, item_ids: Array[String]) -> void:
	for identity: String in item_ids:
		var item := inventory.find(identity)
		var view: InventoryItemView = _views.get(identity)
		if view != null and (item == null or not view.update_stack(item)):
			remove_child(view)
			view.queue_free()
			_views.erase(identity)
			view = null
		if item == null: continue
		if view == null:
			view = _create_item_view(item)
			_place_item(view, item.position_px)
			_views[identity] = view
		_place_item(view, item.position_px)


## 创建单个视图并接入共同交互信号，全量和增量路径共用。
## [param domain_item] 当前物品。
## 返回已加入画布的视图。
func _create_item_view(domain_item: GameItem) -> InventoryItemView:
	var item := ItemView.new()
	item.name = "Item_%s" % domain_item.instance_id.validate_node_name()
	item.configure(domain_item, CELL_SIZE, 5.5)
	item.equip_requested.connect(equip_requested.emit)
	item.character_equip_requested.connect(character_equip_requested.emit)
	add_child(item)
	return item


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("source") is InventoryCanvas \
		and Rect2i(Vector2i.ZERO, Vector2i(size)).has_point(Vector2i((at + data.offset / get_global_transform().get_scale()).round()))


func _drop_data(at: Vector2, data: Variant) -> void:
	if not _can_drop_data(at, data): return
	var center := Vector2i((at + data.offset / get_global_transform().get_scale()).round())
	if data.source == self:
		move_requested.emit(data.instance_id, center)
	else:
		transfer_requested.emit(data.instance_id, data.source, center)


func _place_item(item: InventoryItemView, center: Vector2i) -> void:
	item.position = Vector2(center) - item.size * 0.5
