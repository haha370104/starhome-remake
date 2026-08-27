class_name ClientNetworkAdapter
extends Node

signal connection_state_changed(state: ConnectionState)
signal connection_failed(message: String)
signal move_intent_sent(payload: Dictionary)
signal map_transition_intent_sent(payload: Dictionary)
signal use_ability_intent_sent(payload: Dictionary)
signal authoritative_snapshot_received(snapshot: Dictionary)
signal remote_snapshot_received(snapshot: Dictionary)
signal server_message_received(message: Dictionary)
signal session_opened(result: Dictionary)
signal map_joined_received(result: Dictionary)
signal command_rejected(code: StringName, message: String)

enum ConnectionState {
	DISCONNECTED,
	CONNECTING,
	CONNECTED,
}

const DEFAULT_PORT := 24680
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const TransportEndpointScript := preload("res://scripts/network/transport/network_transport_endpoint.gd")

var offline_debug_enabled := false
var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var session_ready := false
var reconnect_token := ""
var entity_id := ""
var map_id := ""
var map_instance_id := ""
var _transport_endpoint: NetworkTransportEndpoint


## Initializes node dependencies after the node enters the scene tree.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _ready() -> void:
	# Real-network lifecycle signals are bound through the stable transport endpoint on demand.
	pass


## Configures the instance from validated runtime inputs.
## [param enabled] Whether the corresponding behavior is enabled.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func configure_offline_debug(enabled: bool) -> void:
	offline_debug_enabled = enabled
	if enabled:
		_set_connection_state(ConnectionState.CONNECTED)
	elif multiplayer.multiplayer_peer == null:
		_set_connection_state(ConnectionState.DISCONNECTED)


## Processes the requested protocol or gameplay operation.
## [param host] Input value consumed by the operation.
## [param port] Input value consumed by the operation.
## Returns A Godot error code describing the operation result.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func connect_to_server(host: String, port: int = DEFAULT_PORT) -> Error:
	if offline_debug_enabled:
		_set_connection_state(ConnectionState.CONNECTED)
		return OK
	if host.strip_edges().is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER

	_ensure_transport_endpoint()
	var error := _transport_endpoint.connect_client(host, port)
	if error != OK:
		connection_failed.emit(error_string(error))
		return error
	_set_connection_state(ConnectionState.CONNECTING)
	return OK


## Processes the requested protocol or gameplay operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func disconnect_from_server() -> void:
	# Offline adapters deliberately have no MultiplayerAPI peer.
	if not offline_debug_enabled and _transport_endpoint != null:
		_transport_endpoint.close()
	session_ready = false
	_set_connection_state(ConnectionState.DISCONNECTED)


## Processes the requested protocol or gameplay operation.
## [param payload] Serialized input received at the subsystem boundary.
## Returns A Godot error code describing the operation result.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func send_move_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	move_intent_sent.emit(payload.duplicate(true))
	if offline_debug_enabled:
		return OK
	_transport_endpoint.send_move_intent(payload)
	return OK


## Sends one validated map-transition [param payload] through the reliable command channel.
## [param payload] Current map instance, transition ID, destination entry number and command sequence.
## Returns `OK` after local observation/transport submission, or `ERR_UNCONFIGURED` while disconnected.
## Design: This adapter transports the intent verbatim; destination map and spawn authority stay on the server.
func send_map_transition_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	map_transition_intent_sent.emit(payload.duplicate(true))
	if offline_debug_enabled:
		return OK
	_transport_endpoint.send_map_transition_intent(payload)
	return OK


## 将一个 [param payload] 技能意图交给可靠网络通道。
## [param payload] 当前地图、技能、目标实体和命令序号。
## Returns 已连接或离线调试时返回 `OK`，否则返回 `ERR_UNCONFIGURED`。
## Design: 适配器只传输意图；客户端不能通过该接口提交伤害、命中、能耗或冷却。
func send_use_ability_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	use_ability_intent_sent.emit(payload.duplicate(true))
	if offline_debug_enabled:
		return OK
	_transport_endpoint.send_use_ability_intent(payload)
	return OK


## Performs the `inject_authoritative_snapshot` operation.
## [param snapshot] Serialized input received at the subsystem boundary.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func inject_authoritative_snapshot(snapshot: Dictionary) -> void:
	if offline_debug_enabled:
		authoritative_snapshot_received.emit(snapshot.duplicate(true))


## Performs the `inject_remote_snapshot` operation.
## [param snapshot] Serialized input received at the subsystem boundary.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func inject_remote_snapshot(snapshot: Dictionary) -> void:
	if offline_debug_enabled:
		remote_snapshot_received.emit(snapshot.duplicate(true))


