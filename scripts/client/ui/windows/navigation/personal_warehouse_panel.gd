class_name PersonalWarehousePanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var backpack_list: InventoryCanvas
var warehouse_list: InventoryCanvas
var deposit_quantity: SpinBox
var withdraw_quantity: SpinBox
var deposit_button: Button
var withdraw_button: Button
var expand_button: Button
var confirmation: ConfirmationDialog
var details: RichTextLabel
var _backpack_title: Label
var _warehouse_title: Label
var _status: Label
var _cabinet_buttons: Array[Button] = []
var _snapshot: PersonalWarehouseSnapshot = null
var _deposit_id := ""
var _withdraw_id := ""
var _cabinet := 1
var _waiting := false
var _pending: Dictionary = {}


## 组合共享窗口壳、原物品图、双侧清单与独立数量输入，不在客户端结算存取。
func _ready() -> void:
	build_modern_window(Vector2(860, 650), "个人仓库")
	make_label("仅在龙之城或基地大厅使用", Rect2(24, 60, 370, 28))
	for index in range(6):
		var button := make_button("柜%d" % (index + 1), Rect2(454 + index * 64, 58, 58, 32), _select_cabinet.bind(index + 1))
		_style_button(button)
		button.toggle_mode = true
		_cabinet_buttons.append(button)
	_backpack_title = make_label("背包", Rect2(24, 105, 330, 24))
	_warehouse_title = make_label("储物柜", Rect2(454, 105, 380, 24))
	backpack_list = _make_list(Rect2(70, 132, 276, 295), true)
	warehouse_list = _make_list(Rect2(504, 132, 276, 295), false)
	details = RichTextLabel.new()
	details.position = Vector2(24, 438)
	details.size = Vector2(812, 50)
	details.text = "拖动物品在两侧存取或自由摆放；也可选择数量后存取。"
	content_root.add_child(details)
	make_label("数量", Rect2(24, 510, 54, 28))
	deposit_quantity = _quantity(Vector2(78, 506))
	deposit_button = make_button("存入 →", Rect2(196, 506, 210, 36), _transfer.bind(true))
	make_label("数量", Rect2(454, 510, 54, 28))
	withdraw_quantity = _quantity(Vector2(508, 506))
	withdraw_button = make_button("← 取出", Rect2(626, 506, 210, 36), _transfer.bind(false))
	_status = make_label("正在读取仓库…", Rect2(24, 554, 810, 26))
	_status.clip_text = true
	_style_button(make_button("整理仓库", Rect2(126, 606, 120, 30), _submit_edit.bind({"type": "arrange_warehouse"})))
	_style_button(make_button("拆分选中物", Rect2(260, 606, 150, 30), _split_selected))
	_style_button(make_button("刷新", Rect2(24, 606, 92, 30), open_board))
	expand_button = make_button("开通新柜", Rect2(526, 606, 310, 30), _ask_expansion)
	for button: Button in [deposit_button, withdraw_button, expand_button]:
		_style_button(button)
		button.disabled = true
	confirmation = ConfirmationDialog.new()
	confirmation.title = "开通储物柜"
	confirmation.ok_button_text = "确认开通"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(_confirm_expansion)
	confirmation.canceled.connect(func() -> void: _pending.clear())
	add_child(confirmation)
	visibility_changed.connect(_dismiss_confirmation)


## 创建与背包共用的图标画布，坐标保持现有存档的左上角语义。
## [param rect] 画布区域。[param deposit] 是否为背包一侧。
## 返回接好语义信号的只读库存画布。
func _make_list(rect: Rect2, deposit: bool) -> InventoryCanvas:
	var frame := Panel.new()
	frame.position = rect.position - Vector2(4, 4)
	frame.size = rect.size + Vector2(8, 8)
	frame.add_theme_stylebox_override("panel", _surface_style("0b1620", "304b5e"))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(frame)
	var canvas := InventoryCanvas.new()
	canvas.position = rect.position
	canvas.item_selected.connect(_select_identity.bind(deposit))
	canvas.move_requested.connect(_move_item.bind(deposit))
	canvas.external_drop_requested.connect(_cross_drop.bind(deposit))
	content_root.add_child(canvas)
	return canvas


## 按画布实例身份恢复选中项，图片层不持有独立库存。
## [param id] 点击实例。[param deposit] 所属容器。
func _select_identity(id: String, deposit: bool) -> void:
	if _snapshot == null: return
	var rows := _snapshot.carried if deposit else _snapshot.stored
	for index in rows.size():
		if rows[index].id == id:
			_select_item(index, deposit)
			return


## 创建仅允许整件数量的输入框，选择后上限跟随权威堆叠。
## [param at] 窗口内位置。
## 返回数量控件。
func _quantity(at: Vector2) -> SpinBox:
	var quantity := SpinBox.new()
	quantity.position = at
	quantity.size = Vector2(106, 36)
	quantity.min_value = 1
	quantity.max_value = 1
	quantity.step = 1
	content_root.add_child(quantity)
	return quantity


