class_name ReplayLlmProvider
extends LlmProvider

const HighLevelPlayerActionScript = preload("res://scripts/server/llm/high_level_player_action.gd")
const LlmToolCallScript = preload("res://scripts/server/llm/llm_tool_call.gd")

var _actions: Array[Variant] = []


func configure(actions: Array) -> DomainResult:
	_actions.clear()
	for action: Variant in actions:
		_actions.append(action)
	return Result.ok(self)


func create_turn(_observation: PlayerObservation, _context: Dictionary = {}) -> DomainResult:
	return _next_action()


func continue_turn(
	_observation: PlayerObservation,
	_context: Dictionary,
	_tool_result: Dictionary,
) -> DomainResult:
	return _next_action()


func _next_action() -> DomainResult:
	if _actions.is_empty():
		return Result.failure(&"llm.replay_exhausted", "replay provider has no remaining action")
	var raw_action: Variant = _actions.pop_front()
	if raw_action is DomainResult:
		return raw_action
	if raw_action is HighLevelPlayerAction:
		return Result.ok(raw_action)
	if raw_action is LlmToolCall or raw_action is Dictionary and raw_action.get("type") == "tool_call":
		return LlmToolCallScript.from_dictionary(raw_action)
	return HighLevelPlayerActionScript.from_dictionary(raw_action)
