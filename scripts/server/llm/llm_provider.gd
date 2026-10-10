class_name LlmProvider
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")


func create_turn(_observation: PlayerObservation, _context: Dictionary = {}) -> DomainResult:
	return Result.failure(&"llm.provider_abstract", "provider does not implement create_turn")


func continue_turn(
	_observation: PlayerObservation,
	_context: Dictionary,
	_tool_result: Dictionary,
) -> DomainResult:
	return Result.failure(&"llm.provider_abstract", "provider does not implement continue_turn")


func request_turn(
	observation: PlayerObservation,
	context: Dictionary,
	completion: Callable,
) -> DomainResult:
	if not completion.is_valid():
		return Result.failure(&"llm.provider_invalid", "provider completion is required")
	var result := create_turn(observation, context)
	completion.call(result)
	return Result.ok()


func request_continuation(
	observation: PlayerObservation,
	context: Dictionary,
	tool_result: Dictionary,
	completion: Callable,
) -> DomainResult:
	if not completion.is_valid():
		return Result.failure(&"llm.provider_invalid", "provider completion is required")
	var result := continue_turn(observation, context, tool_result)
	completion.call(result)
	return Result.ok()


func cancel_turn() -> void:
	pass


func complete_tool_call(_tool_call: LlmToolCall, _result: Dictionary, _actor_id: String) -> void:
	pass
