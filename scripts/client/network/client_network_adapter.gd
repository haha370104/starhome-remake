class_name ClientNetworkAdapter
extends Node

signal connection_state_changed(state: ConnectionState)
signal connection_failed(message: String)
signal move_intent_sent(payload: Dictionary)
signal map_transition_intent_sent(payload: Dictionary)
signal use_ability_intent_sent(payload: Dictionary)
signal vehicle_recovery_intent_sent(payload: Dictionary)
signal pickup_loot_intent_sent(payload: Dictionary)
signal player_panel_command_sent(payload: Dictionary)
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
const InProcessTransportScript := preload(
	"res://scripts/network/transport/in_process_authoritative_transport.gd"
)

var offline_debug_enabled := false
var connection_state: ConnectionState = ConnectionState.DISCONNECTED
var session_ready := false
var reconnect_token := ""
var entity_id := ""
var map_id := ""
var map_instance_id := ""
var _transport_endpoint: Node
var _in_process_server_config
var _in_process_repository


## 节点进入场景树后初始化运行依赖。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _ready() -> void:
	# Real-network lifecycle signals are bound through the stable transport endpoint on demand.
	pass


## 配置并初始化 `configure_offline_debug` 对应的模块状态。
## [param enabled] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func configure_offline_debug(enabled: bool) -> void:
	offline_debug_enabled = enabled
	if connection_state != ConnectionState.DISCONNECTED:
		disconnect_from_server()
	elif not enabled and multiplayer.multiplayer_peer == null:
		_set_connection_state(ConnectionState.DISCONNECTED)


## 在建立进程内连接前注入权威服务器配置和可选仓储。
## [param server_config] 与独立服务器共用的配置对象。
## [param repository] 测试或宿主提供的仓储；为空时使用配置路径。
## 返回当前适配器是否尚未创建传输、可以安全接收配置。
func configure_in_process_server(server_config, repository = null) -> bool:
	if _transport_endpoint != null or server_config == null:
		return false
	_in_process_server_config = server_config
	_in_process_repository = repository
	return true


## 执行 `connect_to_server` 对应的模块操作。
## [param host] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param port] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func connect_to_server(host: String, port: int = DEFAULT_PORT) -> Error:
	if not offline_debug_enabled and (host.strip_edges().is_empty() or port < 1 or port > 65535):
		return ERR_INVALID_PARAMETER

	_ensure_transport_endpoint()
	var error: Error = _transport_endpoint.call("connect_client", host, port)
	if error != OK:
		connection_failed.emit(error_string(error))
		return error
	_set_connection_state(ConnectionState.CONNECTING)
	return OK


## 执行 `disconnect_from_server` 对应的模块操作。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func disconnect_from_server() -> void:
	if _transport_endpoint != null:
		_transport_endpoint.close()
		if _transport_endpoint.get_parent() == self:
			_transport_endpoint.queue_free()
			_transport_endpoint = null
	session_ready = false
	_set_connection_state(ConnectionState.DISCONNECTED)


## 执行 `send_move_intent` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func send_move_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	move_intent_sent.emit(payload.duplicate(true))
	_transport_endpoint.send_move_intent(payload)
	return OK


## 执行 `send_map_transition_intent` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func send_map_transition_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	map_transition_intent_sent.emit(payload.duplicate(true))
	_transport_endpoint.send_map_transition_intent(payload)
	return OK


## 执行 `send_use_ability_intent` 对应的模块操作。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：适配器只传输意图；客户端不能通过该接口提交伤害、命中、能耗或冷却。
func send_use_ability_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	use_ability_intent_sent.emit(payload.duplicate(true))
	_transport_endpoint.send_use_ability_intent(payload)
	return OK


## 将击毁后回基地的选择发送给权威服务器。
## [param payload] 调用方传入的 `payload` 参数。
## 返回该函数计算、查询或操作得到的结果。
func send_vehicle_recovery_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	vehicle_recovery_intent_sent.emit(payload.duplicate(true))
	_transport_endpoint.send_vehicle_recovery_intent(payload)
	return OK


