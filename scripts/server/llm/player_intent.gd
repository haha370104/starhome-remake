class_name PlayerIntent
extends RefCounted

var actor_id := ""
var intent_kind: StringName = &""
var sequence := 0
var observed_revision := -1
var payload: Dictionary = {}


func _init(
	requested_actor_id: String,
	requested_intent_kind: StringName,
	requested_sequence: int,
	requested_observed_revision: int,
	requested_payload: Dictionary,
) -> void:
	actor_id = requested_actor_id
	intent_kind = requested_intent_kind
	sequence = requested_sequence
	observed_revision = requested_observed_revision
	payload = requested_payload.duplicate(true)


func to_dictionary() -> Dictionary:
	return {
		"actor_id": actor_id,
		"intent_kind": String(intent_kind),
		"sequence": sequence,
		"observed_revision": observed_revision,
		"payload": payload.duplicate(true),
	}
