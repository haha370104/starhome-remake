class_name LlmPlayerMemory
extends RefCounted

const MAX_MEMORIES := 256
const CONTEXT_CHARACTERS := 8000
const EPHEMERAL_EVENTS: Array[StringName] = [&"periodic_review", &"player_spawned", &"low_health", &"history_search_result"]
const STATE_QUERIES := ["inspect_self", "inspect_vehicle", "inspect_character", "inspect_inventory", "inspect_friends"]

class MemoryWriter extends BackgroundFileWriter:
	var failure: DomainResult = DomainResult.ok()
	var journal_offset := 0

	func _write_job(job: Dictionary) -> DomainResult:
		if job.kind == "snapshot": job.document["journal_offset"] = journal_offset
		if failure.is_ok: failure = super._write_job(job)
		if failure.is_ok and job.kind == "trace": journal_offset = _files[job.path].get_position()
		return failure

var working_memory: Dictionary = {}
var last_action: Dictionary = {}
var _memories: Dictionary = {}
var _sequence := 0
var _actor_id := ""
var _directory := ""
var _writer: BackgroundFileWriter
var _seen_area := ""
var _seen_signature := ""
var _warning_emitted := false
var _history_thread: Thread
var _history_mutex := Mutex.new()
var _history_cancel := {"cancelled": false}


func configure(actor_id: String, directory := "") -> DomainResult:
	var closed := close()
	if not closed.is_ok: return closed
	_actor_id = actor_id
	_directory = ProjectSettings.globalize_path(directory) if not directory.is_empty() else ""
	working_memory.clear()
	last_action.clear()
	_memories.clear()
	_sequence = 0
	_seen_area = ""
	_seen_signature = ""
	_warning_emitted = false
	if _directory.is_empty(): return DomainResult.ok()
	var checkpoint_path := _directory.path_join("memory.json")
	var journal_offset := 0
	if not FileAccess.file_exists(checkpoint_path) and FileAccess.file_exists(checkpoint_path + ".bak"):
		checkpoint_path += ".bak"
	if FileAccess.file_exists(checkpoint_path):
		var parser := JSON.new()
		var state: Variant = parser.data if parser.parse(FileAccess.get_file_as_string(checkpoint_path)) == OK else null
		if state is Dictionary and state.get("schema_version") == 1 and state.get("working_memory") is Dictionary and state.get("memories") is Dictionary and state.get("last_action") is Dictionary:
			working_memory = state.working_memory
			last_action = state.last_action
			_memories = state.memories
			_sequence = int(state.get("sequence", 0))
			journal_offset = int(state.get("journal_offset", 0))
	var journal_path := _directory.path_join("events.jsonl")
	if _sequence > 0 and not FileAccess.file_exists(journal_path):
		return DomainResult.failure(&"llm.memory_invalid", "LLM memory checkpoint has no source journal")
	if FileAccess.file_exists(journal_path):
		var journal := FileAccess.open(journal_path, FileAccess.READ_WRITE)
		if journal == null: return DomainResult.failure(&"llm.memory_storage_error", "cannot read LLM experience journal")
		if journal_offset < 0 or journal_offset > journal.get_length():
			return DomainResult.failure(&"llm.memory_invalid", "LLM journal cursor is outside the journal")
		journal.seek_end(-1 if journal.get_length() > 0 else 0)
		var incomplete_tail := journal.get_length() > 0 and journal.get_8() != 10
		journal.seek(journal_offset)
		while not journal.eof_reached():
			var record_start := journal.get_position()
			var line := journal.get_line()
			if line.is_empty(): continue
			var parser := JSON.new()
			var entry: Variant = parser.data if parser.parse(line) == OK else null
			if not entry is Dictionary and incomplete_tail and journal.get_position() == journal.get_length():
				if journal.resize(record_start) != OK:
					return DomainResult.failure(&"llm.memory_storage_error", "cannot repair incomplete experience journal tail")
				journal.seek(record_start)
				break
			if not entry is Dictionary or not entry.get("payload") is Dictionary or not entry.get("kind") is String or not entry.get("map_id") is String or not entry.has("observed_at") or not entry.has("sequence"):
				return DomainResult.failure(&"llm.memory_invalid", "LLM experience journal contains an invalid record")
			if int(entry.sequence) > _sequence:
				if int(entry.sequence) != _sequence + 1:
					return DomainResult.failure(&"llm.memory_invalid", "LLM experience journal is missing a record")
				_apply(entry)
		if journal.get_length() > 0:
			journal.seek_end(-1)
			if journal.get_8() != 10: journal.store_8(10)
		journal_offset = journal.get_position()
	_writer = MemoryWriter.new()
	(_writer as MemoryWriter).journal_offset = journal_offset
	if _writer.start() != OK:
		_writer = null
		return DomainResult.failure(&"llm.memory_storage_error", "cannot start LLM memory writer")
	return DomainResult.ok()


