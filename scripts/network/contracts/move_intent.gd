class_name MoveIntent
extends RefCounted

const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_instance_id",
	&"requested_world_point",
	&"input_sequence",
]

var map_instance_id: String
var requested_world_point: Vector2
var input_sequence: int


## Initializes a new instance with its required state.
## [param requested_map_instance_id] Stable identifier of the target value.
## [param world_point] World-space position used by the operation.
## [param requested_input_sequence] Sequence, tick, or index value used by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func _init(requested_map_instance_id: String, world_point: Vector2, requested_input_sequence: int) -> void:
	map_instance_id = requested_map_instance_id
	requested_world_point = world_point
	input_sequence = requested_input_sequence


## Validates the supplied state against the domain invariants.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func validate():
	var result = from_dictionary(to_dictionary())
	return Result.ok(self) if result.is_ok else result


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func to_dictionary() -> Dictionary:
	return {
		"map_instance_id": map_instance_id,
		"requested_world_point": Validation.vector2_to_dictionary(requested_world_point),
		"input_sequence": input_sequence,
	}


## Builds a typed value from a serialized dictionary.
## [param raw] Serialized input received at the subsystem boundary.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "move intent")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(source, ALLOWED_FIELDS, "move intent")
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_instance_id")
	if not map_result.is_ok:
		return map_result
	var point_result = Validation.require_vector2(source, &"requested_world_point")
	if not point_result.is_ok:
		return point_result
	var sequence_result = Validation.require_integer(
		source,
		&"input_sequence",
		Protocol.MIN_SEQUENCE,
		Protocol.MAX_SEQUENCE,
	)
	if not sequence_result.is_ok:
		return sequence_result
	return Result.ok(load("res://scripts/network/contracts/move_intent.gd").new(
		map_result.value,
		point_result.value,
		sequence_result.value,
	))
