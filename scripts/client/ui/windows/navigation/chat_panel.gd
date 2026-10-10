class_name ChatPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

const MAX_HISTORY := 80

var transcript: RichTextLabel
var channel_picker: OptionButton
var target_label: Label
var message_input: LineEdit
var send_button: Button
var status_label: Label
var conversation_picker: OptionButton
var earlier_button: Button
var _actor_id := ""
var _target_entity_id := ""
var _target_name := ""
var _history: Array[String] = []
var _conversations: Dictionary = {}
var _private_messages: Dictionary = {}
var _cursor: Variant = null
var _request_id := 0
var _list_request_id := -1
var _page_request_id := -1
var _requested_cursor: Variant = null


func _ready() -> void:
	build_modern_window(Vector2(520, 430), "聊天")
	status_label = make_label("区域聊天", Rect2(20, 48, 480, 22))
	transcript = RichTextLabel.new()
	transcript.position = Vector2(20, 78)
	transcript.size = Vector2(480, 255)
	transcript.bbcode_enabled = false
	transcript.scroll_active = true
	transcript.fit_content = false
	transcript.add_theme_stylebox_override("normal", _surface_style("0b1620", "304b5e"))
	content_root.add_child(transcript)
	channel_picker = OptionButton.new()
	channel_picker.position = Vector2(20, 347)
	channel_picker.size = Vector2(112, 28)
	channel_picker.add_item("区域聊天")
	channel_picker.set_item_metadata(0, "area")
	channel_picker.add_item("队伍聊天")
	channel_picker.set_item_metadata(1, "party")
	channel_picker.add_item("私聊")
	channel_picker.set_item_metadata(2, "private")
	channel_picker.item_selected.connect(_channel_changed)
	content_root.add_child(channel_picker)
	channel_picker.select(0)
	target_label = make_label("未选择私聊对象", Rect2(145, 350, 220, 24))
	conversation_picker = OptionButton.new()
	conversation_picker.position = Vector2(145, 347)
	conversation_picker.size = Vector2(220, 28)
	conversation_picker.item_selected.connect(_select_conversation)
	content_root.add_child(conversation_picker)
	earlier_button = make_button("更早消息", Rect2(375, 347, 125, 28), func() -> void: _request_history(_target_entity_id, _cursor))
	message_input = LineEdit.new()
	message_input.position = Vector2(20, 382)
	message_input.size = Vector2(390, 28)
	message_input.max_length = 200
	message_input.placeholder_text = "输入消息（最多 200 字）"
	message_input.text_submitted.connect(func(_text: String) -> void: _send_message())
	content_root.add_child(message_input)
	send_button = make_button("发送", Rect2(420, 382, 80, 28), _send_message)
	make_button("关闭", Rect2(220, 414, 80, 24), request_close)
	_render_channel()


func open_area() -> void:
	channel_picker.select(0)
	_render_channel()


func open_private(target_entity_id: String, target_name: String, refresh_list := true) -> void:
	if target_entity_id != _target_entity_id: _private_messages.clear()
	_target_entity_id = target_entity_id
	_target_name = target_name
	_conversations[target_entity_id] = target_name
	_cursor = null
	channel_picker.select(2)
	_render_channel()
	_request_history(target_entity_id)
	if refresh_list: _request_history(null)


func apply_player(player: Player) -> void:
	if _actor_id == player.entity_id: return
	_actor_id = player.entity_id
	_history.clear()
	_conversations.clear()
	_private_messages.clear()
	_target_entity_id = ""
	_target_name = ""
	_cursor = null
	_page_request_id = -1
	_list_request_id = -1
	_render_channel()


func refresh_history() -> void:
	_request_history(null)
	if channel_picker.get_selected_metadata() == "private" and not _target_entity_id.is_empty():
		_request_history(_target_entity_id)


func apply_event(message: Dictionary) -> void:
	var result: Dictionary = message.get("result", {})
	if not bool(result.get("ok", false)):
		return
	var page: Variant = result.get("value", {}).get("private_chat_history")
	if page is Dictionary:
		_apply_history(page)
		return
	if String(message.get("type", "")) != "chat_event": return
	var event: Dictionary = result.get("value", {}).get("event", {})
	if event.is_empty():
		return
	if event.get("channel") == "private":
		var outgoing: bool = event.sender_entity_id == _actor_id
		var target_id := String(event.target_entity_id if outgoing else event.sender_entity_id)
		var target_name := String(event.get("target_name", "玩家") if outgoing else event.sender_name)
		_conversations[target_id] = target_name
		if _target_entity_id.is_empty() or channel_picker.get_selected_metadata() != "private":
			open_private(target_id, target_name)
		if target_id == _target_entity_id: _merge_messages([event])
		_render_channel()
		return
	var prefix := "区域" if String(event.get("channel", "")) == "area" else \
		"队伍"
	_history.append("[%s] %s：%s" % [prefix, String(event.get("sender_name", "玩家")), String(event.get("message", ""))])
	if _history.size() > MAX_HISTORY:
		_history.pop_front()
	_render_transcript()