## 查询当前柜，关闭时不轮询；刷新也可恢复失败后的交互状态。
func open_board() -> void:
	_waiting = true
	_update_actions()
	command_requested.emit({"type": "query_personal_warehouse", "cabinet": _cabinet})


## 应用同事务的具名展示快照，保留仍存在的选择而不替换确认中的意图。
## [param snapshot] 已完成协议转换的当前柜数据。
func apply_snapshot(snapshot: PersonalWarehouseSnapshot) -> void:
	_snapshot = snapshot
	_cabinet = snapshot.cabinet
	_waiting = false
	_backpack_title.text = "背包 · %d / %d" % [snapshot.carried.size(), snapshot.inventory_capacity]
	_warehouse_title.text = "第%d柜 · %d / %d" % [_cabinet, snapshot.stored.size(), snapshot.capacity]
	for index in range(_cabinet_buttons.size()):
		var button := _cabinet_buttons[index]
		button.disabled = index >= snapshot.cabinet_count
		button.set_pressed_no_signal(index + 1 == _cabinet)
		button.tooltip_text = "尚未开通，请使用下方开通按钮" if button.disabled else "查看第%d柜" % (index + 1)
	_fill(backpack_list, snapshot.carried, _deposit_id)
	_fill(warehouse_list, snapshot.stored, _withdraw_id)
	if _selected(true) == null: _deposit_id = ""
	if _selected(false) == null: _withdraw_id = ""
	_status.text = "紫晶：%d    %s" % [snapshot.amethyst, snapshot.message]
	expand_button.text = "已开通全部储物柜" if snapshot.cabinet_count >= snapshot.maximum_cabinets else "开通第%d柜 · %d紫晶" % [snapshot.cabinet_count + 1, snapshot.expansion_cost]
	_update_actions()
	if not snapshot.message.is_empty(): notice_requested.emit(snapshot.message)


## 响应普通背包变化，只在仓库可见且版本变化时请求新的同事务状态。
## [param revision] 已接收背包的权威版本。
func inventory_changed(revision: int) -> void:
	if visible and not _waiting and _snapshot != null and _snapshot.inventory_revision != revision:
		open_board()


## 填充物品图、数量和状态说明，恢复仍然存在的实例选择。
## [param listing] 目标列表。
## [param rows] 类型化显示行。
## [param _selected_id] 选中身份由面板统一保留。
func _fill(listing: InventoryCanvas, rows: Array[PersonalWarehouseSnapshot.ItemRow], _selected_id: String) -> void:
	var inventory := Inventory.new()
	var items: Array[GameItem] = []
	for row: PersonalWarehouseSnapshot.ItemRow in rows:
		items.append(row.item)
	inventory.restore_items(items)
	listing.apply_inventory(inventory)


## 切换已开通柜时清除旧柜选择，背包选择仍然保留。
## [param cabinet] 一起始的目标柜号。
func _select_cabinet(cabinet: int) -> void:
	if _snapshot == null or cabinet > _snapshot.cabinet_count: return
	_cabinet = cabinet
	_withdraw_id = ""
	open_board()


## 选择具体实例并显示说明，数量默认一件，不自动转移任何物品。
## [param index] 点击行号。
## [param deposit] 是否为背包侧。
func _select_item(index: int, deposit: bool) -> void:
	if _snapshot == null: return
	var rows := _snapshot.carried if deposit else _snapshot.stored
	if index < 0 or index >= rows.size(): return
	var row: PersonalWarehouseSnapshot.ItemRow = rows[index]
	if deposit: _deposit_id = row.id
	else: _withdraw_id = row.id
	var quantity := deposit_quantity if deposit else withdraw_quantity
	quantity.value = 1
	details.text = row.label() + "\n" + row.description
	_update_actions()


## 根据实例身份定位当前权威行，选择已消失时不跳到相邻物品。
## [param deposit] 是否查询背包侧。
## 返回选中行，或空值。
func _selected(deposit: bool) -> PersonalWarehouseSnapshot.ItemRow:
	if _snapshot == null: return null
	var id := _deposit_id if deposit else _withdraw_id
	for row: PersonalWarehouseSnapshot.ItemRow in (_snapshot.carried if deposit else _snapshot.stored):
		if row.id == id: return row
	return null


## 按权威可用性和选择控制操作，不预测容量、价格或背包最终数量。
func _update_actions() -> void:
	if deposit_button == null: return
	for deposit: bool in [true, false]:
		var row := _selected(deposit)
		var button := deposit_button if deposit else withdraw_button
		var quantity := deposit_quantity if deposit else withdraw_quantity
		button.disabled = _waiting or _snapshot == null or not _snapshot.available or row == null or row.locked
		quantity.max_value = row.quantity if row != null else 1
	expand_button.disabled = _waiting or _snapshot == null or not _snapshot.available or _snapshot.cabinet_count >= _snapshot.maximum_cabinets


