class_name AuthoritativeMailService
extends RefCounted

const DomainResultScript := preload("res://scripts/core/domain_result.gd")

const MAX_MAIL_COUNT := 100
const MAX_SUBJECT_LENGTH := 60
const MAX_BODY_LENGTH := 1000
const MIN_SEND_INTERVAL_MSEC := 1000
const SECTIONS := ["mail", "leaveword"]
const COMMANDS := ["query_mailbox", "send_mail", "mark_mail_read", "delete_mail"]

var _player_for_entity: Callable
var _mailbox_for_entity: Callable
var _display_name_for_entity: Callable
var _is_active_for_entity: Callable
var _commit_mailbox: Callable
var _send_to_entity: Callable
var _find_entities_by_display_name: Callable
var _last_sent_msec: Dictionary = {}
var _configured := false


func configure(
	player_for_entity: Callable,
	mailbox_for_entity: Callable,
	display_name_for_entity: Callable,
	is_active_for_entity: Callable,
	commit_mailbox: Callable,
	send_to_entity: Callable,
	find_entities_by_display_name: Callable = Callable(),
) -> DomainResult:
	for port: Callable in [
		player_for_entity,
		mailbox_for_entity,
		display_name_for_entity,
		is_active_for_entity,
		commit_mailbox,
		send_to_entity,
	]:
		if not port.is_valid():
			return DomainResultScript.failure(&"mail.invalid_port", "all mail service ports are required")
	_player_for_entity = player_for_entity
	_mailbox_for_entity = mailbox_for_entity
	_display_name_for_entity = display_name_for_entity
	_is_active_for_entity = is_active_for_entity
	_commit_mailbox = commit_mailbox
	_send_to_entity = send_to_entity
	_find_entities_by_display_name = find_entities_by_display_name
	_configured = true
	return DomainResultScript.ok(self)


static func handles(command_type: String) -> bool:
	return command_type in COMMANDS


func remove_expired_entity(entity_id: String) -> void:
	_last_sent_msec.erase(entity_id)


func execute(actor_id: String, command: Dictionary) -> DomainResult:
	if not _configured:
		return _failure(&"mail.unavailable", "mail service is not configured")
	if actor_id.is_empty() or _player_for_entity.call(actor_id) == null \
		or not _is_active_for_entity.call(actor_id):
		return _failure(&"mail.actor_missing", "actor has no active authoritative player")
	var command_type := String(command.get("type", ""))
	match command_type:
		"query_mailbox":
			if command.size() == 1:
				return DomainResultScript.ok(snapshot_for(actor_id))
			if not _exact_keys(command, ["type", "section"]) or typeof(command.section) != TYPE_STRING:
				return _invalid_payload()
			if String(command.section) not in SECTIONS:
				return _failure(&"mail.invalid_section", "mail section is not available")
			return DomainResultScript.ok(snapshot_for(actor_id, String(command.section)))
		"send_mail":
			if not (_exact_keys(command, ["type", "target_entity_id", "subject", "body"]) \
					or _exact_keys(command, ["type", "target_entity_id", "subject", "body", "section"])):
				return _invalid_payload()
			for field: String in ["target_entity_id", "subject", "body"]:
				if typeof(command[field]) != TYPE_STRING:
					return _invalid_payload()
			var section := String(command.get("section", "mail"))
			if typeof(command.get("section", "mail")) != TYPE_STRING or section not in SECTIONS:
				return _invalid_payload()
			return _send(actor_id, String(command.target_entity_id), String(command.subject), String(command.body), section)
		"mark_mail_read":
			if not _exact_keys(command, ["type", "mail_id"]) or typeof(command.mail_id) != TYPE_STRING: return _invalid_payload()
			return _mark_read(actor_id, String(command.mail_id))
		"delete_mail":
			if not _exact_keys(command, ["type", "mail_id"]) or typeof(command.mail_id) != TYPE_STRING: return _invalid_payload()
			return _delete(actor_id, String(command.mail_id))
		_:
			return _failure(&"mail.unsupported_command", "unsupported mail command")


func snapshot_for(entity_id: String, section := "") -> Dictionary:
	var player: Player = _player_for_entity.call(entity_id)
	var mailbox: Array = player.mailbox.duplicate(true) if player != null else []
	if not section.is_empty():
		var filtered: Array = []
		for message: Dictionary in mailbox:
			if String(message.get("section", "mail")) == section:
				filtered.append(message)
		mailbox = filtered
	return {"mailbox": mailbox, "section": section}


