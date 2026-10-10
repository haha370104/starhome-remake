class_name PersonalWarehousePanel
extends NavigationWindow

signal command_requested(command: Dictionary)

var item_canvas: InventoryCanvas
var context_menu: InventoryContextMenu
var confirmation: ConfirmationDialog
var _count_label: Label
var _cabinet_buttons: Array[Button] = []
var _snapshot: PersonalWarehouseSnapshot
var _player: CurrentPlayer
var _cabinet := 1
var _waiting := false
var _pending: Dictionary = {}


func _ready() -> void:
	item_canvas = InventoryPanel.build_storage_window(self, _request_arrange)
	item_canvas.move_requested.connect(_request_move)
	_count_label = InventoryPanel.make_storage_label(self, Vector2(36, 405), Vector2(180, 18))
	for index in range(6):
		var button := make_button(str(index + 1), Rect2(181 + index * 22, 405, 20, 24), _select_cabinet.bind(index + 1))
		button.add_theme_font_size_override("font_size", 11)
		button.toggle_mode = true
		_cabinet_buttons.append(button)
	context_menu = InventoryContextMenu.new()
	context_menu.command_requested.connect(_submit)
	context_menu.right_click.connect(handle_context_menu_right_click)
	add_child(context_menu)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "开通储物柜"
	confirmation.ok_button_text = "开通"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(_confirm_expansion)
	confirmation.canceled.connect(func() -> void: _pending.clear())
	add_child(confirmation)
	visibility_changed.connect(_on_visibility_changed)


func apply_snapshot(raw: Dictionary, player: CurrentPlayer) -> void:
	var parsed := PersonalWarehouseSnapshot.from_payload(raw, player, _snapshot)
	_waiting = false
	if not parsed.is_ok:
		_snapshot = null
		item_canvas.apply_inventory(null)
		notice_requested.emit(parsed.error_message)
		return
	_snapshot = parsed.value
	_player = player
	_cabinet = _snapshot.cabinet
	item_canvas.apply_inventory(_snapshot.inventory)
	_count_label.text = "物品：%d / %d" % [_snapshot.inventory.items().size(), _snapshot.inventory.capacity]
	_update_cabinet_buttons()


func _update_cabinet_buttons() -> void:
	if _snapshot == null:
		return
	for index in range(_cabinet_buttons.size()):
		var cabinet := index + 1
		var button := _cabinet_buttons[index]
		button.disabled = not _snapshot.available or cabinet > mini(_snapshot.cabinet_count + 1, _snapshot.maximum_cabinets)
		button.set_pressed_no_signal(cabinet == _cabinet)


func open_board() -> void:
	_waiting = true
	command_requested.emit({"type": "query_personal_warehouse", "cabinet": _cabinet})


func _select_cabinet(cabinet: int) -> void:
	_update_cabinet_buttons()
	if _snapshot == null or _waiting:
		return
	if cabinet <= _snapshot.cabinet_count:
		_cabinet = cabinet
		open_board()
		return
	_ask_expansion(cabinet)


func _ask_expansion(cabinet: int) -> void:
	if _snapshot == null or not _snapshot.available:
		return
	_pending = {"type": "expand_personal_warehouse", "confirm_expansion": true, "cabinet": cabinet,
		"inventory_revision": _player.inventory.revision, "warehouse_revision": _snapshot.revision}
	confirmation.dialog_text = "开通第%d柜需要%d紫晶，是否开通？" % [cabinet, _snapshot.expansion_cost]
	confirmation.popup_centered(Vector2i(360, 130))


func _confirm_expansion() -> void:
	if _pending.is_empty():
		return
	var command := _pending.duplicate(true)
	_pending.clear()
	_submit(command)


func _request_arrange() -> void:
	_submit({"type": "arrange_warehouse"})


func _request_move(instance_id: String, position: Vector2i) -> void:
	_submit({"type": "move_warehouse_item", "instance_id": instance_id, "position_px": [position.x, position.y]})


func transfer_item(instance_id: String, deposit: bool, position: Vector2i) -> void:
	_submit({"type": "deposit_warehouse_item" if deposit else "withdraw_warehouse_item", "instance_id": instance_id, "position_px": [position.x, position.y]})


func _submit(command: Dictionary) -> void:
	if _snapshot == null or _player == null or _waiting or not _snapshot.available:
		return
	command.merge({"cabinet": _cabinet,
		"inventory_revision": _player.inventory.revision, "warehouse_revision": _snapshot.revision})
	_waiting = true
	command_requested.emit(command)


func handle_context_click(point: Vector2) -> bool:
	var item := item_canvas.item_at(point)
	if item == null or _snapshot == null or _waiting or not _snapshot.available:
		return false
	context_menu.open_for(item, _player.inventory.revision, point, true, {
		"cabinet": _cabinet, "warehouse_revision": _snapshot.revision})
	return true


func handle_rejection(code: StringName, _message: String) -> void:
	var was_waiting := _waiting
	_waiting = false
	if visible and was_waiting and code in [&"warehouse.revision", &"warehouse.location"]:
		open_board()


func _on_visibility_changed() -> void:
	if not visible:
		_pending.clear()
		confirmation.hide()
		context_menu.dismiss()
