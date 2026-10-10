class_name LlmTurnBudget
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var max_provider_calls := 4
var max_tool_calls := 8
var max_wall_clock_msec := 30000
var provider_calls := 0
var tool_calls := 0
var started_at_msec := -1


func begin(now_msec := -1) -> DomainResult:
	provider_calls = 0
	tool_calls = 0
	started_at_msec = now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return Result.ok(self)


func consume_provider_call(now_msec := -1) -> DomainResult:
	if provider_calls >= max_provider_calls:
		return Result.failure(&"llm.provider_budget_exhausted", "turn provider-call budget is exhausted")
	var available := check_wall_clock(now_msec)
	if not available.is_ok:
		return available
	provider_calls += 1
	return Result.ok(self)


func consume_tool_call(now_msec := -1) -> DomainResult:
	if tool_calls >= max_tool_calls:
		return Result.failure(&"llm.tool_budget_exhausted", "turn tool-call budget is exhausted")
	var available := check_wall_clock(now_msec)
	if not available.is_ok:
		return available
	tool_calls += 1
	return Result.ok(self)


func check_wall_clock(now_msec := -1) -> DomainResult:
	return Result.failure(&"llm.turn_budget_exhausted", "turn wall-clock budget is exhausted") \
		if _expired(now_msec) else Result.ok(self)


func remaining_msec(now_msec := -1) -> int:
	if started_at_msec < 0 or max_wall_clock_msec <= 0:
		return max_wall_clock_msec
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return maxi(0, max_wall_clock_msec - maxi(0, current_time - started_at_msec))


func snapshot() -> Dictionary:
	return {
		"max_provider_calls": max_provider_calls,
		"max_tool_calls": max_tool_calls,
		"max_wall_clock_msec": max_wall_clock_msec,
		"provider_calls": provider_calls,
		"tool_calls": tool_calls,
		"started_at_msec": started_at_msec,
	}


func _expired(now_msec := -1) -> bool:
	if started_at_msec < 0 or max_wall_clock_msec <= 0:
		return false
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return current_time - started_at_msec >= max_wall_clock_msec
