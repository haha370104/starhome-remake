class_name ClientMultiplayerSession
extends Node

const EntitySnapshotContract := preload("res://scripts/network/contracts/entity_snapshot.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const MapTransitionIntentContract := preload("res://scripts/network/contracts/map_transition_intent.gd")
const NetworkErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")

signal connection_state_changed(state: ClientNetworkAdapter.ConnectionState)
signal connection_failed(message: String)
signal command_rejected(code: StringName, message: String)
signal local_presentation_state_changed(state: Dictionary)
signal remote_presentation_state_changed(entity_id: StringName, state: Dictionary)
signal remote_entity_removed(entity_id: StringName)
signal movement_intent_created(payload: Dictionary)
signal map_change_requested(transition_id: StringName, transition_sequence: int)
signal map_joined(
	map_id: StringName,
	map_instance_id: String,
	spawn_position: Vector2,
	definition_version: int,
)
signal map_change_failed(transition_id: StringName, code: StringName, message: String)
signal combat_snapshot_received(snapshot: Dictionary)
signal combat_event_received(event: Dictionary)

@export var offline_debug_enabled := false
@export var local_entity_id: StringName = &"player.local"
@export var current_map_id: StringName = &""
@export var current_map_instance_id := ""

var network_adapter: ClientNetworkAdapter
var local_predictor := LocalMovementPredictor.new()
var remote_interpolator := RemoteEntityInterpolator.new()
var _known_remote_entity_ids: Dictionary = {}
var _next_transition_sequence := 1
var _pending_map_change: Dictionary = {}
var _minimum_snapshot_server_tick := -1
var _suppress_local_presentation_signal := false
var _next_ability_sequence := 1


## Initializes node dependencies after the node enters the scene tree.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _ready() -> void:
	network_adapter = ClientNetworkAdapter.new()
	add_child(network_adapter)
	network_adapter.connection_state_changed.connect(_on_connection_state_changed)
	network_adapter.connection_failed.connect(connection_failed.emit)
	network_adapter.command_rejected.connect(_on_command_rejected)
	network_adapter.server_message_received.connect(_on_server_message_received)
	network_adapter.session_opened.connect(_on_session_opened)
	network_adapter.map_joined_received.connect(_on_map_joined_received)
	network_adapter.authoritative_snapshot_received.connect(_on_world_snapshot)
	local_predictor.presentation_state_changed.connect(_on_local_predictor_presentation_changed)
	local_predictor.move_intent_created.connect(_on_move_intent_created)
	remote_interpolator.presentation_state_changed.connect(remote_presentation_state_changed.emit)
	network_adapter.configure_offline_debug(offline_debug_enabled)


## Advances frame-based presentation state.
## [param delta] Elapsed time in seconds for this update.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _process(delta: float) -> void:
	local_predictor.advance(delta)
	remote_interpolator.advance(delta)


## Processes the requested protocol or gameplay operation.
## [param host] Input value consumed by the operation.
## [param port] Input value consumed by the operation.
## Returns A Godot error code describing the operation result.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func connect_to_server(host: String, port: int = ClientNetworkAdapter.DEFAULT_PORT) -> Error:
	return network_adapter.connect_to_server(host, port)


## Processes the requested protocol or gameplay operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func disconnect_from_server() -> void:
	network_adapter.disconnect_from_server()
	_clear_remote_entities()


## Initializes the subsystem and returns its startup result.
## [param position] World-space position used by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func initialize_local_player(position: Vector2) -> void:
	local_predictor.reset(position)


## Configures the instance from validated runtime inputs.
## [param map_instance_id] Stable identifier of the target value.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func configure_map_instance(map_instance_id: String) -> void:
	current_map_instance_id = map_instance_id


## Performs the `request_move` operation.
## [param requested_world_point] World-space position used by the operation.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func request_move(requested_world_point: Vector2) -> Dictionary:
	if current_map_instance_id.is_empty() or not _pending_map_change.is_empty():
		return {}
	return local_predictor.create_move_intent(current_map_instance_id, requested_world_point)


## Submits [param target_entity_id] for [param ability_id] using a monotonic client command sequence.
## [param ability_id] Equipped ability identifier; no damage or energy fields are accepted.
## [param target_entity_id] Monster identity selected from the latest authority snapshot.
## Returns the strict payload, or an empty dictionary when transport/map state is unavailable.
func request_use_ability(ability_id: String, target_entity_id: String) -> Dictionary:
	if current_map_instance_id.is_empty() or ability_id.is_empty() or target_entity_id.is_empty():
		return {}
	var contract := UseAbilityIntentContract.new(
		current_map_instance_id, ability_id, target_entity_id, _next_ability_sequence
	)
	var validation = contract.validate()
	if not validation.is_ok:
		return {}
	var payload: Dictionary = contract.to_dictionary()
	if network_adapter.send_use_ability_intent(payload) != OK:
		return {}
	_next_ability_sequence += 1
	return payload


## Requests the server-owned transition identified by [param transition_id] and its declared [param destination_entry_number].
## [param transition_id] Business exit identifier selected from the current map definition.
## [param destination_entry_number] Destination entrance number declared by that exit, never a map or position.
## Returns the validated wire payload, or an empty dictionary if another transfer is pending or submission fails.
## Design: Only one transfer may be pending; all current-map state remains observable until a matching `map_joined` arrives.
func request_map_change(
	transition_id: StringName,
	destination_entry_number: int = 0,
) -> Dictionary:
	if current_map_instance_id.is_empty() or transition_id.is_empty():
		return {}
	if not _pending_map_change.is_empty():
		return {}
	if network_adapter == null \
		or network_adapter.connection_state != ClientNetworkAdapter.ConnectionState.CONNECTED:
		return {}
	var contract := MapTransitionIntentContract.new(
		current_map_instance_id,
		String(transition_id),
		destination_entry_number,
		_next_transition_sequence,
	)
	var validation = contract.validate()
	if not validation.is_ok:
		return {}
	var payload: Dictionary = contract.to_dictionary()
	_pending_map_change = payload.duplicate(true)
	_next_transition_sequence += 1
	map_change_requested.emit(transition_id, int(payload["input_sequence"]))
	var send_error := network_adapter.send_map_transition_intent(payload)
	if send_error != OK:
		_fail_pending_map_change(
			&"network.transport_unavailable",
			"Unable to submit map transition: %s" % error_string(send_error),
		)
		return {}
	return payload


## Reports whether a map-transfer command is waiting for a matching server result.
## Returns `true` between a successful local submission and its authoritative join or correlated rejection.
func is_map_change_pending() -> bool:
	return not _pending_map_change.is_empty()


## Performs the `record_local_predicted_delta` operation.
## [param input_sequence] Sequence, tick, or index value used by the operation.
## [param displacement] Input value consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func record_local_predicted_delta(input_sequence: int, displacement: Vector2) -> bool:
	return local_predictor.apply_predicted_delta(input_sequence, displacement)


## Performs the `local_presentation_state` operation.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func local_presentation_state() -> Dictionary:
	return local_predictor.presentation_state()


## Performs the `remote_presentation_states` operation.
## Returns Structured result data produced by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func remote_presentation_states() -> Dictionary:
	return remote_interpolator.presentation_states()


## Performs the `inject_offline_snapshot` operation.
## [param snapshot] Serialized input received at the subsystem boundary.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func inject_offline_snapshot(snapshot: Dictionary) -> void:
	network_adapter.inject_authoritative_snapshot(snapshot)


## Handles the signal callback for `on_move_intent_created`.
## [param payload] Serialized input received at the subsystem boundary.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _on_move_intent_created(payload: Dictionary) -> void:
	movement_intent_created.emit(payload.duplicate(true))
	network_adapter.send_move_intent(payload)


## Handles the signal callback for `on_world_snapshot`.
## [param snapshot] Serialized input received at the subsystem boundary.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _on_world_snapshot(snapshot: Dictionary) -> void:
	var server_tick := int(snapshot.get("server_tick", -1))
	if server_tick < _minimum_snapshot_server_tick:
		return
	var server_time := float(snapshot.get("server_time_seconds", 0.0))
	var entities: Array = snapshot.get("entities", [])
	var remote_entities: Array = []
	for raw_entity in entities:
		var entity_result = EntitySnapshotContract.from_dictionary(raw_entity)
		if not entity_result.is_ok:
			continue
		var entity = entity_result.value
		if entity.server_tick != server_tick:
			continue
		var entity_id := StringName(entity.entity_id)
		if entity_id == local_entity_id:
			local_predictor.apply_authoritative_snapshot(
				server_tick,
				entity.acknowledged_input_sequence,
				entity.position,
			)
		else:
			remote_entities.append(entity.to_dictionary())
	if not remote_interpolator.push_snapshot(server_tick, server_time, remote_entities):
		return
	var current_remote_entity_ids: Dictionary = {}
	for remote_entity in remote_entities:
		current_remote_entity_ids[StringName(remote_entity["entity_id"])] = true
	for known_entity_id in _known_remote_entity_ids:
		if current_remote_entity_ids.has(known_entity_id):
			continue
		remote_interpolator.remove_entity(known_entity_id)
		remote_entity_removed.emit(known_entity_id)
	_known_remote_entity_ids = current_remote_entity_ids
	var combat_value: Variant = snapshot.get("combat")
	if combat_value is Dictionary and _is_valid_combat_snapshot(combat_value):
		combat_snapshot_received.emit((combat_value as Dictionary).duplicate(true))


## Adopts the authoritative identity/map assigned by a successful network handshake.
## [param result] Successful serialized result carried by the session-opened envelope.
## Design: Local identity is server-assigned; exported defaults are only offline-debug conveniences.
func _on_session_opened(result: Dictionary) -> void:
	var value: Dictionary = result.get("value", {})
	if not _commit_map_joined(value, false):
		connection_failed.emit("Server handshake contained an invalid initial map join")
		network_adapter.disconnect_from_server()


## Applies an authoritative explicit map-transfer result from the reliable control channel.
## [param result] Successful wire result containing `map_joined`, an initial snapshot and transition sequence.
## Design: A mismatched or malformed response cannot mutate the old-map session state.
func _on_map_joined_received(result: Dictionary) -> void:
	var value: Dictionary = result.get("value", {})
	if _pending_map_change.is_empty():
		return
	if int(value.get("transition_sequence", -1)) != int(_pending_map_change["input_sequence"]):
		return
	_commit_map_joined(value, true)


## Validates and atomically commits the joined map described by [param value].
## [param value] Successful result value containing the strict `MapJoined` contract and optional initial snapshot.
## [param explicit_transition] Whether the commit must complete the currently pending map-change command.
## Returns `true` only after identity, map state, prediction and remote tracks have all been replaced.
## Design: Validation completes before any mutable field changes, preserving the previous map on malformed success responses.
func _commit_map_joined(value: Dictionary, explicit_transition: bool) -> bool:
	var joined_result = MapJoinedContract.from_dictionary(value.get("map_joined", {}))
	if not joined_result.is_ok:
		_fail_pending_map_change(joined_result.error_code, joined_result.error_message)
		return false
	var joined = joined_result.value
	if explicit_transition and StringName(joined.entity_id) != local_entity_id:
		_fail_pending_map_change(
			NetworkErrorCodes.INVALID_IDENTIFIER,
			"Map join changed the server-assigned local entity identity",
		)
		return false
	var snapshot_value: Variant = value.get("snapshot")
	if not snapshot_value is Dictionary:
		_fail_pending_map_change(
			NetworkErrorCodes.INVALID_PAYLOAD,
			"Map join did not include a target-map snapshot",
		)
		return false
	var snapshot: Dictionary = snapshot_value
	if (
		typeof(snapshot.get("server_tick")) != TYPE_INT
		or int(snapshot["server_tick"]) != joined.server_tick
		or not snapshot.get("entities") is Array
	):
		_fail_pending_map_change(
			NetworkErrorCodes.INVALID_PAYLOAD,
			"Map join snapshot does not match the authoritative join tick",
		)
		return false
	snapshot = snapshot.duplicate(true)

	_suppress_local_presentation_signal = true
	local_entity_id = StringName(joined.entity_id)
	current_map_id = StringName(joined.map_id)
	current_map_instance_id = joined.map_instance_id
	network_adapter.entity_id = joined.entity_id
	network_adapter.map_id = joined.map_id
	network_adapter.map_instance_id = joined.map_instance_id
	_minimum_snapshot_server_tick = joined.server_tick
	local_predictor.reset(joined.spawn_position, 1, false)
	_clear_remote_entities()
	remote_interpolator.reset()
	_pending_map_change.clear()
	_on_world_snapshot(snapshot)
	_suppress_local_presentation_signal = false
	map_joined.emit(
		current_map_id,
		current_map_instance_id,
		joined.spawn_position,
		joined.definition_version,
	)
	local_presentation_state_changed.emit(local_predictor.presentation_state())
	return true


## Publishes predictor [param state] unless a map-join transaction is still replacing session state.
## [param state] Current local prediction and correction projection.
## Design: Suppression prevents observers from seeing a new-map spawn while session identity still names the old map.
func _on_local_predictor_presentation_changed(state: Dictionary) -> void:
	if _suppress_local_presentation_signal:
		return
	local_presentation_state_changed.emit(state.duplicate(true))


## Forwards [param code]/[param message] and correlates typed transition rejections with the pending sequence.
## [param code] Stable server rejection code.
## [param message] Human-readable server rejection detail.
## Design: Movement or context-free rejections never cancel a concurrently pending map transfer.
func _on_command_rejected(code: StringName, message: String) -> void:
	command_rejected.emit(code, message)
	# The adapter's compact signal intentionally excludes protocol context. Inspect the last
	# reliable envelope so map-change completion still requires an exact command/sequence match.
	# Context-aware handling is performed in `_on_server_message_received`.


## Correlates a reliable server [param message] with the active map-transfer command.
## [param message] Raw control envelope emitted before adapter-specific projections.
## Design: Correlation uses explicit command type and sequence, never error-code naming conventions.
func _on_server_message_received(message: Dictionary) -> void:
	if StringName(message.get("type", "")) == &"combat_event":
		var combat_result: Dictionary = message.get("result", {})
		if bool(combat_result.get("ok", false)) and combat_result.get("value") is Dictionary:
			combat_event_received.emit((combat_result["value"] as Dictionary).duplicate(true))
		return
	if StringName(message.get("type", "")) != &"command_rejected":
		return
	if _pending_map_change.is_empty():
		return
	var result: Dictionary = message.get("result", {})
	var context: Dictionary = result.get("value", {}) if result.get("value") is Dictionary else {}
	if StringName(context.get("command_type", "")) != Protocol.MAP_TRANSITION_INTENT:
		return
	if int(context.get("transition_sequence", -1)) != int(_pending_map_change["input_sequence"]):
		return
	_fail_pending_map_change(
		StringName(result.get("code", NetworkErrorCodes.INVALID_PAYLOAD)),
		String(result.get("message", "Server rejected the map transition")),
	)


## Validates the untrusted [param snapshot] minimum combat schema before presentation signals.
## [param snapshot] Map-scoped combat document received from transport.
## Returns true only when local resources and every monster expose correctly typed public fields.
## Design: Resource paths never arrive over the network; snapshots reference only committed business actor IDs.
func _is_valid_combat_snapshot(snapshot: Dictionary) -> bool:
	if typeof(snapshot.get("server_tick")) != TYPE_INT:
		return false
	if not snapshot.get("local_vehicle") is Dictionary or not snapshot.get("monsters") is Array:
		return false
	for raw_monster: Variant in snapshot["monsters"]:
		if not raw_monster is Dictionary:
			return false
		var monster: Dictionary = raw_monster
		if typeof(monster.get("entity_id")) != TYPE_STRING \
			or typeof(monster.get("species_id")) != TYPE_STRING \
			or typeof(monster.get("combat_actor_id")) != TYPE_STRING \
			or typeof(monster.get("position")) != TYPE_ARRAY \
			or (monster["position"] as Array).size() != 2 \
			or typeof(monster.get("health")) != TYPE_INT \
			or typeof(monster.get("max_health")) != TYPE_INT \
			or typeof(monster.get("alive")) != TYPE_BOOL:
			return false
	return true


## Ends the current pending transfer with [param code] and [param message] while retaining old-map state.
## [param code] Stable protocol or authoritative-domain failure code.
## [param message] Human-readable failure detail for temporary scene feedback.
## Design: Failure clears only the command latch; map identity, prediction and remote tracks remain untouched.
func _fail_pending_map_change(code: StringName, message: String) -> void:
	if _pending_map_change.is_empty():
		return
	var transition_id := StringName(_pending_map_change.get("transition_id", ""))
	_pending_map_change.clear()
	map_change_failed.emit(transition_id, code, message)


## 转发网络连接状态，并在连接关闭后清理所有远端表现实体。
## [param state] 客户端网络适配器报告的最新连接状态。
## Design: 会话层拥有远端实体生命周期，表现层无需理解传输断开细节。
func _on_connection_state_changed(state: ClientNetworkAdapter.ConnectionState) -> void:
	connection_state_changed.emit(state)
	if state == ClientNetworkAdapter.ConnectionState.DISCONNECTED:
		if not _pending_map_change.is_empty():
			_fail_pending_map_change(&"network.disconnected", "Disconnected during map transition")
		_clear_remote_entities()


## 清空插值器中的远端轨迹，并为每个已知实体发布一次移除事件。
## Design: 快照差分与断线清理由会话层统一收口，避免场景遗留幽灵角色。
func _clear_remote_entities() -> void:
	for entity_id in _known_remote_entity_ids:
		remote_interpolator.remove_entity(entity_id)
		remote_entity_removed.emit(entity_id)
	_known_remote_entity_ids.clear()