func handle_rejection(code: StringName, message: String) -> void:
	if not String(code).begins_with("chat."):
		return
	status_label.text = message if not message.is_empty() else String(code)
	if code == &"chat.cursor_expired": _request_history(_target_entity_id)


func _channel_changed(_index: int) -> void:
	_render_channel()
	if channel_picker.get_selected_metadata() == "private":
		_request_history(null)
		if not _target_entity_id.is_empty(): _request_history(_target_entity_id)


func _select_conversation(index: int) -> void:
	open_private(String(conversation_picker.get_item_metadata(index)), conversation_picker.get_item_text(index), false)


func _request_history(target_id: Variant, cursor: Variant = null) -> void:
	_request_id += 1
	if target_id == null: _list_request_id = _request_id
	else:
		_page_request_id = _request_id
		_requested_cursor = cursor
	command_requested.emit({"type": "query_private_chat_history", "target_entity_id": target_id,
		"cursor": cursor, "request_id": _request_id})


func _apply_history(page: Dictionary) -> void:
	if page.get("target_entity_id") == null:
		if int(page.get("request_id", -1)) != _list_request_id: return
		for conversation: Dictionary in page.conversations:
			_conversations[conversation.target_entity_id] = conversation.player_name
		if _target_entity_id.is_empty() and not _conversations.is_empty() and channel_picker.get_selected_metadata() == "private":
			open_private(String(_conversations.keys()[0]), String(_conversations.values()[0]), false)
	else:
		if page.target_entity_id != _target_entity_id or int(page.get("request_id", -1)) != _page_request_id: return
		_target_name = String(page.player_name)
		_conversations[_target_entity_id] = _target_name
		_cursor = page.next_cursor
		_merge_messages(page.messages)
		for message_id: String in _private_messages.keys():
			if _private_messages[message_id].sequence < int(page.oldest_sequence): _private_messages.erase(message_id)
	_render_channel()
	if page.get("target_entity_id") != null and _requested_cursor != null: transcript.scroll_to_line(0)


func _merge_messages(messages: Array) -> void:
	for row: Dictionary in messages: _private_messages[String(row.message_id)] = row
	var ordered: Array = _private_messages.values()
	ordered.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.sequence < second.sequence)
	for row: Dictionary in ordered.slice(0, maxi(0, ordered.size() - 500)): _private_messages.erase(row.message_id)


func _render_transcript() -> void:
	var lines := _history.duplicate()
	if channel_picker.get_selected_metadata() == "private":
		lines.clear()
		var messages: Array = _private_messages.values()
		messages.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.sequence < second.sequence)
		for row: Dictionary in messages:
			var seconds := int(float(row.sent_at_unix_msec) / 1000) + int(Time.get_time_zone_from_system().bias) * 60
			lines.append("[%s] %s：%s" % [Time.get_datetime_string_from_unix_time(seconds).replace("T", " "), row.sender_name, row.message])
	transcript.text = "\n".join(lines)
	transcript.scroll_to_line(maxi(0, lines.size() - 1))


func _render_channel() -> void:
	var channel := String(channel_picker.get_selected_metadata()) if channel_picker != null else "area"
	var is_private := channel == "private"
	status_label.text = "私聊：%s" % _target_name if is_private and not _target_entity_id.is_empty() \
		else "请选择私聊对象" if is_private else "队伍聊天" if channel == "party" else "区域聊天"
	target_label.text = "对象：%s" % _target_name if is_private and not _target_name.is_empty() else "队伍频道" if channel == "party" else "未选择私聊对象"
	target_label.visible = not is_private
	conversation_picker.visible = is_private
	earlier_button.visible = is_private
	earlier_button.disabled = _cursor == null
	conversation_picker.clear()
	for target_id: String in _conversations:
		conversation_picker.add_item(String(_conversations[target_id]))
		var index := conversation_picker.item_count - 1
		conversation_picker.set_item_metadata(index, target_id)
		if target_id == _target_entity_id: conversation_picker.select(index)
	send_button.disabled = is_private and _target_entity_id.is_empty()
	_render_transcript()


func _send_message() -> void:
	var message := message_input.text.strip_edges()
	if message.is_empty():
		return
	var channel := String(channel_picker.get_selected_metadata())
	var command := {"type": "chat_send", "channel": channel, "message": message}
	if channel == "private":
		if _target_entity_id.is_empty():
			return
		command["target_entity_id"] = _target_entity_id
	command_requested.emit(command)
	message_input.clear()
