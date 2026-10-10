class_name LlmToolRouter
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var _registry: LlmToolRegistry
var _handlers: Dictionary = {}


func configure(registry: LlmToolRegistry) -> DomainResult:
	if registry == null:
		return Result.failure(&"llm.tool_registry_missing", "tool registry is required")
	_registry = registry
	_handlers.clear()
	return Result.ok(self)


func bind(tool_id: String, handler: Callable) -> DomainResult:
	if _registry == null:
		return Result.failure(&"llm.tool_router_unavailable", "tool router is not configured")
	if _registry.tool_for(tool_id) == null or not handler.is_valid():
		return Result.failure(&"llm.tool_invalid", "tool and handler are required")
	_handlers[tool_id] = handler
	return Result.ok()


func invoke(actor_id: String, tool_id: String, arguments: Dictionary = {}) -> DomainResult:
	if _registry == null:
		return Result.failure(&"llm.tool_router_unavailable", "tool router is not configured")
	var tool := _registry.tool_for(tool_id)
	if tool == null:
		return Result.failure(&"llm.tool_unknown", "tool is not registered")
	var validated := tool.validate_arguments(arguments)
	if not validated.is_ok: return validated
	var handler: Callable = _handlers.get(tool_id, Callable())
	if not handler.is_valid():
		return Result.failure(&"llm.tool_unavailable", "tool handler is not bound")
	var result: Variant = handler.call(actor_id, validated.value)
	return result if result is DomainResult else Result.failure(
		&"llm.tool_invalid_result", "tool handler must return a DomainResult"
	)
