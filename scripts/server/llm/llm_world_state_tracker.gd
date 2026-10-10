class_name LlmWorldStateTracker
extends RefCounted

const Result = preload("res://scripts/core/domain_result.gd")

var _previous: Dictionary = {}
var _previous_revision := -1


func reset() -> void:
	_previous.clear()
	_previous_revision = -1


func update(observation: PlayerObservation) -> DomainResult:
	if observation == null:
		return Result.failure(&"llm.observation_required", "an observation is required")
	var current := _snapshot(observation)
	var diff := _diff(_previous, current, observation.observation_revision)
	_previous = current
	_previous_revision = observation.observation_revision
	return Result.ok(diff)


func snapshot() -> Dictionary:
	return _previous.duplicate(true)


func _snapshot(observation: PlayerObservation) -> Dictionary:
	return {
		"actor_id": observation.actor_id,
		"map_instance_id": observation.map_instance_id,
		"map_id": observation.map_id,
		"self": observation.self_state.duplicate(true),
		"visible_entities": _index(observation.visible_entities, "entity_id"),
		"available_objectives": _index(observation.available_objectives, "objective_id"),
		"party_state": observation.party_state.duplicate(true),
		"friend_state": observation.friend_state.duplicate(true),
		"trade_state": observation.trade_state.duplicate(true),
		"available_transitions": _index(observation.available_transitions, "transition_id"),
		"recent_events": _index(observation.recent_events, "event_id"),
	}


func _diff(previous: Dictionary, current: Dictionary, revision: int) -> Dictionary:
	var initial := previous.is_empty()
	var result := {
		"kind": "initial" if initial else "delta",
		"map_changed": initial or previous.get("map_instance_id", "") != current.get("map_instance_id", "") \
			or previous.get("map_id", "") != current.get("map_id", ""),
		"self_changed": initial or previous.get("self", {}) != current.get("self", {}),
		"party_changed": initial or previous.get("party_state", {}) != current.get("party_state", {}),
		"friend_changed": initial or previous.get("friend_state", {}) != current.get("friend_state", {}),
		"trade_changed": initial or previous.get("trade_state", {}) != current.get("trade_state", {}),
		"transitions_changed": initial or previous.get("available_transitions", {}) != current.get("available_transitions", {}),
		"entities": _collection_diff(previous.get("visible_entities", {}), current.get("visible_entities", {})),
		"objectives": _collection_diff(previous.get("available_objectives", {}), current.get("available_objectives", {})),
		"transitions": _collection_diff(previous.get("available_transitions", {}), current.get("available_transitions", {})),
		"events": _collection_diff(previous.get("recent_events", {}), current.get("recent_events", {})),
	}
	if result.map_changed:
		result["map"] = {"map_id": current.map_id}
	if result.self_changed:
		result["self"] = current.self.duplicate(true)
	if result.party_changed:
		result["party"] = current.party_state.duplicate(true)
	if result.friend_changed:
		result["friends"] = current.friend_state.duplicate(true)
	if result.trade_changed:
		result["trade"] = current.trade_state.duplicate(true)
	if result.transitions_changed:
		result["available_transitions"] = current.available_transitions.duplicate(true)
	result["has_changes"] = initial or result.map_changed or result.self_changed or result.party_changed \
		or result.friend_changed or result.trade_changed \
		or result.transitions_changed \
		or not result.entities.added.is_empty() or not result.entities.removed.is_empty() \
		or not result.entities.changed.is_empty() or not result.objectives.added.is_empty() \
		or not result.objectives.removed.is_empty() or not result.objectives.changed.is_empty() \
		or not result.transitions.added.is_empty() or not result.transitions.removed.is_empty() \
		or not result.transitions.changed.is_empty() \
		or not result.events.added.is_empty() or not result.events.removed.is_empty() \
		or not result.events.changed.is_empty()
	return result


func _index(entries: Array, key: String) -> Dictionary:
	var result: Dictionary = {}
	for raw_entry: Variant in entries:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		var entry_id := str(entry.get(key, ""))
		if entry_id.is_empty():
			entry_id = JSON.stringify(entry)
		result[entry_id] = entry.duplicate(true)
	return result


func _collection_diff(previous: Dictionary, current: Dictionary) -> Dictionary:
	var added: Array = []
	var removed: Array = []
	var changed: Array = []
	var current_ids: Array[String] = []
	for raw_id: Variant in current.keys():
		current_ids.append(String(raw_id))
	current_ids.sort()
	for entry_id: String in current_ids:
		if not previous.has(entry_id):
			added.append(current[entry_id].duplicate(true))
		elif previous[entry_id] != current[entry_id]:
			changed.append({
				"id": entry_id,
				"before": previous[entry_id].duplicate(true),
				"after": current[entry_id].duplicate(true),
			})
	var previous_ids: Array[String] = []
	for raw_id: Variant in previous.keys():
		previous_ids.append(String(raw_id))
	previous_ids.sort()
	for entry_id: String in previous_ids:
		if not current.has(entry_id):
			removed.append(previous[entry_id].duplicate(true))
	return {"added": added, "removed": removed, "changed": changed}
