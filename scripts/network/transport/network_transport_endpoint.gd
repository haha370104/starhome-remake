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


## 节点进入场景树后初始化运行依赖。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func _ready() -> void:
	if not multiplayer.connected_to_server.is_connected(connected_to_server.emit):
		multiplayer.connected_to_server.connect(connected_to_server.emit)
	if not multiplayer.connection_failed.is_connected(connection_failed.emit):
		multiplayer.connection_failed.connect(connection_failed.emit)
	if not multiplayer.server_disconnected.is_connected(server_disconnected.emit):
		multiplayer.server_disconnected.connect(server_disconnected.emit)
	if not multiplayer.peer_disconnected.is_connected(peer_disconnected.emit):
		multiplayer.peer_disconnected.connect(peer_disconnected.emit)


## 执行 `start_server` 对应的模块操作。
## [param listen_address] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param port] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param max_clients] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func start_server(listen_address: String, port: int, max_clients: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	peer.set_bind_ip(listen_address)
	var error := peer.create_server(port, max_clients, CHANNEL_COUNT)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


## 执行 `connect_client` 对应的模块操作。
## [param host] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param port] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func connect_client(host: String, port: int) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var error := peer.create_client(host, port, CHANNEL_COUNT)
	if error != OK:
		return error
	peer.get_host().compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


## 执行 `close` 对应的模块操作。
func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## 执行 `request_session` 对应的模块操作。
## [param request] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func request_session(request: Dictionary) -> void:
	rpc_open_session.rpc_id(SERVER_PEER_ID, request)


## 执行 `send_move_intent` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func send_move_intent(intent: Dictionary) -> void:
	rpc_submit_move_intent.rpc_id(SERVER_PEER_ID, intent)


## 执行 `send_map_transition_intent` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func send_map_transition_intent(intent: Dictionary) -> void:
	rpc_submit_map_transition_intent.rpc_id(SERVER_PEER_ID, intent)


## 执行 `send_use_ability_intent` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：技能命令与移动快照分离；命中、能耗与伤害仍由服务端领域层裁决。
func send_use_ability_intent(intent: Dictionary) -> void:
	rpc_submit_use_ability_intent.rpc_id(SERVER_PEER_ID, intent)


## 执行 `send_server_message` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func send_server_message(peer_id: int, message: Dictionary) -> void:
	rpc_receive_server_message.rpc_id(peer_id, message)


## 执行 `send_world_snapshot` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func send_world_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	rpc_receive_world_snapshot.rpc_id(peer_id, snapshot)


@rpc("any_peer", "call_remote", "reliable", 0)
## 执行 `rpc_open_session` 对应的模块操作。
## [param request] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func rpc_open_session(request: Dictionary) -> void:
	session_request_received.emit(multiplayer.get_remote_sender_id(), request.duplicate(true))


@rpc("any_peer", "call_remote", "reliable", 1)
## 执行 `rpc_submit_move_intent` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func rpc_submit_move_intent(intent: Dictionary) -> void:
	move_intent_received.emit(multiplayer.get_remote_sender_id(), intent.duplicate(true))


@rpc("any_peer", "call_remote", "reliable", 1)
## 执行 `rpc_submit_map_transition_intent` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数只处理协议边界，不信任未经校验的外部状态。
func rpc_submit_map_transition_intent(intent: Dictionary) -> void:
	map_transition_intent_received.emit(
		multiplayer.get_remote_sender_id(), intent.duplicate(true)
	)


@rpc("any_peer", "call_remote", "reliable", 1)
## 执行 `rpc_submit_use_ability_intent` 对应的模块操作。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：传输层不解释技能，也不接受载荷中的身份、伤害或命中声明。
func rpc_submit_use_ability_intent(intent: Dictionary) -> void:
	use_ability_intent_received.emit(
		multiplayer.get_remote_sender_id(), intent.duplicate(true)
	)


@rpc("authority", "call_remote", "reliable", 0)
## 执行 `rpc_receive_server_message` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func rpc_receive_server_message(message: Dictionary) -> void:
	server_message_received.emit(message.duplicate(true))


@rpc("authority", "call_remote", "unreliable_ordered", 2)
## 执行 `rpc_receive_world_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func rpc_receive_world_snapshot(snapshot: Dictionary) -> void:
	world_snapshot_received.emit(snapshot.duplicate(true))
