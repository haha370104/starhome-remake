class_name NetworkTransportEndpoint
extends Node

signal connected_to_server
signal connection_failed
signal server_disconnected
signal peer_disconnected(peer_id: int)
signal session_request_received(peer_id: int, request: Dictionary)
signal move_intent_received(peer_id: int, intent: Dictionary)
signal map_transition_intent_received(peer_id: int, intent: Dictionary)
signal use_ability_intent_received(peer_id: int, intent: Dictionary)
signal server_message_received(message: Dictionary)
signal world_snapshot_received(snapshot: Dictionary)

const ROOT_NODE_NAME := "StarhomeNetworkTransport"
const SERVER_PEER_ID := 1
const CHANNEL_COUNT := 3


## Connects MultiplayerAPI lifecycle events to transport-level signals.
## Design: Every executable installs this node at the fixed `/root/StarhomeNetworkTransport` path.
func _ready() -> void:
	if not multiplayer.connected_to_server.is_connected(connected_to_server.emit):
		multiplayer.connected_to_server.connect(connected_to_server.emit)
	if not multiplayer.connection_failed.is_connected(connection_failed.emit):
		multiplayer.connection_failed.connect(connection_failed.emit)
	if not multiplayer.server_disconnected.is_connected(server_disconnected.emit):
		multiplayer.server_disconnected.connect(server_disconnected.emit)
	if not multiplayer.peer_disconnected.is_connected(peer_disconnected.emit):
		multiplayer.peer_disconnected.connect(peer_disconnected.emit)


## Starts an ENet authority on [param listen_address]/[param port] for [param max_clients] peers.
## [param listen_address] Local interface address or `*` wildcard to bind.
## [param port] UDP listen port shared by the server configuration and client default.
## [param max_clients] Maximum simultaneously connected remote peers.
## Returns A Godot error code from ENet peer creation.
func start_server(listen_address: String, port: int, max_clients: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(listen_address)
	var error := peer.create_server(port, max_clients, CHANNEL_COUNT)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


## Starts an ENet connection to [param host] and [param port].
## [param host] DNS name or IP address of the authoritative server.
## [param port] UDP port exposed by the authoritative server.
## Returns A Godot error code from ENet peer creation.
func connect_client(host: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host, port, CHANNEL_COUNT)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


## Closes the active peer while preserving the endpoint and its stable RPC path.
func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## Sends a versioned [param request] to open or resume a server session.
## [param request] Protocol/content versions plus an optional reconnect token.
func request_session(request: Dictionary) -> void:
	rpc_open_session.rpc_id(SERVER_PEER_ID, request)


## Sends one client movement [param intent] to server authority.
## [param intent] Untrusted movement payload validated by the authoritative server.
func send_move_intent(intent: Dictionary) -> void:
	rpc_submit_move_intent.rpc_id(SERVER_PEER_ID, intent)


## Sends one reliable map-transition [param intent] to server authority.
## [param intent] Current instance, transition ID, destination entry number, and command sequence.
## Design: Destination map and landing coordinates are resolved exclusively by the server.
func send_map_transition_intent(intent: Dictionary) -> void:
	rpc_submit_map_transition_intent.rpc_id(SERVER_PEER_ID, intent)


## 通过可靠命令通道发送一个 [param intent] 技能使用意图。
## [param intent] 当前地图、技能、目标实体和命令序号，不包含任何战斗结算数值。
## Design: 技能命令与移动快照分离；命中、能耗与伤害仍由服务端领域层裁决。
func send_use_ability_intent(intent: Dictionary) -> void:
	rpc_submit_use_ability_intent.rpc_id(SERVER_PEER_ID, intent)


## Sends one reliable control [param message] to [param peer_id].
## [param peer_id] Destination ENet peer ID.
## [param message] Session or rejection envelope.
func send_server_message(peer_id: int, message: Dictionary) -> void:
	rpc_receive_server_message.rpc_id(peer_id, message)


## Sends one ordered but lossy world [param snapshot] to [param peer_id].
## [param peer_id] Destination ENet peer ID.
## [param snapshot] Complete authoritative world state for one server tick.
func send_world_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	rpc_receive_world_snapshot.rpc_id(peer_id, snapshot)


@rpc("any_peer", "call_remote", "reliable", 0)
## Accepts a remote [param request] and exposes it with the authenticated sender peer ID.
## [param request] Versioned open/resume-session payload.
## Design: The transport never trusts caller-supplied peer IDs; MultiplayerAPI supplies identity.
func rpc_open_session(request: Dictionary) -> void:
	session_request_received.emit(multiplayer.get_remote_sender_id(), request.duplicate(true))


@rpc("any_peer", "call_remote", "reliable", 1)
## Accepts a remote [param intent] and exposes it with the authenticated sender peer ID.
## [param intent] Untrusted movement payload for domain validation.
## Design: Gameplay mutation remains outside this transport-only node.
func rpc_submit_move_intent(intent: Dictionary) -> void:
	move_intent_received.emit(multiplayer.get_remote_sender_id(), intent.duplicate(true))


@rpc("any_peer", "call_remote", "reliable", 1)
## Accepts a remote map-transition [param intent] with its authenticated sender peer ID.
## [param intent] Untrusted transition payload validated by server authority.
## Design: Sharing the reliable command channel preserves ordering without granting client map authority.
func rpc_submit_map_transition_intent(intent: Dictionary) -> void:
	map_transition_intent_received.emit(
		multiplayer.get_remote_sender_id(), intent.duplicate(true)
	)


@rpc("any_peer", "call_remote", "reliable", 1)
## 接收远端 [param intent] 技能命令并绑定 MultiplayerAPI 提供的真实 peer ID。
## [param intent] 交给服务端契约层校验的不可信技能载荷。
## Design: 传输层不解释技能，也不接受载荷中的身份、伤害或命中声明。
func rpc_submit_use_ability_intent(intent: Dictionary) -> void:
	use_ability_intent_received.emit(
		multiplayer.get_remote_sender_id(), intent.duplicate(true)
	)


@rpc("authority", "call_remote", "reliable", 0)
## Receives reliable server [param message] envelopes on clients.
## [param message] Session-opened or command-rejected envelope.
func rpc_receive_server_message(message: Dictionary) -> void:
	server_message_received.emit(message.duplicate(true))


@rpc("authority", "call_remote", "unreliable_ordered", 2)
## Receives ordered authoritative [param snapshot] packets on clients.
## [param snapshot] Complete world snapshot for one server tick.
func rpc_receive_world_snapshot(snapshot: Dictionary) -> void:
	world_snapshot_received.emit(snapshot.duplicate(true))
