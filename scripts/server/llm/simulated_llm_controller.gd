class_name SimulatedLlmController
extends Node

const Result = preload("res://scripts/core/domain_result.gd")
const HighLevelPlayerActionScript = preload("res://scripts/server/llm/high_level_player_action.gd")
const CallableLlmProviderScript = preload("res://scripts/server/llm/callable_llm_provider.gd")
const LlmToolCallScript = preload("res://scripts/server/llm/llm_tool_call.gd")

signal action_ready(action: HighLevelPlayerAction)
signal decision_failed(code: StringName, message: String)
signal tool_call_ready(tool_call: LlmToolCall)

var decision_provider: Callable
var _provider: LlmProvider
var decision_delay_seconds := 0.0
var decision_timeout_seconds := 180.0
var _pending: Array[Dictionary] = []
var _provider_generation := 0
var _provider_in_flight := false
var _provider_deadline_msec := -1


func configure(provider_input: Variant, delay_seconds := 0.0, timeout_seconds := 180.0) -> DomainResult:
	if provider_input is LlmProvider:
		cancel_pending()
		_provider = provider_input
	elif provider_input is Callable:
		var callable_provider = CallableLlmProviderScript.new()
		var configured := callable_provider.configure(provider_input)
		if not configured.is_ok:
			return configured
		cancel_pending()
		_provider = callable_provider
		decision_provider = provider_input
	else:
		return Result.failure(&"llm.provider_invalid", "an LLM provider is required")
	decision_delay_seconds = maxf(0.0, delay_seconds)
	decision_timeout_seconds = maxf(0.001, timeout_seconds)
	_pending.clear()
	_provider_in_flight = false
	_provider_deadline_msec = -1
	set_process(true)
	return Result.ok(self)


func request_decision(
	observation: PlayerObservation,
	context: Dictionary = {},
	remaining_seconds := -1.0,
) -> DomainResult:
	return _queue_request(observation, context, remaining_seconds)


func request_tool_continuation(
	observation: PlayerObservation,
	context: Dictionary,
	tool_result: Dictionary,
	remaining_seconds := -1.0,
) -> DomainResult:
	return _queue_request(observation, context, remaining_seconds, tool_result)


func _queue_request(
	observation: PlayerObservation, context: Dictionary, remaining_seconds: float, tool_result: Variant = null,
) -> DomainResult:
	if _provider == null:
		return Result.failure(&"llm.provider_invalid", "LLM provider is not configured")
	if observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required")
	var timeout_seconds := decision_timeout_seconds
	if remaining_seconds >= 0.0:
		timeout_seconds = minf(timeout_seconds, remaining_seconds)
	if timeout_seconds <= 0.0:
		return Result.failure(&"llm.turn_budget_exhausted", "LLM turn deadline has elapsed")
	var now_msec := Time.get_ticks_msec()
	var request := {
		"due_at_msec": now_msec + roundi(decision_delay_seconds * 1000.0),
		"deadline_msec": now_msec + roundi(timeout_seconds * 1000.0),
		"observation": observation,
		"context": context.duplicate(true),
	}
	if tool_result != null:
		request["tool_result"] = tool_result.duplicate(true)
	_pending.append(request)
	set_process(true)
	return Result.ok()


## 取消尚未交给 provider 的决定；不会伪造动作结果。
## 返回本次被取消的请求数量。
func cancel_pending() -> int:
	var count := _pending.size() + (1 if _provider_in_flight else 0)
	_pending.clear()
	_provider_generation += 1
	_provider_in_flight = false
	_provider_deadline_msec = -1
	if _provider != null:
		_provider.cancel_turn()
	if count > 0: set_process(false)
	return count


func complete_tool_call(tool_call: LlmToolCall, result: Dictionary, actor_id: String) -> void:
	if _provider != null: _provider.complete_tool_call(tool_call, result, actor_id)


func _process(_delta: float) -> void:
	var now_msec := Time.get_ticks_msec()
	if _provider_in_flight:
		if now_msec >= _provider_deadline_msec:
			_provider_generation += 1
			_provider_in_flight = false
			_provider.cancel_turn()
			decision_failed.emit(&"llm.provider_timeout", "LLM provider decision timed out")
		set_process(_provider_in_flight or not _pending.is_empty())
		return
	if _pending.is_empty():
		set_process(false)
		return
	var ready_requests: Array[Dictionary] = []
	for request: Dictionary in _pending:
		if now_msec >= int(request["due_at_msec"]) or now_msec >= int(request["deadline_msec"]):
			ready_requests.append(request)
	for request: Dictionary in ready_requests:
		_pending.erase(request)
		if now_msec >= int(request["deadline_msec"]):
			decision_failed.emit(&"llm.provider_timeout", "simulated provider decision timed out")
		else:
			_start_provider_request(request)
		if _provider_in_flight:
			break
	set_process(_provider_in_flight or not _pending.is_empty())


func _start_provider_request(request: Dictionary) -> void:
	_provider_generation += 1
	var generation := _provider_generation
	_provider_in_flight = true
	_provider_deadline_msec = int(request["deadline_msec"])
	request.context["request_timeout_seconds"] = maxf(0.001, float(_provider_deadline_msec - Time.get_ticks_msec()) / 1000.0)
	var completion := Callable(self, "_on_provider_result").bind(generation)
	var requested := _provider.request_continuation(
		request.observation,
		request.context,
		request.get("tool_result", {}),
		completion,
	) if request.has("tool_result") else _provider.request_turn(
		request.observation,
		request.context,
		completion,
	)
	if not requested.is_ok:
		_provider_in_flight = false
		decision_failed.emit(requested.error_code, requested.error_message)


func _on_provider_result(provider_result: DomainResult, generation: int) -> void:
	if generation != _provider_generation or not _provider_in_flight:
		return
	var deadline_msec := _provider_deadline_msec
	_provider_in_flight = false
	_provider_deadline_msec = -1
	if Time.get_ticks_msec() >= deadline_msec:
		decision_failed.emit(&"llm.provider_timeout", "LLM provider decision timed out")
	else:
		_emit_provider_response(provider_result)
	set_process(not _pending.is_empty())


func _emit_provider_response(provider_result: DomainResult) -> void:
	if not provider_result.is_ok:
		decision_failed.emit(provider_result.error_code, provider_result.error_message)
		return
	var response: Variant = provider_result.value
	if response is HighLevelPlayerAction:
		action_ready.emit(response)
	elif response is LlmToolCallScript:
		tool_call_ready.emit(response)
	elif response is Dictionary and response.get("type") == "tool_call":
		var tool_call_result: DomainResult = LlmToolCallScript.from_dictionary(response)
		if tool_call_result.is_ok:
			tool_call_ready.emit(tool_call_result.value)
		else:
			decision_failed.emit(tool_call_result.error_code, tool_call_result.error_message)
	elif response is Dictionary:
		var action_result: DomainResult = HighLevelPlayerActionScript.from_dictionary(response)
		if action_result.is_ok:
			action_ready.emit(action_result.value)
		else:
			decision_failed.emit(action_result.error_code, action_result.error_message)
	else:
		decision_failed.emit(&"llm.provider_response_invalid", "provider returned an unsupported response")
