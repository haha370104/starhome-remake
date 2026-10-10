class_name LlmAgentTool
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var tool_id := ""
var description := ""
var input_schema: Dictionary = {}
var tool_kind := "query"


func _init(
	requested_tool_id: String,
	requested_description: String,
	requested_input_schema: Dictionary = {},
	requested_tool_kind := "query",
) -> void:
	tool_id = requested_tool_id
	description = requested_description
	input_schema = requested_input_schema.duplicate(true)
	tool_kind = requested_tool_kind


func validate() -> DomainResult:
	if tool_id.is_empty() or tool_id.length() > 64:
		return Result.failure(&"llm.tool_invalid", "tool id is invalid")
	if description.is_empty() or description.length() > 512:
		return Result.failure(&"llm.tool_invalid", "tool description is invalid")
	if tool_kind not in ["query", "action"]:
		return Result.failure(&"llm.tool_invalid", "tool kind must be query or action")
	return Result.ok(self)


func to_dictionary() -> Dictionary:
	return {
		"name": tool_id,
		"description": description,
		"input_schema": input_schema.duplicate(true),
		"tool_kind": tool_kind,
	}


func validate_arguments(arguments: Dictionary) -> DomainResult:
	var properties: Dictionary = input_schema.get("properties", {})
	if arguments.size() != properties.size():
		return Result.failure(&"llm.tool_arguments_invalid", "工具参数必须包含且仅包含：%s" % str(properties.keys()))
	var normalized := arguments.duplicate(true)
	for field: String in properties:
		if not arguments.has(field) or not _matches_parameter(arguments[field], properties[field]):
			return Result.failure(&"llm.tool_arguments_invalid", "参数 %s 不符合工具定义" % field)
		if typeof(arguments[field]) == TYPE_FLOAT:
			normalized[field] = int(arguments[field])
	return Result.ok(normalized)


func _matches_parameter(value: Variant, schema: Dictionary) -> bool:
	if schema.has("anyOf"):
		for option: Dictionary in schema.anyOf:
			if _matches_parameter(value, option): return true
		return false
	match schema.get("type"):
		"null": return value == null
		"string": return value is String and (not schema.has("enum") or value in schema.enum)
		"boolean": return typeof(value) == TYPE_BOOL
		"integer": return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == float(int(value))
		"array": return value is Array and value.all(func(entry: Variant) -> bool: return _matches_parameter(entry, schema.get("items", {})))
	return false
