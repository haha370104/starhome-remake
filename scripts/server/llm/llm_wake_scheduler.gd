class_name LlmWakeScheduler
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

signal wake_requested(actor_id: String)

var _wake: Callable
var _entries: Dictionary = {}


func configure(wake: Callable) -> DomainResult:
	if not wake.is_valid():
		return Result.failure(&"llm.wake_scheduler_invalid", "wake callback is required")
	_wake = wake
	_entries.clear()
	return Result.ok(self)


func register(actor_id: String, interval_seconds := 15.0) -> DomainResult:
	if actor_id.is_empty() or interval_seconds <= 0.0 or not _wake.is_valid():
		return Result.failure(&"llm.wake_scheduler_invalid", "actor, interval and wake callback are required")
	_entries[actor_id] = {
		"interval_seconds": interval_seconds,
		"remaining_seconds": interval_seconds,
	}
	return Result.ok()


func unregister(actor_id: String) -> DomainResult:
	_entries.erase(actor_id)
	return Result.ok()


func advance(elapsed_seconds: float) -> DomainResult:
	if elapsed_seconds <= 0.0:
		return Result.ok(0)
	var wake_count := 0
	for actor_id: String in _entries.keys():
		var entry: Dictionary = _entries[actor_id]
		var remaining := float(entry.remaining_seconds) - elapsed_seconds
		if remaining > 0.0:
			entry.remaining_seconds = remaining
			_entries[actor_id] = entry
			continue
		entry.remaining_seconds = float(entry.interval_seconds)
		_entries[actor_id] = entry
		var wake_result: Variant = _wake.call(actor_id)
		if not wake_result is DomainResult:
			return Result.failure(&"llm.wake_scheduler_invalid", "wake callback must return a DomainResult")
		var result: DomainResult = wake_result
		if not result.is_ok:
			return result
		wake_requested.emit(actor_id)
		wake_count += 1
	return Result.ok(wake_count)


func has_actor(actor_id: String) -> bool:
	return _entries.has(actor_id)
