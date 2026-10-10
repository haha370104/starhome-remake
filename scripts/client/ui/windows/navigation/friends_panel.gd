class_name FriendsPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)
signal private_chat_requested(target_entity_id: String, display_name: String)

var summary: Label
var relation_picker: OptionButton
var listing: Tree
var pending_label: Label
var target_label: Label
var name_input: LineEdit
var name_invite_button: Button
var add_friend_button: Button
var add_enemy_button: Button
var remove_button: Button
var private_chat_button: Button
var accept_button: Button
var decline_button: Button
var _friends: Array = []
var _enemies: Array = []
var _pending_invite: Dictionary = {}
var _target_entity_id := ""
var _target_name := ""


func _ready() -> void:
	build_modern_window(Vector2(430, 510), "好友列表")
	summary = make_label("好友 0 / 仇人 0", Rect2(20, 48, 390, 24))
	relation_picker = OptionButton.new()
	relation_picker.position = Vector2(20, 78)
	relation_picker.size = Vector2(110, 28)
	relation_picker.add_item("好友")
	relation_picker.set_item_metadata(0, "friends")
	relation_picker.add_item("仇人")
	relation_picker.set_item_metadata(1, "enemies")
	relation_picker.item_selected.connect(func(_index: int) -> void: _render())
	content_root.add_child(relation_picker)
	listing = Tree.new()
	listing.position = Vector2(20, 115)
	listing.size = Vector2(390, 205)
	listing.columns = 3
	listing.hide_root = true
	listing.column_titles_visible = true
	for column in range(3):
		listing.set_column_title(column, ["玩家", "状态", "身份"][column])
		listing.set_column_custom_minimum_width(column, [190, 90, 90][column])
	listing.item_selected.connect(func() -> void: _render_buttons())
	content_root.add_child(listing)
	target_label = make_label("未从当前场景玩家列表选择对象", Rect2(20, 330, 390, 24))
	name_input = LineEdit.new()
	name_input.position = Vector2(20, 358)
	name_input.size = Vector2(190, 28)
	name_input.placeholder_text = "输入在线玩家昵称"
	name_input.text_changed.connect(func(_text: String) -> void: _render())
	name_input.text_submitted.connect(func(_text: String) -> void: _invite_by_name())
	content_root.add_child(name_input)
	name_invite_button = make_button("按昵称申请", Rect2(220, 358, 110, 28), _invite_by_name)
	add_friend_button = make_button("发送好友申请", Rect2(20, 393, 120, 28), _add_friend)
	add_enemy_button = make_button("标记仇人", Rect2(150, 393, 90, 28), _add_enemy)
	remove_button = make_button("移除关系", Rect2(250, 393, 90, 28), _remove_selected)
	private_chat_button = make_button("私聊", Rect2(345, 393, 65, 28), _private_chat_selected)
	pending_label = make_label("没有待处理好友申请", Rect2(20, 428, 390, 24))
	accept_button = make_button("接受", Rect2(20, 458, 70, 26), _accept_invite)
	decline_button = make_button("拒绝", Rect2(100, 458, 70, 26), _decline_invite)
	make_button("关闭", Rect2(340, 458, 70, 26), request_close)
	_render()


## 从场景玩家列表预选一个目标，实际关系仍由服务端命令确认。
func open_add_target(target_entity_id: String, display_name: String) -> void:
	_target_entity_id = target_entity_id
	_target_name = display_name
	if is_node_ready():
		_render()


## 消费好友状态、申请和拒绝事件，不在客户端直接修改关系。
func apply_event(message: Dictionary) -> void:
	var message_type := String(message.get("type", ""))
	var result: Dictionary = message.get("result", {})
	if not bool(result.get("ok", false)):
		return
	var value: Variant = result.get("value", {})
	if message_type == "friend_invite":
		_pending_invite = (value as Dictionary).get("invite", {}) if value is Dictionary else {}
	elif message_type == "friend_invite_cancelled":
		_pending_invite.clear()
		summary.text = "好友申请已失效"
	elif message_type == "friend_invite_declined":
		summary.text = "对方拒绝了好友申请"
	elif message_type == "friend_state" or message_type == "social_result":
		var snapshot: Variant = value
		if value is Dictionary and value.get("friends") is Dictionary:
			snapshot = value.get("friends")
		if snapshot is Dictionary and snapshot.has("friends"):
			_apply_snapshot(snapshot)
	_render()


