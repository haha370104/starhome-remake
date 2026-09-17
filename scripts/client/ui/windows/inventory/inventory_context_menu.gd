class_name InventoryContextMenu
extends Node

signal enhancement_requested(instance_id: String, is_stone: bool)
signal vehicle_workshop_requested(instance_id: String, is_material: bool)

signal command_requested(command: Dictionary)

var menu := PopupMenu.new()
var split_dialog := ConfirmationDialog.new()
var replace_dialog := ConfirmationDialog.new()
var food_status: FoodStatus
var amount := SpinBox.new()
var _item: GameItem
var _revision := -1
var _actions: Array[String] = []


## 创建独立物品菜单和拆分数量框，交互只发命令不修改玩家投影。
func _ready() -> void:
	add_child(menu)
	menu.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_font.tres"))
	menu.add_theme_font_size_override("font_size", 16)
	menu.id_pressed.connect(_select_action)
	add_child(split_dialog)
	split_dialog.title = "拆分物品"
	split_dialog.ok_button_text = "拆分"
	split_dialog.cancel_button_text = "取消"
	amount.min_value = 1
	amount.position = Vector2(16, 16)
	amount.size = Vector2(220, 32)
	split_dialog.add_child(amount)
	split_dialog.confirmed.connect(_confirm_split)
	add_child(replace_dialog)
	replace_dialog.title = "替换食品效果"
	replace_dialog.ok_button_text = "使用并替换"
	replace_dialog.cancel_button_text = "取消"
	replace_dialog.confirmed.connect(_confirm_use)


## 按实际领域物品能力显示菜单，锁定项保留操作名但禁用。
## [param item] 被命中的自有物品。
## [param revision] 打开菜单时的背包版本。
## [param point] 视口鼠标坐标。
func open_for(item: GameItem, revision: int, point: Vector2) -> void:
	_item = item
	_revision = revision
	_actions.clear()
	menu.clear()
	menu.add_separator(item.display_name)
	if item is VehicleEquipment or item is Clothing:
		_add_action("装备", "equip", item.locked)
	if item is Clothing or item is EnhancementStone:
		_add_action("人物强化 / 合成", "clothing_enhancement", false)
	if item is VehicleEquipment or item is VehicleCrystal:
		_add_action("战车开槽 / 晶石", "vehicle_sockets", false)
	if item is ConsumableItem:
		_add_action("使用", "use_inventory_item", item.locked)
	if item.max_stack > 1:
		_add_action("拆分", "split_inventory_item", item.locked or item.quantity < 2)
		_add_action("合并", "merge_inventory_item", item.locked)
	if _actions.is_empty():
		menu.add_item("暂无可用操作")
		menu.set_item_disabled(menu.item_count - 1, true)
	menu.position = Vector2i(point)
	menu.reset_size()
	menu.popup()


## 加入带稳定动作映射的菜单项。
## [param label] 用户可见名称。
## [param action] 语义动作。
## [param disabled] 当前是否禁止点击。
func _add_action(label: String, action: String, disabled: bool) -> void:
	menu.add_item(label, _actions.size())
	_actions.append(action)
	menu.set_item_disabled(menu.item_count - 1, disabled)


## 将菜单选择转换为既有装备命令或新的背包操作命令。
## [param id] 菜单动作索引。
func _select_action(id: int) -> void:
	if id < 0 or id >= _actions.size() or _item == null:
		return
	var action := _actions[id]
	if action == "vehicle_sockets":
		vehicle_workshop_requested.emit(_item.instance_id, _item is VehicleCrystal)
		return
	if action == "clothing_enhancement":
		enhancement_requested.emit(_item.instance_id, _item is EnhancementStone)
		return
	if action == "use_inventory_item" and food_status != null:
		for effect: FoodEffect in (_item as ConsumableItem).effects:
			if food_status.bonus(effect.kind) > 0:
				replace_dialog.dialog_text = "使用%s将替换已有的同类食品效果。\n%s" % [_item.display_name, (_item as ConsumableItem).use_description()]
				replace_dialog.popup_centered(Vector2i(480, 190))
				return
	if action == "split_inventory_item":
		amount.max_value = _item.quantity - 1
		amount.value = maxi(1, floori(float(_item.quantity) / 2.0))
		split_dialog.popup_centered(Vector2i(260, 130))
		return
	var command := {"type": action, "instance_id": _item.instance_id, "inventory_revision": _revision}
	if action == "equip":
		if _item is VehicleEquipment:
			command.type = "equip_vehicle_item"
			command.location = (_item as VehicleEquipment).equipment_location
			command.requires_loadout_revision = true
		else:
			command.type = "equip_character_item"
			command.character_slot = (_item as Clothing).character_slot
			command.requires_state_revision = true
	command_requested.emit(command)


## 确认替换已有增益后提交使用，数量与冷却仍由服务器决定。
func _confirm_use() -> void:
	if _item != null:
		command_requested.emit({"type": "use_inventory_item", "instance_id": _item.instance_id,
			"inventory_revision": _revision})


## 使用打开菜单时的版本提交拆分数量，防止异步更新后对错误堆叠操作。
func _confirm_split() -> void:
	if _item == null:
		return
	command_requested.emit({"type": "split_inventory_item", "instance_id": _item.instance_id,
		"quantity": int(amount.value), "inventory_revision": _revision})


## 随背包关闭收起物品弹窗。
func dismiss() -> void:
	menu.hide()
	split_dialog.hide()
	replace_dialog.hide()
