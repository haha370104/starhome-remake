class_name LlmEventBus
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")
const AgentEventScript = preload("res://scripts/server/llm/agent_event.gd")

signal published(actor_id: String, event: LlmAgentEvent)

var max_seen_events := 2048
var _delivery: Callable
var _seen: Dictionary = {}
var _seen_order: Array[String] = []


func configure(delivery: Callable) -> DomainResult:
	if not delivery.is_valid():
		return Result.failure(&"llm.event_bus_invalid", "event delivery is required")
	_delivery = delivery
	_seen.clear()
	_seen_order.clear()
	return Result.ok(self)


func publish(actor_id: String, raw_event: Variant) -> DomainResult:
	if actor_id.is_empty() or not _delivery.is_valid():
		return Result.failure(&"llm.event_bus_unavailable", "event bus is not configured")
	var parsed := AgentEventScript.from_dictionary(raw_event)
	if not parsed.is_ok:
		return parsed
	var event: LlmAgentEvent = parsed.value
	var key := "%s:%s" % [actor_id, event.event_id]
	if _seen.has(key):
		return Result.ok(event)
	_seen[key] = true
	_seen_order.append(key)
	_trim_seen_events()
	var delivered: Variant = _delivery.call(actor_id, event)
	if not delivered is DomainResult:
		_forget(key)
		return Result.failure(&"llm.event_delivery_invalid", "event delivery must return a DomainResult")
	var result: DomainResult = delivered
	if not result.is_ok:
		_forget(key)
		return result
	published.emit(actor_id, event)
	return result


func clear_actor(actor_id: String) -> void:
	var prefix := actor_id + ":"
	for key: String in _seen_order.duplicate():
		if key.begins_with(prefix):
			_forget(key)


func clear() -> void:
	_seen.clear()
	_seen_order.clear()


func _trim_seen_events() -> void:
	while _seen_order.size() > maxi(1, max_seen_events):
		_seen.erase(_seen_order.pop_front())


func _forget(key: String) -> void:
	_seen.erase(key)
	_seen_order.erase(key)
