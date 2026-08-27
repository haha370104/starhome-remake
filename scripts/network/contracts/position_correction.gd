class_name PositionCorrection
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")

const REASON_NAVIGATION: StringName = &"navigation"
const REASON_SPEED_LIMIT: StringName = &"speed_limit"
const REASON_MAP_STATE: StringName = &"map_state"
const REASON_SERVER_RECONCILIATION: StringName = &"server_reconciliation"

var authoritative_position: Vector2
var reason: StringName
var acknowledged_input_sequence: int
var server_tick: int


## Initializes a new instance with its required state.
## [param requested_authoritative_position] World-space position used by the operation.
## [param requested_reason] New value requested by the caller.
## [param requested_acknowledged_input_sequence] Sequence, tick, or index value used by the operation.
## [param requested_server_tick] Sequence, tick, or index value used by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func _init(
	requested_authoritative_position: Vector2,
	requested_reason: StringName,
	requested_acknowledged_input_sequence: int,
	requested_server_tick: int,
) -> void:
	authoritative_position = requested_authoritative_position
	reason = requested_reason
	acknowledged_input_sequence = requested_acknowledged_input_sequence
	server_tick = requested_server_tick


## Performs the `supported_reasons` operation.
## Returns the resulting collection.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func supported_reasons() -> Array[StringName]:
	return [REASON_NAVIGATION, REASON_SPEED_LIMIT, REASON_MAP_STATE, REASON_SERVER_RECONCILIATION]


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
		"authoritative_position": Validation.vector2_to_dictionary(authoritative_position),
		"reason": String(reason),
		"acknowledged_input_sequence": acknowledged_input_sequence,
		"server_tick": server_tick,
	}


## Builds a typed value from a serialized dictionary.
## [param raw] Serialized input received at the subsystem boundary.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "position correction")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var position_result = Validation.require_vector2(source, &"authoritative_position")
	if not position_result.is_ok:
		return position_result
	var reason_result = Validation.require_string(source, &"reason", 1, Protocol.MAX_ACTION_LENGTH)
	if not reason_result.is_ok:
		return reason_result
	var parsed_reason := StringName(reason_result.value)
	if parsed_reason not in supported_reasons():
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "Unsupported correction reason")
	var sequence_result = Validation.require_integer(
		source,
		&"acknowledged_input_sequence",
		Protocol.MIN_SEQUENCE,
		Protocol.MAX_SEQUENCE,
	)
	if not sequence_result.is_ok:
		return sequence_result
	var tick_result = Validation.require_integer(source, &"server_tick", 0, Protocol.MAX_SERVER_TICK)
	if not tick_result.is_ok:
		return tick_result
	return Result.ok(load("res://scripts/network/contracts/position_correction.gd").new(
		position_result.value,
		parsed_reason,
		sequence_result.value,
		tick_result.value,
	))