func record(kind: String, map_id: String, payload: Dictionary) -> DomainResult:
	var entry := {"sequence": _sequence + 1, "kind": kind, "map_id": map_id,
		"observed_at": Time.get_unix_time_from_system(), "payload": ObservationPolicy.public_value(payload, _actor_id)}
	if _writer != null:
		var result := _writer.last_result()
		if not result.is_ok:
			_warn(result.error_message)
			return result
		var accepted := _writer.enqueue_trace(_directory.path_join("events.jsonl"), entry, 1073741824)
		if accepted != OK:
			_warn("LLM experience journal queue is full")
			return DomainResult.failure(&"llm.memory_storage_error", "LLM experience journal could not be queued")
	_apply(entry)
	if _writer != null and (kind == "plan" or (kind == "action" and payload.get("tool") != "wait") or _sequence % 16 == 0):
		if _checkpoint() != OK: _warn("LLM memory checkpoint could not be queued")
	return DomainResult.ok()


func observe(observation: PlayerObservation) -> void:
	_seen_area = observation.map_id
	var species: Array[Dictionary] = []
	for option: Dictionary in observation.hunt_options:
		species.append({"species_id": option.get("species_id"), "display_name": option.get("display_name")})
	var minerals := {}
	for entity: Dictionary in observation.visible_entities:
		if entity.get("entity_kind") == "mine_source":
			minerals[String(entity.get("mineral_id", ""))] = {"mineral_id": entity.get("mineral_id"),
				"display_name": entity.get("display_name"), "required_mining_level": entity.get("required_mining_level")}
	var payload := {"hunt_species": species, "available_transitions": observation.available_transitions,
		"minerals": minerals.values(), "npcs": observation.npcs, "facilities": observation.facilities}
	var signature := JSON.stringify([observation.map_id, payload]).sha256_text()
	if signature == _seen_signature: return
	if record("area_seen", observation.map_id, payload).is_ok: _seen_signature = signature


func update_plan(arguments: Dictionary) -> DomainResult:
	for field: String in ["goal", "plan", "next_step"]:
		if not arguments.get(field) is String or arguments[field].length() > 1024:
			return DomainResult.failure(&"llm.plan_invalid", "计划字段必须是最多 1024 字符的文本")
	var recorded := record("plan", _seen_area, arguments)
	return DomainResult.ok(working_memory.duplicate(true)) if recorded.is_ok else recorded


func recall(map_id: String, query := "", limit := 6) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	var terms := query.to_lower().strip_edges().split(" ", false)
	for memory: Dictionary in _memories.values():
		var score := 4 if memory.map_id == map_id else 0
		var searchable := JSON.stringify(memory.payload).to_lower()
		for field: String in ["goal", "plan", "next_step"]:
			var intention := String(working_memory.get(field, "")).to_lower()
			if intention.is_empty(): continue
			var landmarks: Array = memory.payload.get("available_transitions", []) if memory.kind == "area_seen" else []
			for landmark: Dictionary in landmarks:
				var label := String(landmark.get("label", "")).to_lower()
				if not label.is_empty() and intention.contains(label): score += 2
		for term: String in terms:
			if searchable.contains(term) or String(memory.kind).contains(term) or String(memory.map_id).contains(term): score += 8
		if not terms.is_empty() and score <= 4: continue
		candidates.append({"score": score, "memory": memory})
	candidates.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return left.score > right.score if left.score != right.score else left.memory.last_observed > right.memory.last_observed)
	var result: Array[Dictionary] = []
	var remaining := CONTEXT_CHARACTERS
	for candidate: Dictionary in candidates:
		var memory: Dictionary = candidate.memory.duplicate(true)
		memory.erase("first_source")
		memory.erase("last_source")
		var size := JSON.stringify(memory).length()
		if size > remaining: continue
		result.append(memory)
		remaining -= size
		if result.size() >= limit: break
	return result


