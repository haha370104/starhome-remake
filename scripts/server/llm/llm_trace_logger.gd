class_name LlmTraceLogger
extends RefCounted

const MAX_TRACE_BYTES := 32 * 1024 * 1024

static var _enabled := false
static var _trace_path := ""
static var _writer: BackgroundFileWriter
static var _stopped := false
static var _path_announced := false
static var _write_warning_emitted := false


static func enable(path_override := "") -> void:
	_stopped = false
	_enabled = true
	if not path_override.is_empty():
		_trace_path = path_override
	_ensure_trace_path()


static func is_enabled() -> bool:
	return _enabled and not _stopped


static func trace_path() -> String:
	if is_enabled():
		_ensure_trace_path()
	return _trace_path


static func record(actor_id: String, stage: StringName, fields: Dictionary = {}) -> void:
	if not is_enabled():
		return
	_ensure_trace_path()
	if _writer == null:
		return
	var entry := {
		"unix_time_ms": roundi(Time.get_unix_time_from_system() * 1000.0),
		"monotonic_time_ms": Time.get_ticks_msec(),
		"process_id": OS.get_process_id(),
		"actor_id": actor_id,
		"stage": String(stage),
		"fields": _json_safe(fields),
	}
	var accepted := _writer.enqueue_trace(
		ProjectSettings.globalize_path(_trace_path), entry, MAX_TRACE_BYTES
	)
	if accepted != OK or not _writer.last_result().is_ok:
		if not _write_warning_emitted:
			_write_warning_emitted = true
			push_warning("LLM 日志后台写入异常或队列已满：%s" % _trace_path)
	print("LLM_TRACE " + JSON.stringify(entry))


static func shutdown() -> DomainResult:
	_stopped = true
	var result: DomainResult = _writer.close() if _writer != null else DomainResult.ok()
	_writer = null
	return result


static func _ensure_trace_path() -> void:
	if _trace_path.is_empty():
		_trace_path = "user://logs/llm_player_trace.jsonl"
	if _writer != null:
		return
	_writer = BackgroundFileWriter.new()
	if _writer.start() != OK:
		_writer = null
		_enabled = false
		push_warning("无法启动 LLM 日志后台线程")
		return
	if not _path_announced:
		_path_announced = true
		print("LLM 玩家日志：%s" % ProjectSettings.globalize_path(_trace_path))


static func _json_safe(value: Variant) -> Variant:
	if value is Vector2:
		return [value.x, value.y]
	if value is StringName:
		return String(value)
	if value is Dictionary:
		var converted := {}
		for key: Variant in value:
			converted[String(key)] = _json_safe(value[key])
		return converted
	if value is Array:
		var converted: Array = []
		for item: Variant in value:
			converted.append(_json_safe(item))
		return converted
	if value == null or value is bool or value is int or value is float or value is String:
		return value
	return str(value)
