class_name LocalMovementPredictor
extends RefCounted

const MoveIntentContract = preload("res://scripts/network/contracts/move_intent.gd")

signal move_intent_created(payload: Dictionary)
signal presentation_state_changed(state: Dictionary)
signal correction_started(mode: StringName, error_distance: float)
signal correction_finished(mode: StringName)
signal stale_snapshot_rejected(server_tick: int)

const CORRECTION_NONE: StringName = &"none"
const CORRECTION_SMOOTH: StringName = &"smooth"
const CORRECTION_FORCED: StringName = &"forced"

var smooth_threshold_px := 24.0
var force_threshold_px := 96.0
var smooth_duration_seconds := 0.15

var predicted_position := Vector2.ZERO
var authoritative_position := Vector2.ZERO
var next_input_sequence := 1
var last_acknowledged_sequence := 0
var last_server_tick := -1
var correction_mode: StringName = CORRECTION_NONE

var _pending_intents: Array[Dictionary] = []
var _correction_origin := Vector2.ZERO
var _correction_target := Vector2.ZERO
var _correction_elapsed := 0.0
var _correction_duration := 0.0


## Configures the instance from validated runtime inputs.
## [param smooth_threshold] Input value consumed by the operation.
## [param force_threshold] Input value consumed by the operation.
## [param smooth_duration] Input value consumed by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func configure(
	smooth_threshold: float = 24.0,
	force_threshold: float = 96.0,
	smooth_duration: float = 0.15,
) -> void:
	smooth_threshold_px = maxf(0.0, smooth_threshold)
	force_threshold_px = maxf(smooth_threshold_px, force_threshold)
	smooth_duration_seconds = maxf(0.001, smooth_duration)


## Resets the managed state to its initial value.
## [param position] World-space position used by the operation.
## [param starting_sequence] Sequence, tick, or index value used by the operation.
## [param emit_change] Whether to publish the reset immediately; transactional owners may defer it.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func reset(position: Vector2, starting_sequence: int = 1, emit_change: bool = true) -> void:
	predicted_position = position
	authoritative_position = position
	next_input_sequence = maxi(1, starting_sequence)
	last_acknowledged_sequence = next_input_sequence - 1
	last_server_tick = -1
	_pending_intents.clear()
	_clear_correction()
	if emit_change:
		_emit_presentation_state()


## Builds the requested runtime object from configuration data.
## [param map_instance_id] Stable identifier of the target value.
## [param requested_world_point] World-space position used by the operation.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func create_move_intent(map_instance_id: String, requested_world_point: Vector2) -> Dictionary:
	var sequence := next_input_sequence
	next_input_sequence += 1
	var intent: Dictionary = {
		"input_sequence": sequence,
		"map_instance_id": map_instance_id,
		"requested_world_point": requested_world_point,
		"predicted_delta": Vector2.ZERO,
	}
	_pending_intents.append(intent)
	var payload := _intent_payload(intent)
	move_intent_created.emit(payload.duplicate(true))
	return payload


## Advances the managed state using the supplied update.
## [param input_sequence] Sequence, tick, or index value used by the operation.
## [param displacement] Input value consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func apply_predicted_delta(input_sequence: int, displacement: Vector2) -> bool:
	for index in range(_pending_intents.size() - 1, -1, -1):
		var intent := _pending_intents[index]
		if int(intent["input_sequence"]) != input_sequence:
			continue
		intent["predicted_delta"] = Vector2(intent["predicted_delta"]) + displacement
		_pending_intents[index] = intent
		predicted_position += displacement
		if correction_mode == CORRECTION_SMOOTH:
			# New prediction continues while reconciliation is blending; move both ends
			# of the correction so fresh input does not resurrect the old error.
			_correction_origin += displacement
			_correction_target += displacement
		_emit_presentation_state()
		return true
	return false