func _send(actor_id: String, target_id: String, subject: String, body: String, section: String) -> DomainResult:
	if section not in SECTIONS:
		return _failure(&"mail.invalid_section", "mail section is not available")
	target_id = target_id.strip_edges()
	if target_id.is_empty() or target_id == actor_id:
		return _failure(&"mail.invalid_target", "mail target is invalid")
	var target_mailbox_result: DomainResult = _mailbox_for_entity.call(target_id)
	if not target_mailbox_result.is_ok and _find_entities_by_display_name.is_valid():
		var candidates: Variant = _find_entities_by_display_name.call(target_id)
		if candidates is Array and candidates.size() == 1:
			target_id = String(candidates[0])
			target_mailbox_result = _mailbox_for_entity.call(target_id)
		elif candidates is Array and candidates.size() > 1:
			return _failure(&"mail.ambiguous_target", "more than one player has this display name")
	if target_id == actor_id:
		return _failure(&"mail.invalid_target", "mail target is invalid")
	if not target_mailbox_result.is_ok:
		return _failure(&"mail.target_unavailable", "mail target is unavailable")
	var target_mailbox: Array = target_mailbox_result.value
	subject = subject.strip_edges()
	body = body.strip_edges()
	if subject.is_empty() or subject.length() > MAX_SUBJECT_LENGTH or "\n" in subject or "\r" in subject:
		return _failure(&"mail.invalid_subject", "mail subject must be 1..60 characters on one line")
	if body.is_empty() or body.length() > MAX_BODY_LENGTH:
		return _failure(&"mail.invalid_body", "mail body must be 1..1000 characters")
	if target_mailbox.size() >= MAX_MAIL_COUNT:
		return _failure(&"mail.mailbox_full", "mail target mailbox is full")
	var now := Time.get_ticks_msec()
	var last := int(_last_sent_msec.get(actor_id, -MIN_SEND_INTERVAL_MSEC))
	if now - last < MIN_SEND_INTERVAL_MSEC:
		return _failure(&"mail.rate_limited", "letters are being sent too quickly")
	var message := {
		"mail_id": "mail." + Crypto.new().generate_random_bytes(16).hex_encode(),
		"sender_entity_id": actor_id,
		"sender_name": String(_display_name_for_entity.call(actor_id)),
		"recipient_entity_id": target_id,
		"section": section,
		"subject": subject,
		"body": body,
		"sent_at_msec": int(Time.get_unix_time_from_system() * 1000),
		"read": false,
	}
	var mailbox: Array = target_mailbox.duplicate(true)
	mailbox.append(message)
	var committed: DomainResult = _commit_mailbox.call(target_id, mailbox)
	if not committed.is_ok: return committed
	_last_sent_msec[actor_id] = now
	_send_to_entity.call(target_id, {"type": "mail_received", "result": _wire_success({"mail": message, "section": section})})
	return DomainResultScript.ok({"mail_id": message.mail_id, "section": section})


func _mark_read(actor_id: String, mail_id: String) -> DomainResult:
	var player: Player = _player_for_entity.call(actor_id)
	var index := _message_index(player, mail_id)
	if index < 0:
		return _failure(&"mail.not_found", "mail message is unavailable")
	var mailbox: Array = player.mailbox.duplicate(true)
	var section := String(mailbox[index].get("section", "mail"))
	if not bool(mailbox[index].get("read", false)):
		mailbox[index]["read"] = true
		var committed: DomainResult = _commit_mailbox.call(actor_id, mailbox)
		if not committed.is_ok: return committed
	var snapshot := snapshot_for(actor_id, section)
	_send_to_entity.call(actor_id, {"type": "mail_state", "result": _wire_success(snapshot)})
	return DomainResultScript.ok(snapshot)


func _delete(actor_id: String, mail_id: String) -> DomainResult:
	var player: Player = _player_for_entity.call(actor_id)
	var index := _message_index(player, mail_id)
	if index < 0:
		return _failure(&"mail.not_found", "mail message is unavailable")
	var mailbox: Array = player.mailbox.duplicate(true)
	var section := String(mailbox[index].get("section", "mail"))
	mailbox.remove_at(index)
	var committed: DomainResult = _commit_mailbox.call(actor_id, mailbox)
	if not committed.is_ok: return committed
	var snapshot := snapshot_for(actor_id, section)
	_send_to_entity.call(actor_id, {"type": "mail_state", "result": _wire_success(snapshot)})
	return DomainResultScript.ok(snapshot)


func _message_index(player: Player, mail_id: String) -> int:
	if player == null or mail_id.is_empty(): return -1
	for index: int in range(player.mailbox.size()):
		if String(player.mailbox[index].get("mail_id", "")) == mail_id:
			return index
	return -1


func _exact_keys(command: Dictionary, keys: Array) -> bool:
	if command.size() != keys.size(): return false
	for key: String in keys:
		if not command.has(key): return false
	return true


func _wire_success(value: Dictionary) -> Dictionary:
	return {"ok": true, "code": "ok", "value": value}


func _invalid_payload() -> DomainResult:
	return _failure(&"mail.invalid_payload", "mail command contains an invalid field set")


func _failure(code: StringName, message: String) -> DomainResult:
	return DomainResultScript.failure(code, message)
