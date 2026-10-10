class_name CallableLlmProvider
extends LlmProvider

const HighLevelPlayerActionScript = preload("res://scripts/server/llm/high_level_player_action.gd")
const LlmToolCallScript = preload("res://scripts/server/llm/llm_tool_call.gd")

var decision_provider: Callable


func configure(provider: Callable) -> DomainResult:
	if not provider.is_valid():
		return Result.failure(&"llm.provider_invalid", "callable provider is required")
	decision_provider = provider
	return Result.ok(self)


func create_turn(observation: PlayerObservation, context: Dictionary = {}) -> DomainResult:
	return _call_provider(observation, context)


func continue_turn(
	observation: PlayerObservation,
	context: Dictionary,
	tool_result: Dictionary,
) -> DomainResult:
	var continuation := context.duplicate(true)
	continuation["tool_result"] = tool_result.duplicate(true)
	continuation["continuation"] = true
	return _call_provider(observation, continuation)


func _call_provider(observation: PlayerObservation, context: Dictionary) -> DomainResult:
	if not decision_provider.is_valid():
		return Result.failure(&"llm.provider_invalid", "callable provider is not configured")
	if observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required")
	var frame := observation.to_dictionary()
	if not context.is_empty():
		frame["turn"] = context.duplicate(true)
	var raw_action: Variant = decision_provider.call(frame)
	if raw_action is DomainResult:
		if not raw_action.is_ok:
			return raw_action
		raw_action = raw_action.value
	if raw_action is HighLevelPlayerAction:
		return Result.ok(raw_action)
	if raw_action is LlmToolCall or raw_action is Dictionary and raw_action.get("type") == "tool_call":
		return LlmToolCallScript.from_dictionary(raw_action)
	return HighLevelPlayerActionScript.from_dictionary(raw_action)
