class_name TradePanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var status_label: Label
var partner_label: Label
var inventory_listing: Tree
var offer_listing: Tree
var quantity_input: SpinBox
var currency_input: SpinBox
var accept_button: Button
var decline_button: Button
var add_button: Button
var remove_button: Button
var currency_button: Button
var ready_button: Button
var cancel_button: Button

var _player: Player
var _trade: Dictionary = {}
var _invite: Dictionary = {}
var _selected_inventory_id := ""
var _selected_offer_id := ""


func _ready() -> void:
	build_modern_window(Vector2(640, 470), "玩家交易")
	status_label = make_label("等待交易邀请", Rect2(20, 48, 600, 22))
	partner_label = make_label("", Rect2(20, 70, 600, 22))
	var inventory_title := make_label("我的可交易物品", Rect2(20, 95, 280, 22))
	inventory_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var offer_title := make_label("当前报价", Rect2(340, 95, 280, 22))
	offer_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inventory_listing = _make_listing(Rect2(20, 120, 280, 220), ["物品", "数量", "状态"])
	offer_listing = _make_listing(Rect2(340, 120, 280, 220), ["所有者", "物品", "数量"])
	quantity_input = SpinBox.new()
	quantity_input.position = Vector2(20, 350)
	quantity_input.size = Vector2(110, 28)
	quantity_input.min_value = 1
	quantity_input.max_value = 1
	quantity_input.step = 1
	quantity_input.tooltip_text = "加入所选物品的数量"
	content_root.add_child(quantity_input)
	add_button = make_button("加入物品", Rect2(140, 350, 100, 28), _add_item)
	remove_button = make_button("移除物品", Rect2(250, 350, 100, 28), _remove_item)
	currency_input = SpinBox.new()
	currency_input.position = Vector2(365, 350)
	currency_input.size = Vector2(110, 28)
	currency_input.min_value = 0
	currency_input.max_value = 0
	currency_input.step = 1
	currency_input.tooltip_text = "本次交易支付的星际币"
	content_root.add_child(currency_input)
	currency_button = make_button("设置货币", Rect2(485, 350, 100, 28), _set_currency)
	accept_button = make_button("接受邀请", Rect2(20, 398, 100, 28), _accept_invite)
	decline_button = make_button("拒绝邀请", Rect2(130, 398, 100, 28), _decline_invite)
	ready_button = make_button("锁定报价", Rect2(340, 398, 100, 28), _ready_trade)
	cancel_button = make_button("取消交易", Rect2(450, 398, 100, 28), _cancel_trade)
	make_button("关闭", Rect2(280, 438, 80, 24), request_close)
	inventory_listing.item_selected.connect(_select_inventory)
	offer_listing.item_selected.connect(_select_offer)
	_render()


func apply_player(player: Player) -> void:
	_player = player
	if is_node_ready():
		currency_input.max_value = player.inventory.currency if player != null else 0
		_render()


func handle_rejection(code: StringName, message: String) -> void:
	if not String(code).begins_with("trade."):
		return
	status_label.text = message if not message.is_empty() else String(code)
	_render()


func apply_event(message: Dictionary) -> void:
	var message_type := String(message.get("type", ""))
	var result: Dictionary = message.get("result", {})
	if not bool(result.get("ok", false)):
		return
	var value: Dictionary = result.get("value", {})
	match message_type:
		"trade_invite":
			_invite = (value.get("invite", {}) as Dictionary).duplicate(true)
			status_label.text = "收到交易邀请"
		"trade_state", "social_result":
			var pending_invites: Array = value.get("pending_invites", []) if value.get("pending_invites") is Array else []
			if value.get("trade") is Dictionary:
				var trade_value: Dictionary = value.trade
				_trade = trade_value.duplicate(true)
				if String(_trade.get("trade_id", "")).is_empty():
					_trade.clear()
					_selected_offer_id = ""
				else:
					_invite.clear()
					status_label.text = "请检查双方报价后锁定"
			if _trade.is_empty():
				_invite = (pending_invites[0] as Dictionary).duplicate(true) if not pending_invites.is_empty() else {}
				status_label.text = "收到交易邀请" if not _invite.is_empty() else ""
		"trade_completed":
			_trade.clear()
			_invite.clear()
			status_label.text = "交易完成"
		"trade_cancelled":
			_trade.clear()
			_invite.clear()
			status_label.text = "交易已取消"
		"trade_invite_cancelled":
			_invite.clear()
			status_label.text = "交易邀请已失效"
		"trade_invite_declined":
			status_label.text = "对方拒绝了交易邀请"
	_render()


func _make_listing(rect: Rect2, titles: Array[String]) -> Tree:
	var listing := Tree.new()
	listing.position = rect.position
	listing.size = rect.size
	listing.columns = titles.size()
	listing.hide_root = true
	listing.column_titles_visible = true
	for column in titles.size():
		listing.set_column_title(column, titles[column])
		listing.set_column_custom_minimum_width(column, [125, 55, 95][column] if titles.size() == 3 else 90)
	content_root.add_child(listing)
	return listing


