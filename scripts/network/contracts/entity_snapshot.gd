class_name EntitySnapshot
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")

var entity_id: String
var server_tick: int
var position: Vector2
var facing_direction: int
var action_id: StringName
var speed: float
var state_revision: int
var acknowledged_input_sequence: int


## Initializes a new instance with its required state.
## [param requested_entity_id] Stable identifier of the target value.
## [param requested_server_tick] Sequence, tick, or index value used by the operation.
## [param requested_position] World-space position used by the operation.
## [param requested_facing_direction] New value requested by the caller.
## [param requested_action_id] Stable identifier of the target value.
## [param requested_speed] New value requested by the caller.
## [param requested_state_revision] New value requested by the caller.
## [param requested_acknowledged_input_sequence] Latest client input sequence incorporated by the server.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func _init(
	requested_entity_id: String,
	requested_server_tick: int,
	requested_position: Vector2,
	requested_facing_direction: int,
	requested_action_id: StringName,
	requested_speed: float,
	requested_state_revision: int,
	requested_acknowledged_input_sequence: int,
) -> void:
	entity_id = requested_entity_id
	server_tick = requested_server_tick
	position = requested_position
	facing_direction = requested_facing_direction
	action_id = requested_action_id
	speed = requested_speed
	state_revision = requested_state_revision
	acknowledged_input_sequence = requested_acknowledged_input_sequence


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
		"entity_id": entity_id,
		"server_tick": server_tick,
		"position": Validation.vector2_to_dictionary(position),
		"facing_direction": facing_direction,
		"action_id": String(action_id),
		"speed": speed,
		"state_revision": state_revision,
		"acknowledged_input_sequence": acknowledged_input_sequence,
	}


## Builds a typed value from a serialized dictionary.
## [param raw] Serialized input received at the subsystem boundary.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "entity snapshot")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	for deprecated_field in [&"direction", &"action", &"ack_input_sequence"]:
		if source.has(deprecated_field):
			return Result.failure(
				ErrorCodes.INVALID_PAYLOAD,
				"Deprecated entity snapshot field is not accepted: %s" % deprecated_field,
			)
	var entity_result = Validation.require_identifier(source, &"entity_id")
	if not entity_result.is_ok:
		return entity_result
	var tick_result = Validation.require_integer(source, &"server_tick", 0, Protocol.MAX_SERVER_TICK)
	if not tick_result.is_ok:
		return tick_result
	var position_result = Validation.require_vector2(source, &"position")
	if not position_result.is_ok:
		return position_result
	var facing_result = Validation.require_integer(source, &"facing_direction", 0, 7)
	if not facing_result.is_ok:
		return facing_result
	var action_result = Validation.require_string(source, &"action_id", 1, Protocol.MAX_ACTION_LENGTH)
	if not action_result.is_ok:
		return action_result
	var speed_result = Validation.require_number(source, &"speed", 0.0, Protocol.MAX_SPEED)
	if not speed_result.is_ok:
		return speed_result
	var revision_result = Validation.require_integer(source, &"state_revision", 0, Protocol.MAX_SEQUENCE)
	if not revision_result.is_ok:
		return revision_result
	var acknowledgement_result = Validation.require_integer(
		source,
		&"acknowledged_input_sequence",
		Protocol.MIN_SEQUENCE,
		Protocol.MAX_SEQUENCE,
	)
	if not acknowledgement_result.is_ok:
		return acknowledgement_result
	return Result.ok(load("res://scripts/network/contracts/entity_snapshot.gd").new(
		entity_result.value,
		tick_result.value,
		position_result.value,
		facing_result.value,
		StringName(action_result.value),
		speed_result.value,
		revision_result.value,
		acknowledgement_result.value,
	))