func context(observation: PlayerObservation, trigger: Dictionary = {}) -> Dictionary:
	var terms: Array[String] = []
	for field: String in ["display_name", "species_id", "inviter_name", "sender_name", "map_id"]:
		if trigger.get(field) is String: terms.append(trigger[field])
	var memories := recall(observation.map_id, " ".join(terms))
	if memories.is_empty(): memories = recall(observation.map_id)
	return {"working_memory": working_memory.duplicate(true), "relevant_memories": memories,
		"last_action": last_action.duplicate(true)}


func close() -> DomainResult:
	if _history_thread != null:
		_history_mutex.lock()
		_history_cancel.cancelled = true
		_history_mutex.unlock()
		_history_thread.wait_to_finish()
		_history_thread = null
	if _writer != null: _checkpoint()
	var result: DomainResult = _writer.close() if _writer != null else DomainResult.ok()
	_writer = null
	return result


func search_history(query: String) -> DomainResult:
	if query.strip_edges().is_empty() or query.length() > 256:
		return DomainResult.failure(&"llm.memory_query_invalid", "历史检索需要 1..256 字符的关键词")
	if _history_thread != null: return DomainResult.failure(&"llm.history_busy", "已有历史检索正在进行，请等待结果事件")
	var path := _directory.path_join("events.jsonl")
	if _directory.is_empty() or not FileAccess.file_exists(path):
		return DomainResult.ok({"status": "completed", "scope": "recent_index", "query": query, "memories": recall(_seen_area, query)})
	_history_cancel = {"cancelled": false}
	_history_thread = Thread.new()
	if _history_thread.start(_search_journal.bind(path, query, _history_cancel, _history_mutex), Thread.PRIORITY_LOW) != OK:
		_history_thread = null
		return DomainResult.failure(&"llm.history_unavailable", "无法启动历史检索")
	return DomainResult.ok({"status": "searching", "query": query, "message": "后台检索中，完成后返回 history_search_result；可以继续行动或等待，不要重复查询。"})


func poll_history() -> DomainResult:
	if _history_thread == null or _history_thread.is_alive(): return null
	var result: DomainResult = _history_thread.wait_to_finish()
	_history_thread = null
	return result


static func _search_journal(path: String, query: String, cancel: Dictionary, mutex: Mutex) -> DomainResult:
	var journal := FileAccess.open(path, FileAccess.READ)
	if journal == null: return DomainResult.failure(&"llm.history_unavailable", "无法读取经历日志")
	var end := journal.get_length()
	var terms := Array(query.to_lower().strip_edges().split(" ", false))
	var matches: Array[Dictionary] = []
	while journal.get_position() < end:
		mutex.lock()
		var cancelled: bool = cancel.cancelled
		mutex.unlock()
		if cancelled: return DomainResult.failure(&"llm.history_cancelled", "检索已取消")
		var parser := JSON.new()
		var line := journal.get_line()
		if line.is_empty(): continue
		if parser.parse(line) != OK or not parser.data is Dictionary:
			if journal.get_position() >= end: break
			return DomainResult.failure(&"llm.memory_invalid", "经历日志存在无法解析的记录")
		var entry: Dictionary = parser.data
		if entry.get("kind") == "plan" or not entry.get("payload") is Dictionary: continue
		var searchable := JSON.stringify([entry.get("kind"), entry.get("map_id"), entry.payload]).to_lower()
		if not terms.all(func(term: String) -> bool: return searchable.contains(term)): continue
		var payload: Dictionary = entry.payload
		if JSON.stringify(payload).length() > 1000:
			payload = {"preview": JSON.stringify(payload).left(600), "truncated": true}
		matches.append({"kind": entry.get("kind"), "map_id": entry.get("map_id"), "observed_at": entry.get("observed_at"),
			"knowledge_status": "reported" if String(entry.get("kind", "")).contains("chat") or entry.get("kind") in ["player_message", "mail_received"] else "experienced", "payload": payload})
		while matches.size() > 6 or JSON.stringify(matches).length() > CONTEXT_CHARACTERS: matches.pop_front()
	return DomainResult.ok({"status": "completed", "scope": "persisted_history", "query": query, "memories": matches})


