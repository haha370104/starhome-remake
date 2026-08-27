class_name NetworkProtocol
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Result = preload("res://scripts/core/domain_result.gd")

const PROTOCOL_VERSION := 1
const PUBLIC_CONTENT_VERSION := 1
const MIN_SEQUENCE := 0
const MAX_SEQUENCE := 2147483647
const MAX_SERVER_TICK := 9223372036854775807
const MAX_WORLD_COORDINATE := 10000000.0
const MAX_SPEED := 10000.0
const MAX_IDENTIFIER_LENGTH := 128
const MAX_ACTION_LENGTH := 64

const MOVE_INTENT: StringName = &"move_intent"
const MAP_TRANSITION_INTENT: StringName = &"map_transition_intent"
const USE_ABILITY_INTENT: StringName = &"use_ability_intent"
const ENTITY_SNAPSHOT: StringName = &"entity_snapshot"
const MAP_JOINED: StringName = &"map_joined"
const POSITION_CORRECTION: StringName = &"position_correction"


## Performs the `supported_message_types` operation.
## Returns the resulting collection.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func supported_message_types() -> Array[StringName]:
	return [
		MOVE_INTENT,
		MAP_TRANSITION_INTENT,
		USE_ABILITY_INTENT,
		ENTITY_SNAPSHOT,
		MAP_JOINED,
		POSITION_CORRECTION,
	]


## Validates the supplied state against the domain invariants.
## [param protocol_version] Input value consumed by the operation.
## [param content_version] Input value consumed by the operation.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func validate_versions(protocol_version: int, content_version: int):
	if protocol_version != PROTOCOL_VERSION:
		return Result.failure(
			ErrorCodes.UNSUPPORTED_PROTOCOL_VERSION,
			"Unsupported protocol version: %d" % protocol_version,
		)
	if content_version != PUBLIC_CONTENT_VERSION:
		return Result.failure(
			ErrorCodes.CONTENT_VERSION_MISMATCH,
			"Public content version does not match: %d" % content_version,
		)
	return Result.ok()


## Reports whether the requested condition is satisfied.
## [param message_type] Input value consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func is_supported_message_type(message_type: StringName) -> bool:
	return message_type in supported_message_types()
