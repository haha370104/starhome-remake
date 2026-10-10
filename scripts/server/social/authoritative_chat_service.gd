class_name AuthoritativeChatService
extends RefCounted

const DomainResultScript := preload("res://scripts/core/domain_result.gd")
const MAX_MESSAGE_LENGTH := 200
const MIN_SEND_INTERVAL_MSEC := 250
const COMMANDS := ["chat_send", "query_private_chat_history"]

var _session_for_entity: Callable
var _map_for_entity: Callable
var _display_name_for_entity: Callable
var _entities_in_map: Callable
var _is_active_for_entity: Callable
var _send_to_entity: Callable
var _party_members_for_entity: Callable
var _last_sent_msec: Dictionary = {}
var _configured := false
var history := PrivateChatHistory.new()


## 配置聊天的会话、地图和可靠发布端口；聊天内容不落入玩家存档。
func configure(
	session_for_entity: Callable,
	map_for_entity: Callable,
	display_name_for_entity: Callable,
	entities_in_map: Callable,
	is_active_for_entity: Callable,
	send_to_entity: Callable,
	party_members_for_entity: Callable = Callable(),
	history_directory := "",
) -> DomainResult:
	for port: Callable in [
		session_for_entity,
		map_for_entity,
		display_name_for_entity,
		entities_in_map,
		is_active_for_entity,
		send_to_entity,
	]:
		if not port.is_valid():
			return DomainResultScript.failure(&"chat.invalid_port", "all chat service ports are required")
	_session_for_entity = session_for_entity
	_map_for_entity = map_for_entity
	_display_name_for_entity = display_name_for_entity
	_entities_in_map = entities_in_map
	_is_active_for_entity = is_active_for_entity
	_send_to_entity = send_to_entity
	_party_members_for_entity = party_members_for_entity
	var storage := history.configure(history_directory)
	_configured = storage.is_ok
	if not storage.is_ok: return storage
	return DomainResultScript.ok(self)


static func handles(command_type: String) -> bool:
	return command_type in COMMANDS


func remove_expired_entity(entity_id: String) -> void:
	_last_sent_msec.erase(entity_id)


## 接受区域聊天和私聊两种原版基础通道；身份、频道范围和发送频率均由服务端决定。
func execute(actor_id: String, command: Dictionary) -> DomainResult:
	if not _configured:
		return _failure(&"chat.unavailable", "chat service is not configured")
	if _session_for_entity.call(actor_id) == null or not _is_active_for_entity.call(actor_id):
		return _failure(&"chat.actor_missing", "actor has no active authoritative session")
	if command.get("type") == "query_private_chat_history":
		return _query_history(actor_id, command)
	if command.get("type") != "chat_send":
		return _failure(&"chat.unsupported_command", "unsupported chat command")
	var channel := String(command.get("channel", ""))
	var required_keys := ["type", "channel", "message"]
	if channel == "private":
		required_keys.append("target_entity_id")
	if not _exact_keys(command, required_keys):
		return _failure(&"chat.invalid_payload", "chat command contains an invalid field set")
	for field: String in ["channel", "message"]:
		if typeof(command[field]) != TYPE_STRING:
			return _failure(&"chat.invalid_payload", "chat command contains an invalid field type")
	if channel == "private" and typeof(command.target_entity_id) != TYPE_STRING:
		return _failure(&"chat.invalid_payload", "chat command contains an invalid field type")
	if channel not in ["area", "private", "party"]:
		return _failure(&"chat.invalid_channel", "chat channel is not available")
	var message := String(command.message).strip_edges()
	if message.is_empty() or message.length() > MAX_MESSAGE_LENGTH or "\n" in message or "\r" in message:
		return _failure(&"chat.invalid_message", "chat message must be 1..200 characters on one line")
	var now := Time.get_ticks_msec()
	var last := int(_last_sent_msec.get(actor_id, -MIN_SEND_INTERVAL_MSEC))
	if now - last < MIN_SEND_INTERVAL_MSEC:
		return _failure(&"chat.rate_limited", "chat messages are being sent too quickly")
	var recipients: Array[String] = []
	if channel == "area":
		var map_id := String(_map_for_entity.call(actor_id))
		for entity_id: String in _entities_in_map.call(map_id):
			if _is_active_for_entity.call(entity_id):
				recipients.append(entity_id)
	elif channel == "party":
		if not _party_members_for_entity.is_valid():
			return _failure(&"chat.party_unavailable", "party chat is unavailable")
		for entity_id: String in _party_members_for_entity.call(actor_id):
			if _is_active_for_entity.call(entity_id):
				recipients.append(entity_id)
		if recipients.is_empty():
			return _failure(&"chat.not_in_party", "actor does not belong to a party")
	else:
		var target_id := String(command.target_entity_id)
		if target_id.is_empty() or target_id == actor_id:
			return _failure(&"chat.invalid_target", "private chat target is invalid")
		if _session_for_entity.call(target_id) == null or not _is_active_for_entity.call(target_id):
			return _failure(&"chat.target_unavailable", "private chat target is offline")
		recipients = [actor_id, target_id]
	var event := {
		"channel": channel,
		"sender_entity_id": actor_id,
		"sender_name": String(_display_name_for_entity.call(actor_id)),
		"target_entity_id": String(command.get("target_entity_id", "")),
		"message": message,
		"sent_at_msec": now,
	}
	if channel == "private":
		event["target_name"] = String(_display_name_for_entity.call(event.target_entity_id))
		event["sent_at_unix_msec"] = roundi(Time.get_unix_time_from_system() * 1000)
		var recorded := history.append(event)
		if not recorded.is_ok: return recorded
		event.merge(recorded.value, true)
	_last_sent_msec[actor_id] = now
	for entity_id: String in recipients:
		_send_to_entity.call(entity_id, {"type": "chat_event", "result": _wire_success({"event": event})})
	return DomainResultScript.ok({"event": event})