func _select_inventory() -> void:
	var item := inventory_listing.get_selected()
	_selected_inventory_id = String(item.get_metadata(0)) if item != null else ""
	var selected := _player.inventory.find(_selected_inventory_id) if _player != null else null
	quantity_input.max_value = selected.quantity if selected != null else 1
	quantity_input.value = mini(int(quantity_input.value), int(quantity_input.max_value))


func _select_offer() -> void:
	var item := offer_listing.get_selected()
	var metadata: Variant = item.get_metadata(0) if item != null else null
	_selected_offer_id = String(metadata) if metadata is String else ""
	remove_button.disabled = _trade.is_empty() or _own_offer_locked() or _selected_offer_id.is_empty()


func _add_item() -> void:
	if _trade.is_empty() or _selected_inventory_id.is_empty():
		return
	command_requested.emit({
		"type": "trade_add_item",
		"trade_id": String(_trade.get("trade_id", "")),
		"instance_id": _selected_inventory_id,
		"quantity": int(quantity_input.value),
	})


func _remove_item() -> void:
	if _trade.is_empty() or _selected_offer_id.is_empty():
		return
	command_requested.emit({
		"type": "trade_remove_item",
		"trade_id": String(_trade.get("trade_id", "")),
		"instance_id": _selected_offer_id,
	})


func _set_currency() -> void:
	if _trade.is_empty():
		return
	command_requested.emit({
		"type": "trade_set_currency",
		"trade_id": String(_trade.get("trade_id", "")),
		"currency": int(currency_input.value),
	})


func _ready_trade() -> void:
	if not _trade.is_empty():
		command_requested.emit({"type": "trade_ready", "trade_id": String(_trade.get("trade_id", ""))})


func _cancel_trade() -> void:
	if not _trade.is_empty():
		command_requested.emit({"type": "trade_cancel", "trade_id": String(_trade.get("trade_id", ""))})


func _accept_invite() -> void:
	if _invite.is_empty():
		return
	command_requested.emit({
		"type": "trade_respond",
		"invite_id": String(_invite.get("invite_id", "")),
		"accept": true,
	})
	_invite.clear()
	_render()


func _decline_invite() -> void:
	if _invite.is_empty():
		return
	command_requested.emit({
		"type": "trade_respond",
		"invite_id": String(_invite.get("invite_id", "")),
		"accept": false,
	})
	_invite.clear()
	_render()


func _render() -> void:
	if not is_node_ready():
		return
	var trade_id := String(_trade.get("trade_id", ""))
	var members: Array = _trade.get("members", [])
	partner_label.text = "交易对象：%s" % _partner_name(members) if not trade_id.is_empty() else ""
	accept_button.disabled = _invite.is_empty()
	decline_button.disabled = _invite.is_empty()
	var active := not _trade.is_empty()
	var own_offer: Dictionary = _trade.get("offers", {}).get(_player.entity_id, {}) if _player != null else {}
	if active:
		currency_input.value = int(own_offer.get("currency", 0))
	add_button.disabled = not active or _own_offer_locked()
	remove_button.disabled = not active or _own_offer_locked() or _selected_offer_id.is_empty()
	currency_button.disabled = not active or _own_offer_locked()
	ready_button.disabled = not active or _own_offer_locked()
	cancel_button.disabled = not active
	_render_inventory()
	_render_offers()


func _render_inventory() -> void:
	inventory_listing.clear()
	var root := inventory_listing.create_item()
	if _player == null:
		return
	for item: GameItem in _player.inventory.items():
		var row := inventory_listing.create_item(root)
		row.set_text(0, item.display_name)
		row.set_text(1, str(item.quantity))
		row.set_text(2, "不可交易" if item.locked or item.bound else "可交易")
		row.set_metadata(0, item.instance_id)


func _render_offers() -> void:
	offer_listing.clear()
	var root := offer_listing.create_item()
	var offers: Dictionary = _trade.get("offers", {})
	var members: Array = _trade.get("members", [])
	var local_entity_id := _player.entity_id if _player != null else ""
	for member_id: String in members:
		var offer: Dictionary = offers.get(member_id, {})
		for item: Dictionary in offer.get("items", []):
			var row := offer_listing.create_item(root)
			row.set_text(0, String(offer.get("display_name", member_id)))
			row.set_text(1, String(item.get("display_name", item.get("definition_id", "物品"))))
			row.set_text(2, str(item.get("quantity", 0)))
			row.set_metadata(0, String(item.get("instance_id", "")) if member_id == local_entity_id else "")
		if int(offer.get("currency", 0)) > 0:
			var currency_row := offer_listing.create_item(root)
			currency_row.set_text(0, String(offer.get("display_name", member_id)))
			currency_row.set_text(1, "星际币")
			currency_row.set_text(2, str(offer.get("currency", 0)))


func _own_offer_locked() -> bool:
	if _player == null:
		return false
	var offers: Dictionary = _trade.get("offers", {})
	return bool(offers.get(_player.entity_id, {}).get("locked", false))


func _partner_name(members: Array) -> String:
	if _player == null:
		return ""
	var offers: Dictionary = _trade.get("offers", {})
	for member_id: String in members:
		if member_id != _player.entity_id:
			return String(offers.get(member_id, {}).get("display_name", member_id))
	return ""
