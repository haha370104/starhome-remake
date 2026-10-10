class_name MailPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var summary: Label
var listing: Tree
var sender_label: Label
var subject_label: Label
var body_view: RichTextLabel
var target_input: LineEdit
var subject_input: LineEdit
var body_input: TextEdit
var send_button: Button
var mark_read_button: Button
var delete_button: Button
var _mailbox: Array = []
var _selected_mail_id := ""
var _section := "mail"


func _ready() -> void:
	build_modern_window(Vector2(560, 600), "信件")
	summary = make_label("收件箱 0", Rect2(20, 48, 520, 22))
	listing = Tree.new()
	listing.position = Vector2(20, 76)
	listing.size = Vector2(520, 150)
	listing.columns = 4
	listing.hide_root = true
	listing.column_titles_visible = true
	for column in range(4):
		listing.set_column_title(column, ["时间", "发件人", "主题", "状态"][column])
		listing.set_column_custom_minimum_width(column, [130, 110, 205, 55][column])
	listing.item_selected.connect(func() -> void: _select_message())
	content_root.add_child(listing)
	sender_label = make_label("发件人：—", Rect2(20, 234, 520, 22))
	subject_label = make_label("主题：—", Rect2(20, 258, 520, 22))
	body_view = RichTextLabel.new()
	body_view.position = Vector2(20, 282)
	body_view.size = Vector2(520, 76)
	body_view.bbcode_enabled = false
	body_view.scroll_active = true
	body_view.fit_content = false
	body_view.add_theme_stylebox_override("normal", _surface_style("0b1620", "304b5e"))
	content_root.add_child(body_view)
	mark_read_button = make_button("标为已读", Rect2(20, 368, 100, 28), _mark_read)
	delete_button = make_button("删除信件", Rect2(130, 368, 100, 28), _delete_selected)
	make_label("写信（收件人填写昵称或角色实体 ID）", Rect2(20, 405, 520, 22))
	target_input = LineEdit.new()
	target_input.position = Vector2(20, 432)
	target_input.size = Vector2(230, 28)
	target_input.placeholder_text = "收件人昵称或实体 ID"
	content_root.add_child(target_input)
	subject_input = LineEdit.new()
	subject_input.position = Vector2(260, 432)
	subject_input.size = Vector2(280, 28)
	subject_input.max_length = 60
	subject_input.placeholder_text = "主题（最多 60 字）"
	content_root.add_child(subject_input)
	body_input = TextEdit.new()
	body_input.position = Vector2(20, 468)
	body_input.size = Vector2(400, 70)
	body_input.placeholder_text = "正文（最多 1000 字）"
	body_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content_root.add_child(body_input)
	send_button = make_button("发送", Rect2(430, 468, 110, 70), _send_mail)
	target_input.text_changed.connect(func(_value: String) -> void: _render_buttons())
	subject_input.text_changed.connect(func(_value: String) -> void: _render_buttons())
	body_input.text_changed.connect(func() -> void: _render_buttons())
	make_button("关闭", Rect2(240, 558, 80, 26), request_close)
	_render()


func open_board(section: String = "mail") -> void:
	_section = section
	_selected_mail_id = ""
	send_button.text = "发送留言" if _section == "leaveword" else "发送信件"
	_render()
	command_requested.emit({"type": "query_mailbox", "section": _section})


func apply_event(message: Dictionary) -> void:
	var message_type := String(message.get("type", ""))
	var result: Dictionary = message.get("result", {})
	if not bool(result.get("ok", false)):
		return
	var value: Variant = result.get("value", {})
	if not value is Dictionary:
		return
	if message_type == "mail_received":
		var received: Variant = value.get("mail")
		if received is Dictionary and String(received.get("section", "mail")) == _section:
			summary.text = "收到新留言" if _section == "leaveword" else "收到新信件"
			command_requested.emit({"type": "query_mailbox", "section": _section})
		return
	if message_type not in ["mail_state", "social_result"]:
		return
	if value.has("section") and not String(value.section).is_empty() and String(value.section) != _section:
		return
	var mailbox_value: Variant = value.get("mailbox")
	if mailbox_value is Array:
		_mailbox = mailbox_value.duplicate(true)
		_render()


func handle_rejection(code: StringName, message: String) -> void:
	if String(code).begins_with("mail.") and is_node_ready():
		summary.text = message if not message.is_empty() else String(code)


func _select_message() -> void:
	var selected := listing.get_selected()
	_selected_mail_id = String(selected.get_metadata(0)) if selected != null else ""
	_render_detail()
	_render_buttons()


func _render() -> void:
	if not is_node_ready():
		return
	var unread := 0
	for raw_message: Variant in _mailbox:
		if raw_message is Dictionary and not bool(raw_message.get("read", false)):
			unread += 1
	summary.text = "%s %d 封，未读 %d" % ["留言箱" if _section == "leaveword" else "收件箱", _mailbox.size(), unread]
	listing.clear()
	var root := listing.create_item()
	for raw_message: Variant in _mailbox:
		if not raw_message is Dictionary:
			continue
		var message: Dictionary = raw_message
		var row := listing.create_item(root)
		row.set_text(0, _time_text(int(message.get("sent_at_msec", 0))))
		row.set_text(1, String(message.get("sender_name", message.get("sender_entity_id", "玩家"))))
		row.set_text(2, String(message.get("subject", "")))
		row.set_text(3, "已读" if bool(message.get("read", false)) else "未读")
		row.set_metadata(0, String(message.get("mail_id", "")))
	_render_detail()
	_render_buttons()


func _render_detail() -> void:
	var message := _selected_message()
	sender_label.text = "发件人：%s" % String(message.get("sender_name", "—")) if not message.is_empty() else "发件人：—"
	subject_label.text = "主题：%s" % String(message.get("subject", "—")) if not message.is_empty() else "主题：—"
	body_view.text = String(message.get("body", "")) if not message.is_empty() else ""


func _render_buttons() -> void:
	if not is_node_ready():
		return
	var message := _selected_message()
	mark_read_button.disabled = message.is_empty() or bool(message.get("read", false))
	delete_button.disabled = message.is_empty()
	send_button.disabled = target_input.text.strip_edges().is_empty() \
		or subject_input.text.strip_edges().is_empty() or body_input.text.strip_edges().is_empty()


func _selected_message() -> Dictionary:
	for raw_message: Variant in _mailbox:
		if raw_message is Dictionary and String(raw_message.get("mail_id", "")) == _selected_mail_id:
			return raw_message
	return {}


func _mark_read() -> void:
	if not _selected_mail_id.is_empty():
		command_requested.emit({"type": "mark_mail_read", "mail_id": _selected_mail_id})


func _delete_selected() -> void:
	if not _selected_mail_id.is_empty():
		command_requested.emit({"type": "delete_mail", "mail_id": _selected_mail_id})


func _send_mail() -> void:
	var target_id := target_input.text.strip_edges()
	var subject := subject_input.text.strip_edges()
	var body := body_input.text.strip_edges()
	if target_id.is_empty() or subject.is_empty() or body.is_empty():
		return
	command_requested.emit({"type": "send_mail", "target_entity_id": target_id, "subject": subject, "body": body, "section": _section})
	body_input.clear()
	subject_input.clear()


func _time_text(sent_at_msec: int) -> String:
	return Time.get_datetime_string_from_unix_time(int(sent_at_msec / 1000))
