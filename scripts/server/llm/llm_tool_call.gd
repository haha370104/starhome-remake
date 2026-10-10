class_name LlmToolCall
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var tool_id := ""
var arguments: Dictionary = {}
var call_id := ""


func _init(
	requested_tool_id: String,
	requested_arguments: Dictionary = {},
	requested_call_id := "",
) -> void:
	tool_id = requested_tool_id
	arguments = requested_arguments.duplicate(true)
	call_id = requested_call_id


func validate() -> DomainResult:
	if tool_id.is_empty() or tool_id.length() > 64:
		return Result.failure(&"llm.tool_call_invalid", "tool id is invalid")
	if call_id.length() > 128:
		return Result.failure(&"llm.tool_call_invalid", "provider call id is invalid")
	return Result.ok(self)


func to_dictionary() -> Dictionary:
	var result := {"type": "tool_call", "tool_id": tool_id, "arguments": arguments.duplicate(true)}
	if not call_id.is_empty():
		result["call_id"] = call_id
	return result


static func from_dictionary(raw: Variant) -> DomainResult:
	if raw is LlmToolCall:
		var call: LlmToolCall = raw
		var validation := call.validate()
		return Result.ok(call) if validation.is_ok else validation
	if not raw is Dictionary or raw.size() not in [3, 4] or raw.get("type") != "tool_call" \
			or typeof(raw.get("tool_id")) != TYPE_STRING or not raw.get("arguments") is Dictionary:
		return Result.failure(&"llm.tool_call_invalid", "provider response is not a valid tool call")
	var tool_call := LlmToolCall.new(
		String(raw.tool_id), raw.arguments, String(raw.get("call_id", ""))
	)
	var validation := tool_call.validate()
	return Result.ok(tool_call) if validation.is_ok else validation