## 将地面掉落拾取意图发往权威服务器。
## [param payload] 仅包含 loot_id 的目标选择字典。
## 返回传输可用时 OK；未连接时返回 ERR_UNCONFIGURED。
func send_pickup_loot_intent(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	pickup_loot_intent_sent.emit(payload.duplicate(true))
	_transport_endpoint.send_pickup_loot_intent(payload)
	return OK


## 将面板查询或事务意图发往权威服务器。
## [param payload] 已由会话层生成的命令字典。
## 返回传输可用时 OK；未连接时返回 ERR_UNCONFIGURED。
## 设计：离线调试只发出可观测信号，不在适配器内伪造权威状态。
func send_player_panel_command(payload: Dictionary) -> Error:
	if connection_state != ConnectionState.CONNECTED:
		return ERR_UNCONFIGURED
	player_panel_command_sent.emit(payload.duplicate(true))
	_transport_endpoint.send_player_panel_command(payload)
	return OK


## 执行 `inject_authoritative_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func inject_authoritative_snapshot(snapshot: Dictionary) -> void:
	if offline_debug_enabled:
		authoritative_snapshot_received.emit(snapshot.duplicate(true))


## 执行 `inject_remote_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func inject_remote_snapshot(snapshot: Dictionary) -> void:
	if offline_debug_enabled:
		remote_snapshot_received.emit(snapshot.duplicate(true))


## 执行 `receive_server_message` 对应的模块操作。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 执行 `receive_world_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func receive_world_snapshot(snapshot: Dictionary) -> void:
	authoritative_snapshot_received.emit(snapshot.duplicate(true))
	remote_snapshot_received.emit(snapshot.duplicate(true))


## 处理 `_on_connected_to_server` 对应的信号回调。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_connected_to_server() -> void:
	_set_connection_state(ConnectionState.CONNECTED)
	var request := {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}
	if not reconnect_token.is_empty():
		request["reconnect_token"] = reconnect_token
	_transport_endpoint.request_session(request)


## 处理 `_on_connection_failed` 对应的信号回调。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_connection_failed() -> void:
	if _transport_endpoint != null:
		_transport_endpoint.close()
	session_ready = false
	_set_connection_state(ConnectionState.DISCONNECTED)
	connection_failed.emit("Unable to connect to the authoritative server")


## 处理 `_on_server_disconnected` 对应的信号回调。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_server_disconnected() -> void:
	if _transport_endpoint != null:
		_transport_endpoint.close()
	session_ready = false
	_set_connection_state(ConnectionState.DISCONNECTED)


## 设置或恢复 `set_connection_state` 对应的模块状态。
## [param next_state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _set_connection_state(next_state: ConnectionState) -> void:
	if connection_state == next_state:
		return
	connection_state = next_state
	connection_state_changed.emit(connection_state)


## 执行 `ensure_transport_endpoint` 对应的模块操作。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _ensure_transport_endpoint() -> void:
	if _transport_endpoint != null:
		return
	if offline_debug_enabled:
		_transport_endpoint = InProcessTransportScript.new()
		_transport_endpoint.name = "StarhomeInProcessTransport"
		add_child(_transport_endpoint)
		if _in_process_server_config != null:
			_transport_endpoint.call(
				"configure_server", _in_process_server_config, _in_process_repository
			)
	else:
		var existing := get_tree().root.get_node_or_null(TransportEndpointScript.ROOT_NODE_NAME)
		if existing != null:
			_transport_endpoint = existing
		else:
			_transport_endpoint = TransportEndpointScript.new()
			_transport_endpoint.name = TransportEndpointScript.ROOT_NODE_NAME
			get_tree().root.add_child(_transport_endpoint)
	_connect_transport_signal(&"connected_to_server", _on_connected_to_server)
	_connect_transport_signal(&"connection_failed", _on_connection_failed)
	_connect_transport_signal(&"server_disconnected", _on_server_disconnected)
	_connect_transport_signal(&"server_message_received", receive_server_message)
	_connect_transport_signal(&"world_snapshot_received", receive_world_snapshot)


## 将传输端点信号与客户端回调绑定，并保证重连或复用根节点时不会重复绑定。
## [param signal_name] 传输端点公开的信号名称。
## [param callback] 接收该信号的客户端回调。
## 无返回值。
## 设计：网络端点常驻 SceneTree 根节点以承载断线重连；绑定必须具备幂等性。
func _connect_transport_signal(signal_name: StringName, callback: Callable) -> void:
	if _transport_endpoint.is_connected(signal_name, callback):
		return
	_transport_endpoint.connect(signal_name, callback)


## 设置或恢复 `apply_session_opened` 对应的模块状态。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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