## 提交本次选中的数量和双库存版本，服务端负责容量与原子存取。
## [param deposit] 存入或取出方向。
func _transfer(deposit: bool) -> void:
	var button := deposit_button if deposit else withdraw_button
	if button.disabled: return
	var row := _selected(deposit)
	var quantity := deposit_quantity if deposit else withdraw_quantity
	quantity.apply()
	var command := {"type": "deposit_warehouse_item" if deposit else "withdraw_warehouse_item",
		"instance_id": row.id, "quantity": int(quantity.value), "cabinet": _cabinet,
		"inventory_revision": _snapshot.inventory_revision, "warehouse_revision": _snapshot.revision}
	_waiting = true
	_update_actions()
	command_requested.emit(command)
	if _waiting: open_board()


## 固定扩容费用和版本后展示确认；自动刷新不能换成新的收费意图。
func _ask_expansion() -> void:
	if expand_button.disabled: return
	_pending = {"type": "expand_personal_warehouse", "confirm_expansion": true, "cabinet": _cabinet,
		"inventory_revision": _snapshot.inventory_revision, "warehouse_revision": _snapshot.revision}
	confirmation.dialog_text = "开通第%d个储物柜（%d格）\n消耗 %d 紫晶，当前持有 %d 紫晶。\n开通后永久保留。" % [_snapshot.cabinet_count + 1, _snapshot.capacity, _snapshot.expansion_cost, _snapshot.amethyst]
	confirmation.popup_centered(Vector2i(490, 210))


## 只提交一次用户确认的扩容意图，费用由服务端重新核对。
func _confirm_expansion() -> void:
	if _pending.is_empty(): return
	var command := _pending.duplicate(true)
	_pending.clear()
	_waiting = true
	_update_actions()
	command_requested.emit(command)
	if _waiting: open_board()


## 关闭窗口时撤销未发送的确认，不能在重新打开后沿用旧意图。
func _dismiss_confirmation() -> void:
	if not visible:
		_pending.clear()
		confirmation.hide()


## 在当前柜内拆分所选数量，服务端决定新身份与容量许可。
func _split_selected() -> void:
	var row := _selected(false)
	if row == null: return
	withdraw_quantity.apply()
	_submit_edit({"type": "split_warehouse_item", "instance_id": row.id, "quantity": int(withdraw_quantity.value)})


## 把画布内拖动路由到正确容器，保留各自版本与状态所有权。
## [param id] 被拖动的实例。[param point] 容器左上角坐标。[param deposit] 是否背包侧。
func _move_item(id: String, point: Vector2i, deposit: bool) -> void:
	_submit_edit({"type": "move_inventory_item" if deposit else "move_warehouse_item",
		"instance_id": id, "position_px": [point.x, point.y]})


## 跨画布拖动仅在目标画布内落下时发出存取，不将仓库物品直接丢弃。
## [param id] 来源实例。[param point] 视口落点。[param deposit] 存入方向。
func _cross_drop(id: String, point: Vector2, deposit: bool) -> void:
	var target := warehouse_list if deposit else backpack_list
	if not target.get_global_rect().has_point(point): return
	_transfer_at(id, deposit, Vector2i((target.get_global_transform_with_canvas().affine_inverse() * point).round()))


## 接收独立背包窗口拖来的物品，仍使用同一仓库事务。
## [param id] 背包实例。[param point] 视口落点。
func accept_external_item(id: String, point: Vector2) -> void:
	_cross_drop(id, point, true)


## 将整组放在指定位置，不自动合并或排列目标中的其他物品。
## [param id] 来源实例。[param deposit] 存入方向。[param point] 目标左上角。
func _transfer_at(id: String, deposit: bool, point: Vector2i) -> void:
	if _snapshot == null: return
	var rows := _snapshot.carried if deposit else _snapshot.stored
	for row: PersonalWarehouseSnapshot.ItemRow in rows:
		if row.id == id:
			_submit_edit({"type": "deposit_warehouse_item" if deposit else "withdraw_warehouse_item",
				"instance_id": id, "quantity": row.quantity, "position_px": [point.x, point.y]})
			return


## 为仓内编辑补齐快照版本，提交后沿用现有失败刷新流程。
## [param command] 不含库存版本的操作意图。
func _submit_edit(command: Dictionary) -> void:
	if _snapshot == null or _waiting or not _snapshot.available: return
	command = command.duplicate(true)
	command.merge({"cabinet": _cabinet, "warehouse_revision": _snapshot.revision,
		"inventory_revision": _snapshot.inventory_revision})
	_waiting = true
	_update_actions()
	command_requested.emit(command)
	if _waiting: open_board()