## Routes reliable server control messages into client session state and public signals.
## [param message] Server envelope containing a message type and serialized result.
## Design: Reliable control traffic is separated from high-frequency world snapshots.
func receive_server_message(message: Dictionary) -> void:
	var safe_message := message.duplicate(true)
	var message_type := StringName(safe_message.get("type", ""))
	var result: Dictionary = safe_message.get("result", {})
	if message_type == &"session_opened" and bool(result.get("ok", false)):
		_apply_session_opened(result)
		server_message_received.emit(safe_message)
		return
	if message_type == Protocol.MAP_JOINED and bool(result.get("ok", false)):
		map_joined_received.emit(result.duplicate(true))
		server_message_received.emit(safe_message)
		return
	if message_type == &"command_rejected":
		command_rejected.emit(
			StringName(result.get("code", "unknown")),
			String(result.get("message", "Server rejected the command")),
		)
	server_message_received.emit(safe_message)


## Processes the requested protocol or gameplay operation.
## [param snapshot] Serialized input received at the subsystem boundary.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func receive_world_snapshot(snapshot: Dictionary) -> void:
	authoritative_snapshot_received.emit(snapshot.duplicate(true))
	remote_snapshot_received.emit(snapshot.duplicate(true))


## Handles the signal callback for `on_connected_to_server`.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _on_connected_to_server() -> void:
	_set_connection_state(ConnectionState.CONNECTED)
	var request := {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}
	if not reconnect_token.is_empty():
		request["reconnect_token"] = reconnect_token
	_transport_endpoint.request_session(request)


## Handles the signal callback for `on_connection_failed`.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _on_connection_failed() -> void:
	if _transport_endpoint != null:
		_transport_endpoint.close()
	session_ready = false
	_set_connection_state(ConnectionState.DISCONNECTED)
	connection_failed.emit("Unable to connect to the authoritative server")


## Handles the signal callback for `on_server_disconnected`.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _on_server_disconnected() -> void:
	if _transport_endpoint != null:
		_transport_endpoint.close()
	session_ready = false
	_set_connection_state(ConnectionState.DISCONNECTED)


## Updates the managed state with the supplied value.
## [param next_state] Input value consumed by the operation.
## Design: Belongs to the client prediction/presentation boundary and reconciles to server authority.
func _set_connection_state(next_state: ConnectionState) -> void:
	if connection_state == next_state:
		return
	connection_state = next_state
	connection_state_changed.emit(connection_state)


## Installs and binds the process-wide endpoint at the protocol's stable root NodePath.
## Design: All network RPCs use one path independent of the client gameplay scene hierarchy.
func _ensure_transport_endpoint() -> void:
	if _transport_endpoint != null:
		return
	var existing := get_tree().root.get_node_or_null(TransportEndpointScript.ROOT_NODE_NAME)
	if existing != null:
		_transport_endpoint = existing
	else:
		_transport_endpoint = TransportEndpointScript.new()
		_transport_endpoint.name = TransportEndpointScript.ROOT_NODE_NAME
		get_tree().root.add_child(_transport_endpoint)
	_transport_endpoint.connected_to_server.connect(_on_connected_to_server)
	_transport_endpoint.connection_failed.connect(_on_connection_failed)
	_transport_endpoint.server_disconnected.connect(_on_server_disconnected)
	_transport_endpoint.server_message_received.connect(receive_server_message)
	_transport_endpoint.world_snapshot_received.connect(receive_world_snapshot)


## Commits a successful handshake and routes its embedded initial snapshot immediately.
## [param result] Successful serialized server result from a `session_opened` envelope.
## Design: The initial snapshot and assigned identity become visible atomically to higher layers.
func _apply_session_opened(result: Dictionary) -> void:
	var value: Dictionary = result.get("value", {})
	var session: Dictionary = value.get("session", {})
	var map_joined: Dictionary = value.get("map_joined", {})
	reconnect_token = String(session.get("reconnect_token", reconnect_token))
	entity_id = String(map_joined.get("entity_id", session.get("entity_id", "")))
	map_id = String(map_joined.get("map_id", ""))
	map_instance_id = String(map_joined.get("map_instance_id", ""))
	session_ready = not entity_id.is_empty() and not map_instance_id.is_empty()
	session_opened.emit(result.duplicate(true))
	if not session_ready:
		return
	if value.get("snapshot") is Dictionary:
		receive_world_snapshot(value["snapshot"])
