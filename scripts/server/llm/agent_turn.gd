class_name LlmAgentTurn
extends RefCounted

var turn_id := ""
var trigger_kind: StringName = &""
var trigger_payload: Dictionary = {}
var observation_revision := -1
var started_at_msec := 0
var finished_at_msec := -1
var status: StringName = &"active"
var failure_code: StringName = &""
var failure_message := ""
var chosen_action: Dictionary = {}
var submitted_intent: Dictionary = {}
var interruption_reason: StringName = &""
var initial_observation: Dictionary = {}
var world_state_diff: Dictionary = {}
var tool_calls: Array[Dictionary] = []


## 保存一次 LLM 唤醒的生命周期数据，供诊断、回放和后续记忆提取使用。
func _init(
	requested_turn_id: String,
	requested_trigger_kind: StringName,
	requested_trigger_payload: Dictionary,
	requested_observation_revision: int,
	requested_started_at_msec := -1,
) -> void:
	turn_id = requested_turn_id
	trigger_kind = requested_trigger_kind
	trigger_payload = requested_trigger_payload.duplicate(true)
	observation_revision = requested_observation_revision
	started_at_msec = requested_started_at_msec if requested_started_at_msec >= 0 else Time.get_ticks_msec()


func record_tool_call(tool_id: String, arguments: Dictionary, result: DomainResult) -> void:
	tool_calls.append({
		"tool_id": tool_id,
		"arguments": arguments.duplicate(true),
		"ok": result.is_ok,
		"value": result.value.duplicate(true) if result.is_ok and result.value is Dictionary else null,
		"error_code": String(result.error_code),
		"error_message": result.error_message,
	})


func complete(action: Dictionary, intent: Dictionary, result: DomainResult) -> void:
	chosen_action = action.duplicate(true)
	submitted_intent = intent.duplicate(true)
	finished_at_msec = Time.get_ticks_msec()
	if result.is_ok:
		status = &"completed"
	else:
		status = &"failed"
		failure_code = result.error_code
		failure_message = result.error_message


func interrupt(reason: StringName) -> void:
	status = &"interrupted"
	interruption_reason = reason
	finished_at_msec = Time.get_ticks_msec()


func fail(code: StringName, message: String) -> void:
	status = &"failed"
	failure_code = code
	failure_message = message
	finished_at_msec = Time.get_ticks_msec()


func to_dictionary() -> Dictionary:
	return {
		"turn_id": turn_id,
		"trigger_kind": String(trigger_kind),
		"trigger_payload": trigger_payload.duplicate(true),
		"observation_revision": observation_revision,
		"started_at_msec": started_at_msec,
		"finished_at_msec": finished_at_msec,
		"status": String(status),
		"failure_code": String(failure_code),
		"failure_message": failure_message,
		"chosen_action": chosen_action.duplicate(true),
		"submitted_intent": submitted_intent.duplicate(true),
		"interruption_reason": String(interruption_reason),
		"initial_observation": initial_observation.duplicate(true),
		"world_state_diff": world_state_diff.duplicate(true),
		"tool_calls": tool_calls.duplicate(true),
	}
