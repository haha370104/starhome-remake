class_name MapJoined
extends RefCounted

const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")
const ALLOWED_FIELDS: Array[StringName] = [
	&"map_id",
	&"map_instance_id",
	&"entity_id",
	&"spawn_position",
	&"definition_version",
	&"server_tick",
]

var map_id: String
var map_instance_id: String
var entity_id: String
var spawn_position: Vector2
var definition_version: int
var server_tick: int


## Initializes a new instance with its required state.
## [param requested_map_id] Stable identifier of the target value.
## [param requested_map_instance_id] Stable identifier of the target value.
## [param requested_entity_id] Entity identity retained across the atomic map transfer.
## [param requested_spawn_position] World-space position used by the operation.
## [param requested_definition_version] Configuration data that controls the operation.
## [param requested_server_tick] Sequence, tick, or index value used by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func _init(
	requested_map_id: String,
	requested_map_instance_id: String,
	requested_entity_id: String,
	requested_spawn_position: Vector2,
	requested_definition_version: int,
	requested_server_tick: int,
) -> void:
	map_id = requested_map_id
	map_instance_id = requested_map_instance_id
	entity_id = requested_entity_id
	spawn_position = requested_spawn_position
	definition_version = requested_definition_version
	server_tick = requested_server_tick


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
		"map_id": map_id,
		"map_instance_id": map_instance_id,
		"entity_id": entity_id,
		"spawn_position": Validation.vector2_to_dictionary(spawn_position),
		"definition_version": definition_version,
		"server_tick": server_tick,
	}


## Builds a typed value from a serialized dictionary.
## [param raw] Serialized input received at the subsystem boundary.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "map joined")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var fields_result = Validation.require_only_fields(source, ALLOWED_FIELDS, "map joined")
	if not fields_result.is_ok:
		return fields_result
	var map_result = Validation.require_identifier(source, &"map_id")
	if not map_result.is_ok:
		return map_result
	var instance_result = Validation.require_identifier(source, &"map_instance_id")
	if not instance_result.is_ok:
		return instance_result
	var entity_result = Validation.require_identifier(source, &"entity_id")
	if not entity_result.is_ok:
		return entity_result
	var spawn_result = Validation.require_vector2(source, &"spawn_position")
	if not spawn_result.is_ok:
		return spawn_result
	var version_result = Validation.require_integer(source, &"definition_version", 1, Protocol.MAX_SEQUENCE)
	if not version_result.is_ok:
		return version_result
	var tick_result = Validation.require_integer(source, &"server_tick", 0, Protocol.MAX_SERVER_TICK)
	if not tick_result.is_ok:
		return tick_result
	return Result.ok(load("res://scripts/network/contracts/map_joined.gd").new(
		map_result.value,
		instance_result.value,
		entity_result.value,
		spawn_result.value,
		version_result.value,
		tick_result.value,
	))
