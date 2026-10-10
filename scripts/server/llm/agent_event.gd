class_name LlmAgentEvent
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var event_id := ""
var event_kind: StringName = &""
var payload: Dictionary = {}
var interrupts_current_turn := false
var created_at_msec := 0


## 描述一次可能唤醒 LLM 的游戏事件；事件本身不携带权威对象引用。
## [param requested_event_id] 稳定事件身份，用于回放和去重。
## [param requested_event_kind] 语义事件类型。
## [param requested_payload] 供 provider 读取的只读事件数据。
## [param requested_interrupts_current_turn] 是否中断当前确定性决策。
func _init(
	requested_event_id: String,
	requested_event_kind: StringName,
	requested_payload: Dictionary = {},
	requested_interrupts_current_turn := false,
	requested_created_at_msec := -1,
) -> void:
	event_id = requested_event_id
	event_kind = requested_event_kind
	payload = requested_payload.duplicate(true)
	interrupts_current_turn = requested_interrupts_current_turn
	created_at_msec = requested_created_at_msec if requested_created_at_msec >= 0 else Time.get_ticks_msec()


func validate() -> DomainResult:
	if event_id.is_empty() or event_kind == &"":
		return Result.failure(&"llm.event_invalid", "event id and kind are required")
	if event_id.length() > 128 or String(event_kind).length() > 64:
		return Result.failure(&"llm.event_invalid", "event id or kind is too long")
	return Result.ok(self)


func to_dictionary() -> Dictionary:
	return {
		"event_id": event_id,
		"event_kind": String(event_kind),
		"payload": payload.duplicate(true),
		"interrupts_current_turn": interrupts_current_turn,
		"created_at_msec": created_at_msec,
	}


static func from_dictionary(raw: Variant) -> DomainResult:
	if raw is RefCounted and raw.has_method("validate") and raw.has_method("to_dictionary"):
		var event: RefCounted = raw
		var validation: DomainResult = event.validate()
		return Result.ok(event) if validation.is_ok else validation
	if not raw is Dictionary:
		return Result.failure(&"llm.event_invalid", "event must be a Dictionary")
	var source: Dictionary = raw
	var event_script: GDScript = load("res://scripts/server/llm/agent_event.gd")
	var event: RefCounted = event_script.new(
		String(source.get("event_id", "")),
		StringName(source.get("event_kind", "")),
		source.get("payload", {}) if source.get("payload", {}) is Dictionary else {},
		bool(source.get("interrupts_current_turn", false)),
		int(source.get("created_at_msec", -1)),
	)
	var validation: DomainResult = event.validate()
	return Result.ok(event) if validation.is_ok else validation