## Advances the managed state using the supplied update.
## [param server_tick] Sequence, tick, or index value used by the operation.
## [param acknowledged_input_sequence] Latest client input sequence incorporated by the server.
## [param server_position] World-space position used by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func apply_authoritative_snapshot(
	server_tick: int,
	acknowledged_input_sequence: int,
	server_position: Vector2,
) -> bool:
	if server_tick <= last_server_tick:
		stale_snapshot_rejected.emit(server_tick)
		return false
	last_server_tick = server_tick
	authoritative_position = server_position
	last_acknowledged_sequence = maxi(last_acknowledged_sequence, acknowledged_input_sequence)
	_discard_acknowledged_intents(last_acknowledged_sequence)

	var reconciliation_target := authoritative_position
	for intent in _pending_intents:
		reconciliation_target += Vector2(intent["predicted_delta"])
	var error_distance := predicted_position.distance_to(reconciliation_target)
	if error_distance <= 0.001:
		predicted_position = reconciliation_target
		_clear_correction()
		_emit_presentation_state()
		return true
	if error_distance >= force_threshold_px:
		correction_mode = CORRECTION_FORCED
		correction_started.emit(correction_mode, error_distance)
		predicted_position = reconciliation_target
		_emit_presentation_state()
		correction_finished.emit(correction_mode)
		_clear_correction()
		return true

	correction_mode = CORRECTION_SMOOTH
	_correction_origin = predicted_position
	_correction_target = reconciliation_target
	_correction_elapsed = 0.0
	# Tiny errors use the full blend window. Larger-but-not-forced errors converge sooner.
	var threshold_span := maxf(0.001, force_threshold_px - smooth_threshold_px)
	var normalized_error := clampf(
		(error_distance - smooth_threshold_px) / threshold_span,
		0.0,
		1.0,
	)
	_correction_duration = lerpf(smooth_duration_seconds, 0.04, normalized_error)
	correction_started.emit(correction_mode, error_distance)
	return true


## Advances the managed state using the supplied update.
## [param delta] Elapsed time in seconds for this update.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func advance(delta: float) -> void:
	if correction_mode != CORRECTION_SMOOTH:
		return
	_correction_elapsed += maxf(0.0, delta)
	var weight := clampf(_correction_elapsed / _correction_duration, 0.0, 1.0)
	predicted_position = _correction_origin.lerp(_correction_target, weight)
	_emit_presentation_state()
	if weight >= 1.0:
		correction_finished.emit(correction_mode)
		_clear_correction()


## Performs the `pending_intent_count` operation.
## Returns the computed integer value.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func pending_intent_count() -> int:
	return _pending_intents.size()


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func presentation_state() -> Dictionary:
	return {
		"position": predicted_position,
		"authoritative_position": authoritative_position,
		"correction_mode": correction_mode,
		"last_server_tick": last_server_tick,
		"last_acknowledged_sequence": last_acknowledged_sequence,
		"pending_intent_count": _pending_intents.size(),
	}


## Performs the `discard_acknowledged_intents` operation.
## [param ack_sequence] Sequence, tick, or index value used by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _discard_acknowledged_intents(ack_sequence: int) -> void:
	var remaining: Array[Dictionary] = []
	for intent in _pending_intents:
		if int(intent["input_sequence"]) > ack_sequence:
			remaining.append(intent)
	_pending_intents = remaining


## Performs the `intent_payload` operation.
## [param intent] Serialized input received at the subsystem boundary.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _intent_payload(intent: Dictionary) -> Dictionary:
	var contract := MoveIntentContract.new(
		String(intent["map_instance_id"]),
		Vector2(intent["requested_world_point"]),
		int(intent["input_sequence"]),
	)
	return contract.to_dictionary()


## Publishes the current state to subscribed consumers.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _emit_presentation_state() -> void:
	presentation_state_changed.emit(presentation_state())


## Resets the managed state to its initial value.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _clear_correction() -> void:
	correction_mode = CORRECTION_NONE
	_correction_elapsed = 0.0
	_correction_duration = 0.0