func inspect_private_chat(actor_id: String, player_name: Variant, cursor: Variant) -> DomainResult:
	var listed := execute(actor_id, {"type": "query_private_chat_history", "target_entity_id": null, "cursor": null})
	if not listed.is_ok: return listed
	var conversations: Array = listed.value.private_chat_history.conversations
	if player_name == null:
		if cursor != null: return _failure(&"chat.invalid_payload", "请指定要翻页的私聊对象")
		for conversation: Dictionary in conversations: conversation.erase("target_entity_id")
		return DomainResultScript.ok({"conversations": conversations})
	var matches := conversations.filter(func(row: Dictionary) -> bool: return row.player_name == player_name)
	if matches.size() != 1:
		return _failure(&"chat.ambiguous_name" if matches.size() > 1 else &"chat.history_missing", "没有唯一匹配的私聊会话，请先查看会话列表")
	var queried := execute(actor_id, {"type": "query_private_chat_history", "target_entity_id": matches[0].target_entity_id, "cursor": cursor})
	if not queried.is_ok: return queried
	var page: Dictionary = queried.value.private_chat_history
	var messages: Array[Dictionary] = []
	for row: Dictionary in page.messages:
		messages.append({"sender_name": row.sender_name, "message": row.message, "sent_at_unix_msec": row.sent_at_unix_msec})
	return DomainResultScript.ok({"player_name": page.player_name, "messages": messages, "next_cursor": page.next_cursor})


func _query_history(actor_id: String, command: Dictionary) -> DomainResult:
	var keys := ["type", "target_entity_id", "cursor"]
	if command.has("request_id"): keys.append("request_id")
	if not _exact_keys(command, keys) or (command.target_entity_id != null and not command.target_entity_id is String) \
			or (command.cursor != null and (not command.cursor is String or command.cursor.length() > 128)) \
			or (command.has("request_id") and (not command.request_id is int or command.request_id < 0)):
		return _failure(&"chat.invalid_payload", "私聊历史查询参数无效")
	var conversations := history.conversations_for(actor_id)
	for conversation: Dictionary in conversations:
		var current_name := String(_display_name_for_entity.call(conversation.target_entity_id))
		if current_name != conversation.target_entity_id and not current_name.is_empty(): conversation.player_name = current_name
	var value := {"target_entity_id": command.target_entity_id, "request_id": command.get("request_id", -1)}
	if command.target_entity_id == null:
		if command.cursor != null: return _failure(&"chat.invalid_payload", "会话列表不接受消息游标")
		value["conversations"] = conversations
	else:
		if command.target_entity_id.is_empty() or command.target_entity_id == actor_id or command.target_entity_id.length() > 128:
			return _failure(&"chat.invalid_target", "私聊对象无效")
		var page := history.page(actor_id, command.target_entity_id, command.cursor)
		if not page.is_ok: return page
		value.merge(page.value)
		value["player_name"] = String(_display_name_for_entity.call(command.target_entity_id))
		for conversation: Dictionary in conversations:
			if conversation.target_entity_id == command.target_entity_id: value.player_name = conversation.player_name
	return DomainResultScript.ok({"private_chat_history": value})


func _exact_keys(command: Dictionary, keys: Array) -> bool:
	if command.size() != keys.size():
		return false
	for key: String in keys:
		if not command.has(key):
			return false
	return true


func _wire_success(value: Dictionary) -> Dictionary:
	return {"ok": true, "code": "ok", "value": value}


func _failure(code: StringName, message: String) -> DomainResult:
	return DomainResultScript.failure(code, message)