func handle_rejection(code: StringName, message: String) -> void:
	if String(code).begins_with("friend."):
		summary.text = message if not message.is_empty() else String(code)


func _apply_snapshot(snapshot: Dictionary) -> void:
	_friends = (snapshot.get("friends", []) as Array).duplicate(true)
	_enemies = (snapshot.get("enemies", []) as Array).duplicate(true)
	var invites: Array = snapshot.get("pending_invites", []) as Array
	_pending_invite = (invites[0] as Dictionary).duplicate(true) if not invites.is_empty() else {}


func _render() -> void:
	if not is_node_ready():
		return
	summary.text = "好友 %d / 仇人 %d" % [_friends.size(), _enemies.size()] if _pending_invite.is_empty() else \
		"收到来自 %s 的好友申请" % String(_pending_invite.get("inviter_name", "玩家"))
	var is_enemy := String(relation_picker.get_selected_metadata()) == "enemies"
	var rows: Array = _enemies if is_enemy else _friends
	listing.clear()
	var root := listing.create_item()
	for row: Dictionary in rows:
		var item := listing.create_item(root)
		item.set_text(0, String(row.get("display_name", row.get("entity_id", ""))))
		item.set_text(1, "在线" if bool(row.get("online", false)) else "离线")
		item.set_text(2, "同区域" if bool(row.get("same_map", false)) else "—")
		item.set_metadata(0, String(row.get("entity_id", "")))
	target_label.text = "目标：%s" % _target_name if not _target_entity_id.is_empty() else "未从当前场景玩家列表选择对象"
	add_friend_button.disabled = _target_entity_id.is_empty()
	name_invite_button.disabled = name_input.text.strip_edges().is_empty()
	add_enemy_button.disabled = _target_entity_id.is_empty()
	_render_buttons()
	pending_label.text = "好友申请：%s" % String(_pending_invite.get("inviter_name", "玩家")) if not _pending_invite.is_empty() else "没有待处理好友申请"
	accept_button.disabled = _pending_invite.is_empty()
	decline_button.disabled = _pending_invite.is_empty()


func _render_buttons() -> void:
	for button: Button in [remove_button, private_chat_button]:
		if button != null:
			button.disabled = listing.get_selected() == null


func _add_friend() -> void:
	if not _target_entity_id.is_empty():
		command_requested.emit({"type": "friend_invite", "target_entity_id": _target_entity_id})


func _invite_by_name() -> void:
	var display_name := name_input.text.strip_edges()
	if display_name.is_empty():
		return
	command_requested.emit({"type": "friend_invite_by_name", "display_name": display_name})
	name_input.clear()
	_render()


func _add_enemy() -> void:
	if not _target_entity_id.is_empty():
		command_requested.emit({"type": "enemy_add", "target_entity_id": _target_entity_id})


func _remove_selected() -> void:
	var selected := listing.get_selected()
	if selected == null:
		return
	var target_id := String(selected.get_metadata(0))
	var command_type := "enemy_remove" if String(relation_picker.get_selected_metadata()) == "enemies" else "friend_remove"
	command_requested.emit({"type": command_type, "target_entity_id": target_id})


func _private_chat_selected() -> void:
	var selected := listing.get_selected()
	if selected == null:
		return
	private_chat_requested.emit(String(selected.get_metadata(0)), selected.get_text(0))


func _accept_invite() -> void:
	_respond_to_invite(true)


func _decline_invite() -> void:
	_respond_to_invite(false)


func _respond_to_invite(accept: bool) -> void:
	if _pending_invite.is_empty():
		return
	command_requested.emit({
		"type": "friend_respond",
		"invite_id": String(_pending_invite.get("invite_id", "")),
		"accept": accept,
	})
	_pending_invite.clear()
	_render()
