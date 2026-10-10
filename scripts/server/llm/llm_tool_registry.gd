class_name LlmToolRegistry
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var _tools: Dictionary = {}


func register(tool: LlmAgentTool) -> DomainResult:
	if tool == null:
		return Result.failure(&"llm.tool_invalid", "tool is required")
	var validation := tool.validate()
	if not validation.is_ok:
		return validation
	if _tools.has(tool.tool_id):
		return Result.failure(&"llm.tool_duplicate", "tool id is already registered")
	_tools[tool.tool_id] = tool
	return Result.ok(tool)


func tool_for(tool_id: String) -> LlmAgentTool:
	return _tools.get(tool_id)


func descriptors() -> Array[Dictionary]:
	var tool_ids: Array = _tools.keys()
	tool_ids.sort()
	var result: Array[Dictionary] = []
	for tool_id: String in tool_ids:
		result.append((_tools[tool_id] as LlmAgentTool).to_dictionary())
	return result
