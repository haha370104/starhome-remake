class_name SequenceGate
extends RefCounted

const ErrorCodes = preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol = preload("res://scripts/network/contracts/network_protocol.gd")
const Result = preload("res://scripts/core/domain_result.gd")

var _last_accepted_by_stream: Dictionary = {}


## Performs the `accept` operation.
## [param stream_id] Stable identifier of the target value.
## [param sequence] Sequence, tick, or index value used by the operation.
## Returns the result produced by the operation.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func accept(stream_id: StringName, sequence: int):
	if stream_id.is_empty():
		return Result.failure(ErrorCodes.INVALID_IDENTIFIER, "Sequence stream ID cannot be empty")
	if sequence < Protocol.MIN_SEQUENCE or sequence > Protocol.MAX_SEQUENCE:
		return Result.failure(ErrorCodes.VALUE_OUT_OF_RANGE, "Sequence is out of range")
	if not would_accept(stream_id, sequence):
		return Result.failure(
			ErrorCodes.STALE_SEQUENCE,
			"Sequence %d is not newer than %d" % [sequence, last_accepted(stream_id)],
		)
	_last_accepted_by_stream[stream_id] = sequence
	return Result.ok(sequence)


## Reports whether the requested condition is satisfied.
## [param stream_id] Stable identifier of the target value.
## [param sequence] Sequence, tick, or index value used by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func would_accept(stream_id: StringName, sequence: int) -> bool:
	if stream_id.is_empty() or sequence < Protocol.MIN_SEQUENCE or sequence > Protocol.MAX_SEQUENCE:
		return false
	return not _last_accepted_by_stream.has(stream_id) or sequence > int(_last_accepted_by_stream[stream_id])


## Performs the `last_accepted` operation.
## [param stream_id] Stable identifier of the target value.
## Returns the computed integer value.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func last_accepted(stream_id: StringName) -> int:
	return int(_last_accepted_by_stream.get(stream_id, -1))


## Resets the managed state to its initial value.
## [param stream_id] Stable identifier of the target value.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func reset(stream_id: StringName) -> void:
	_last_accepted_by_stream.erase(stream_id)


## Resets the managed state to its initial value.
## Design: Defines or validates data at the network trust boundary before domain code consumes it.
func reset_all() -> void:
	_last_accepted_by_stream.clear()