func _checkpoint() -> Error:
	return _writer.enqueue_snapshot(_directory.path_join("memory.json"), {"schema_version": 1,
		"sequence": _sequence, "working_memory": working_memory, "last_action": last_action, "memories": _memories}, false, true)


func _apply(entry: Dictionary) -> void:
	_sequence = int(entry.sequence)
	var payload: Dictionary = entry.payload
	if entry.kind == "plan":
		working_memory = payload.duplicate(true)
		return
	if entry.kind == "action": last_action = payload.duplicate(true)
	if entry.kind == "action" and payload.get("tool") == "wait": return
	if entry.kind == "tool_result" and payload.get("tool_id") in STATE_QUERIES: return
	if entry.kind == "tool_result" and payload.get("tool_id") == "inspect_manufacturing" and payload.get("ok") == true:
		var station: Dictionary = payload.get("value", {}).get("manufacturing", {})
		for recipe: Dictionary in station.get("recipes", []):
			if not recipe.has("materials"): continue
			var known := recipe.duplicate(true)
			known["station_id"] = recipe.get("station_id", station.get("station_id"))
			for field: String in ["effective_skill_level", "can_craft", "available_batches", "success_probability"]: known.erase(field)
			for material: Dictionary in known.get("materials", []): material.erase("owned")
			_remember(entry, ["recipe", known.station_id, recipe.get("recipe_id")], known, "procedural")
		return
	var subject: Variant = payload
	if entry.kind == "area_seen": subject = "area"
	if entry.kind == "tool_result": subject = [payload.get("tool_id"), payload.get("arguments"), payload.get("ok"), payload.get("error_code")]
	_remember(entry, subject, payload, "spatial" if entry.kind == "area_seen" else "")


func _remember(entry: Dictionary, subject: Variant, payload: Dictionary, knowledge_kind: String) -> void:
	var key := JSON.stringify([entry.kind, entry.map_id, subject]).sha256_text()
	var memory: Dictionary = _memories.get(key, {"kind": entry.kind, "map_id": entry.map_id,
		"payload": payload.duplicate(true), "knowledge_status": "reported" if String(entry.kind).contains("chat") or entry.kind in ["player_message", "mail_received"] else "experienced",
		"first_observed": entry.observed_at, "first_source": entry.sequence, "occurrences": 0})
	memory["last_observed"] = entry.observed_at
	memory["last_source"] = entry.sequence
	memory["payload"] = payload.duplicate(true)
	memory["occurrences"] = int(memory.occurrences) + 1
	if entry.kind == "tool_result" and payload.get("ok") == false and memory.occurrences >= 2:
		knowledge_kind = "procedural"
		memory["lesson"] = "相同操作与参数在此地曾多次失败；这是历史经验，当前条件可能已改变，请用新观察验证。"
	if not knowledge_kind.is_empty(): memory["knowledge_kind"] = knowledge_kind
	_memories.erase(key)
	_memories[key] = memory
	if _memories.size() > MAX_MEMORIES:
		var episodic := _memories.keys().filter(func(candidate: String) -> bool: return not _memories[candidate].has("knowledge_kind"))
		_memories.erase(episodic[0] if not episodic.is_empty() else _memories.keys()[0])


func _warn(message: String) -> void:
	if not _warning_emitted:
		_warning_emitted = true
		push_warning(message)
