class_name MessageEnvelope
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")
const Validation = preload("res://scripts/network/contracts/contract_validation.gd")

var protocol_version: int
var content_version: int
var message_type: StringName
var sequence: int
var payload: Dictionary


## Initializes a new instance with its required state.
## [param requested_message_type] New value requested by the caller.
## [param requested_sequence] Sequence, tick, or index value used by the operation.
## [param requested_payload] Serialized input received at the subsystem boundary.
## [param requested_protocol_version] New value requested by the caller.
## [param requested_content_version] New value requested by the caller.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func _init(
	requested_message_type: StringName,
	requested_sequence: int,
	requested_payload: Dictionary,
	requested_protocol_version: int = Protocol.PROTOCOL_VERSION,
	requested_content_version: int = Protocol.PUBLIC_CONTENT_VERSION,
) -> void:
	message_type = requested_message_type
	sequence = requested_sequence
	payload = requested_payload.duplicate(true)
	protocol_version = requested_protocol_version
	content_version = requested_content_version


## Validates the supplied state against the domain invariants.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func validate():
	var version_result = Protocol.validate_versions(protocol_version, content_version)
	if not version_result.is_ok:
		return version_result
	if not Protocol.is_supported_message_type(message_type):
		return Result.failure(ErrorCodes.UNKNOWN_MESSAGE_TYPE, "Unknown message type: %s" % message_type)
	if sequence < Protocol.MIN_SEQUENCE or sequence > Protocol.MAX_SEQUENCE:
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "Envelope sequence is out of range")
	return Result.ok(self)


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func to_dictionary() -> Dictionary:
	return {
		"protocol_version": protocol_version,
		"content_version": content_version,
		"message_type": String(message_type),
		"sequence": sequence,
		"payload": payload.duplicate(true),
	}


## Builds a typed value from a serialized dictionary.
## [param raw] Serialized input received at the subsystem boundary.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
static func from_dictionary(raw: Variant):
	var dictionary_result = Validation.require_dictionary(raw, "message envelope")
	if not dictionary_result.is_ok:
		return dictionary_result
	var source: Dictionary = dictionary_result.value
	var protocol_result = Validation.require_integer(source, &"protocol_version", 0, Protocol.MAX_SEQUENCE)
	if not protocol_result.is_ok:
		return protocol_result
	var content_result = Validation.require_integer(source, &"content_version", 0, Protocol.MAX_SEQUENCE)
	if not content_result.is_ok:
		return content_result
	var type_result = Validation.require_string(source, &"message_type", 1, Protocol.MAX_ACTION_LENGTH)
	if not type_result.is_ok:
		return type_result
	var sequence_result = Validation.require_integer(
		source,
		&"sequence",
		Protocol.MIN_SEQUENCE,
		Protocol.MAX_SEQUENCE,
	)
	if not sequence_result.is_ok:
		return sequence_result
	var payload_result = Validation.require_field(source, &"payload")
	if not payload_result.is_ok:
		return payload_result
	if typeof(payload_result.value) != TYPE_DICTIONARY:
		return Result.failure(ErrorCodes.INVALID_FIELD_TYPE, "payload must be a Dictionary")
	var envelope = load("res://scripts/network/contracts/message_envelope.gd").new(
		StringName(type_result.value),
		sequence_result.value,
		payload_result.value,
		protocol_result.value,
		content_result.value,
	)
	var validation_result = envelope.validate()
	return Result.ok(envelope) if validation_result.is_ok else validation_result
