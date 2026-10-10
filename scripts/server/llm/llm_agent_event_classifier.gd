class_name LlmAgentEventClassifier
extends RefCounted

const IGNORE: StringName = &"ignore"
const QUEUE: StringName = &"queue"
const INBOX: StringName = &"inbox"
const INTERRUPT: StringName = &"interrupt"

const IGNORED_KINDS: Array[StringName] = [
	&"position_changed",
	&"cooldown_tick",
	&"path_node_changed",
	&"attack_animation",
]
const INTERRUPTING_KINDS: Array[StringName] = [
	&"trade_state", &"trade_completed", &"trade_cancelled",
	&"forced_transfer", &"action_invalidated",
]
const WAKING_KINDS: Array[StringName] = [
	&"player_spawned", &"periodic_review", &"low_health", &"under_attack", &"destination_reached", &"map_transition_result",
	&"combat_result", &"self_repair_stopped", &"objective_changed", &"objective_result",
	&"gather_result", &"inventory_full", &"party_result", &"trade_result", &"action_result", &"action_failed", &"combat_failed",
	&"production_result", &"history_search_result",
]
const COALESCING_KINDS: Array[StringName] = [&"combat_result"]


func classify(event_kind: StringName, waiting := false) -> StringName:
	if event_kind in IGNORED_KINDS:
		return IGNORE
	if (waiting and event_kind != &"under_attack") or event_kind in INTERRUPTING_KINDS:
		return INTERRUPT
	return QUEUE if event_kind in WAKING_KINDS else INBOX


func should_coalesce(event_kind: StringName) -> bool:
	return event_kind in COALESCING_KINDS
