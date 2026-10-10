class_name PrivateChatHistory
extends RefCounted

const MAX_MESSAGES := 500
const PAGE_SIZE := 50

class HistoryWriter extends BackgroundFileWriter:
	var _failures: Dictionary = {}
	var _failure_mutex := Mutex.new()

	func _write_job(job: Dictionary) -> DomainResult:
		var result := super._write_job(job)
		_failure_mutex.lock()
		if result.is_ok: _failures.erase(job.path)
		else: _failures[job.path] = result
		_failure_mutex.unlock()
		if not result.is_ok: push_error("Private chat save failed: " + result.error_message)
		return result

	func failures() -> Dictionary:
		_failure_mutex.lock()
		var result := _failures.duplicate()
		_failure_mutex.unlock()
		return result

var _directory := ""
var _conversations: Dictionary = {}
var _errors: Dictionary = {}
var _writer: HistoryWriter


func configure(directory := "") -> DomainResult:
	var closed := close()
	if not closed.is_ok: return closed
	_directory = ProjectSettings.globalize_path(directory) if not directory.is_empty() else ""
	_conversations.clear()
	_errors.clear()
	if _directory.is_empty(): return DomainResult.ok()
	var keys := {}
	for file_name: String in DirAccess.get_files_at(_directory) if DirAccess.dir_exists_absolute(_directory) else PackedStringArray():
		if file_name.ends_with(".json") or file_name.ends_with(".json.bak"):
			keys[file_name.trim_suffix(".bak").trim_suffix(".json")] = true
	for key: String in keys:
		var loaded := _load(key)
		if not loaded.is_ok: push_error(loaded.error_message + ": " + _path(key))
	_writer = HistoryWriter.new()
	if _writer.start() != OK:
		_writer = null
		return DomainResult.failure(&"chat.storage_error", "无法启动私聊记录后台保存")
	return DomainResult.ok()


func append(event: Dictionary) -> DomainResult:
	var members: Array = [event.sender_entity_id, event.target_entity_id]
	members.sort()
	var key := _key(members)
	if _errors.has(key): return _errors[key]
	var previous: Dictionary = _conversations.get(key, {
		"schema_version": 1, "members": members, "next_sequence": 1, "messages": [],
	})
	var sequence := int(previous.next_sequence)
	var row := {}
	for field: String in ["sender_entity_id", "target_entity_id", "sender_name", "target_name", "message", "sent_at_unix_msec"]:
		row[field] = event[field]
	row.merge({"sequence": sequence, "message_id": "%s.%d" % [key, sequence]})
	var rows: Array = previous.messages.slice(maxi(0, previous.messages.size() - MAX_MESSAGES + 1))
	rows.append(row)
	var document := {"schema_version": 1, "members": members, "next_sequence": sequence + 1, "messages": rows}
	if _writer != null:
		_retry_failed()
		if _writer.enqueue_snapshot(_path(key), document) != OK:
			return DomainResult.failure(&"chat.storage_error", "私聊记录无法加入保存队列")
	_conversations[key] = document
	return DomainResult.ok(row.duplicate(true))


func conversations_for(actor_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for document: Dictionary in _conversations.values():
		if actor_id not in document.members: continue
		var latest: Dictionary = document.messages.back()
		var outgoing: bool = latest.sender_entity_id == actor_id
		result.append({
			"target_entity_id": latest.target_entity_id if outgoing else latest.sender_entity_id,
			"player_name": latest.target_name if outgoing else latest.sender_name,
			"last_message": latest.message, "last_message_at": latest.sent_at_unix_msec,
		})
	result.sort_custom(func(first: Dictionary, second: Dictionary) -> bool: return first.last_message_at > second.last_message_at)
	return result


func page(actor_id: String, target_id: String, cursor: Variant = null) -> DomainResult:
	var key := _key([actor_id, target_id])
	if _errors.has(key): return _errors[key]
	var rows: Array = _conversations.get(key, {}).get("messages", [])
	var end := rows.size()
	if cursor != null:
		end = -1
		for index in rows.size():
			if rows[index].message_id == cursor:
				end = index
				break
		if end < 0: return DomainResult.failure(&"chat.cursor_expired", "历史游标已失效，请重新加载最近消息")
	var begin := maxi(0, end - PAGE_SIZE)
	return DomainResult.ok({"messages": rows.slice(begin, end).duplicate(true),
		"oldest_sequence": int(rows[0].sequence) if not rows.is_empty() else 0,
		"next_cursor": rows[begin].message_id if begin > 0 else null})


func flush() -> DomainResult:
	if _writer == null: return DomainResult.ok()
	_writer.flush()
	_retry_failed()
	_writer.flush()
	var failures := _writer.failures()
	return DomainResult.ok() if failures.is_empty() else failures.values()[0]


func close() -> DomainResult:
	var result := flush()
	if _writer != null:
		_writer.close()
		_writer = null
	return result


func _retry_failed() -> void:
	for path: String in _writer.failures():
		var key := path.get_file().trim_suffix(".json")
		if _conversations.has(key): _writer.enqueue_snapshot(path, _conversations[key])


func _load(key: String) -> DomainResult:
	var result: DomainResult
	for path: String in [_path(key), _path(key) + ".bak"]:
		if not FileAccess.file_exists(path): continue
		var parser := JSON.new()
		var document: Variant = parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null
		if _valid(document, key):
			_conversations[key] = document
			return DomainResult.ok()
	result = DomainResult.failure(&"chat.history_corrupt", "私聊记录损坏，未覆盖原文件")
	_errors[key] = result
	return result


func _valid(document: Variant, key: String) -> bool:
	if not document is Dictionary or document.get("schema_version") != 1 \
			or not document.get("members") is Array or document.members.size() != 2 \
			or not document.get("messages") is Array or document.messages.is_empty() \
			or document.messages.size() > MAX_MESSAGES or not _integer(document.get("next_sequence")):
		return false
	for member: Variant in document.members:
		if not member is String or member.is_empty() or member.length() > 128: return false
	if document.members[0] == document.members[1] or _key(document.members) != key: return false
	var sequence: int = int(document.next_sequence) - document.messages.size()
	for row: Variant in document.messages:
		if not row is Dictionary or not _integer(row.get("sequence")) or row.sequence != sequence \
				or row.get("message_id") != "%s.%d" % [key, sequence] \
				or not _integer(row.get("sent_at_unix_msec")): return false
		for field: String in ["sender_entity_id", "target_entity_id", "sender_name", "target_name", "message"]:
			if not row.get(field) is String or row[field].is_empty(): return false
		if row.sender_entity_id not in document.members or row.target_entity_id not in document.members \
				or row.sender_entity_id == row.target_entity_id or row.message.length() > 200 \
				or "\n" in row.message or "\r" in row.message: return false
		sequence += 1
	return true


func _integer(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and value > 0 and value <= 9007199254740991 and value == floorf(float(value))


func _key(members: Array) -> String:
	var ordered := members.duplicate()
	ordered.sort()
	return JSON.stringify(ordered).sha256_text()


func _path(key: String) -> String:
	return _directory.path_join(key + ".json")
