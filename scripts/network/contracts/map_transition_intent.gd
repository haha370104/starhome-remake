class_name MapTransitionIntent
extends RefCounted

const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_instance_id",
	&"transition_id",
	&"destination_entry_number",
	&"input_sequence",
]

var map_instance_id: String
var transition_id: String
var destination_entry_number: int
var input_sequence: int


## Initializes a map-transfer request using only identifiers the server can verify.
## [param requested_map_instance_id] Current authoritative map instance observed by the client.
## [param requested_transition_id] Business transition identifier selected by the client.
## [param requested_destination_entry_number] Entry number declared by the selected transition.
## [param requested_input_sequence] Monotonic sequence for the map-transition command stream.
## Design: The client never supplies a destination map or spawn coordinate; both remain server-owned.
func _init(
	requested_map_instance_id: String,
	requested_transition_id: String,
	requested_destination_entry_number: int,
	requested_input_sequence: int,
) -> void:
	map_instance_id = requested_map_instance_id
	transition_id = requested_transition_id
	destination_entry_number = requested_destination_entry_number
	input_sequence = requested_input_sequence


## Validates this typed transition request through the same untrusted wire boundary.
## Returns a successful result containing this instance, or a shared network validation error.
## Design: Constructor use does not bypass the protocol allowlist or range checks.
func validate():
	var result = from_dictionary(to_dictionary())
	return Result.ok(self) if result.is_ok else result


## Serializes the request into its stable transport representation.
## Returns a dictionary containing exactly the four public transition-intent fields.
## Design: Destination map and landing coordinates are intentionally absent authority-owned fields.
func to_dictionary() -> Dictionary:
	return {
		"map_instance_id": map_instance_id,
		"transition_id": transition_id,
		"destination_entry_number": destination_entry_number,
		"input_sequence": input_sequence,
	}


## Builds a typed transition intent from an untrusted [param raw] payload.
## [param raw] Serialized value received at the network boundary.
## Returns a result containing `MapTransitionIntent`, or a stable shared validation error.
## Design: Unknown fields are rejected so clients cannot smuggle destination or spawn authority.
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "map transition intent")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(
		source, ALLOWED_FIELDS, "map transition intent"
	)
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_instance_id")
	if not map_result.is_ok:
		return map_result
	var transition_result = Validation.require_identifier(source, &"transition_id")
	if not transition_result.is_ok:
		return transition_result
	var entry_result = Validation.require_integer(
		source, &"destination_entry_number", 0, Protocol.MAX_SEQUENCE
	)
	if not entry_result.is_ok:
		return entry_result
	var sequence_result = Validation.require_integer(
		source, &"input_sequence", Protocol.MIN_SEQUENCE, Protocol.MAX_SEQUENCE
	)
	if not sequence_result.is_ok:
		return sequence_result
	return Result.ok(load("res://scripts/network/contracts/map_transition_intent.gd").new(
		map_result.value,
		transition_result.value,
		entry_result.value,
		sequence_result.value,
	))
