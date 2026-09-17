class_name PersonalWarehousePanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var backpack_list: ItemList
var warehouse_list: ItemList
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
	build_modern_window(Vector2(860, 610), "个人仓库")
	make_label("仅在龙之城或基地大厅使用", Rect2(24, 60, 370, 28))
	for index in range(6):
		var button := make_button("柜%d" % (index + 1), Rect2(454 + index * 64, 58, 58, 32), _select_cabinet.bind(index + 1))
		_style_button(button)
		button.toggle_mode = true
		_cabinet_buttons.append(button)
	_backpack_title = make_label("背包", Rect2(24, 105, 330, 24))
	_warehouse_title = make_label("储物柜", Rect2(454, 105, 380, 24))
	backpack_list = _make_list(Rect2(24, 138, 382, 266), _select_item.bind(true))
	warehouse_list = _make_list(Rect2(454, 138, 382, 266), _select_item.bind(false))
	details = RichTextLabel.new()
	details.position = Vector2(24, 414)
	details.size = Vector2(812, 58)
	details.text = "选择物品后输入数量；锁定物品须先在背包解锁。"
	content_root.add_child(details)
	make_label("数量", Rect2(24, 484, 54, 28))
	deposit_quantity = _quantity(Vector2(78, 480))
	deposit_button = make_button("存入 →", Rect2(196, 480, 210, 36), _transfer.bind(true))
	make_label("数量", Rect2(454, 484, 54, 28))
	withdraw_quantity = _quantity(Vector2(508, 480))
	withdraw_button = make_button("← 取出", Rect2(626, 480, 210, 36), _transfer.bind(false))
	_status = make_label("正在读取仓库…", Rect2(24, 530, 810, 26))
	_status.clip_text = true
	_style_button(make_button("刷新", Rect2(24, 568, 92, 30), open_board))
	expand_button = make_button("开通新柜", Rect2(526, 568, 310, 30), _ask_expansion)
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


## 建立统一字号、原版物品图及溢出省略的可滚动清单。
## [param rect] 清单区域。
## [param callback] 当前一侧的选择动作。
## 返回已挂接的列表。
func _make_list(rect: Rect2, callback: Callable) -> ItemList:
	var listing := ItemList.new()
	listing.position = rect.position
	listing.size = rect.size
	listing.fixed_icon_size = Vector2i(32, 32)
	listing.add_theme_constant_override("v_separation", 8)
	listing.add_theme_stylebox_override("panel", _surface_style("0b1620", "304b5e"))
	listing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	listing.item_selected.connect(callback)
	content_root.add_child(listing)
	return listing


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
## [param selected_id] 上一次实例身份。
func _fill(listing: ItemList, rows: Array[PersonalWarehouseSnapshot.ItemRow], selected_id: String) -> void:
	listing.clear()
	for row: PersonalWarehouseSnapshot.ItemRow in rows:
		listing.add_item(row.label(), ItemPresentationTextureResolver.resolve(row.presentation).get("texture"))
		listing.set_item_tooltip(listing.item_count - 1, row.label() + "\n" + row.description)
		if row.locked: listing.set_item_custom_fg_color(listing.item_count - 1, Color("8998a6"))
		if row.id == selected_id: listing.select(listing.item_count - 1)


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
