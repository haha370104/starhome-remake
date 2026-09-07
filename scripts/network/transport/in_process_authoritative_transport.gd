class_name InProcessAuthoritativeTransport
extends "res://scripts/network/transport/client_transport_endpoint.gd"

const AuthoritativeServerScript := preload("res://scripts/server/authoritative_server.gd")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")

const LOCAL_PEER_ID := 2

var authoritative_server: AuthoritativeServer
var _connected := false
var _initialization_error := ""
var _server_config: DedicatedServerConfig
var _repository: PlayerStateRepository


## 在连接前注入本地服务器配置和可选仓储。
## [param requested_config] 与独立服务器完全相同的配置对象。
## [param injected_repository] 测试或嵌入环境提供的仓储；为空时使用配置路径。
## 返回是否在服务器启动前成功接收配置。
func configure_server(
	requested_config: DedicatedServerConfig,
	injected_repository: PlayerStateRepository = null,
) -> bool:
	if authoritative_server != null or requested_config == null:
		return false
	_server_config = requested_config
	_repository = injected_repository
	return true


## 初始化真正的权威服务器，但不创建 ENet socket。
## 返回服务器地图、存档、战斗及面板服务是否全部可用。
## 设计：进程内模式只替换传输，不替换或模拟任何服务端业务模块。
func initialize() -> Error:
	if authoritative_server != null:
		return OK if _initialization_error.is_empty() else ERR_CANT_CREATE
	var config := _server_config if _server_config != null else ServerConfigScript.new()
	config.network_enabled = false
	authoritative_server = AuthoritativeServerScript.new()
	var initialized := authoritative_server.initialize(config, [], _repository)
	if not bool(initialized.get("ok", false)):
		_initialization_error = String(initialized.get("message", "unknown server initialization error"))
		authoritative_server.free()
		authoritative_server = null
		return ERR_CANT_CREATE
	authoritative_server.server_message_generated.connect(_on_server_message_generated)
	authoritative_server.peer_snapshot_generated.connect(_on_peer_snapshot_generated)
	add_child(authoritative_server)
	return OK


## 建立进程内异步传输连接。
## [param _host] 为保持传输契约一致而保留，进程内实现不使用地址。
## [param _port] 为保持传输契约一致而保留，进程内实现不使用端口。
## 返回本地权威服务器初始化是否成功。
func connect_client(_host: String, _port: int) -> Error:
	var error := initialize()
	if error != OK:
		call_deferred("_emit_connection_failure")
		return error
	call_deferred("_complete_connection")
	return OK


## 关闭本地会话并触发与正式服务器相同的存档收尾。
## 设计：先切断传输对服务端的可达引用，再同步完成断线和存档，最后延迟释放；允许从服务端信号回调内安全调用。
func close() -> void:
	var server_to_release := authoritative_server
	var was_connected := _connected
	_connected = false
	authoritative_server = null
	_repository = null
	if server_to_release == null:
		return
	if was_connected:
		server_to_release.disconnect_session(LOCAL_PEER_ID)
	server_to_release.stop_network()
	server_to_release.queue_free()


## 发送会话握手请求。
## [param request] 协议版本、内容版本及可选重连令牌。
func request_session(request: Dictionary) -> void:
	_enqueue(AuthoritativeServer.TRANSPORT_SESSION_REQUEST, request)


## 发送移动意图。
## [param intent] 已由客户端会话校验的移动协议载荷。
func send_move_intent(intent: Dictionary) -> void:
	_enqueue(Protocol.MOVE_INTENT, intent)


## 发送地图切换意图。
## [param intent] 已由客户端会话校验的地图切换协议载荷。
func send_map_transition_intent(intent: Dictionary) -> void:
	_enqueue(Protocol.MAP_TRANSITION_INTENT, intent)


## 发送能力使用意图。
## [param intent] 已由客户端会话校验的能力协议载荷。
func send_use_ability_intent(intent: Dictionary) -> void:
	_enqueue(Protocol.USE_ABILITY_INTENT, intent)


## 发送战车击毁后的恢复选择。
## [param intent] 调用方传入的 `intent` 参数。
func send_vehicle_recovery_intent(intent: Dictionary) -> void:
	_enqueue(Protocol.VEHICLE_RECOVERY_INTENT, intent)


## 发送地面掉落拾取意图。
## [param intent] 仅含权威掉落实例标识的协议载荷。
func send_pickup_loot_intent(intent: Dictionary) -> void:
	_enqueue(Protocol.PICKUP_LOOT_INTENT, intent)


## 发送人物、背包或战车面板命令。
## [param command] 已由客户端会话补全序号和 revision 的协议载荷。
func send_player_panel_command(command: Dictionary) -> void:
	_enqueue(AuthoritativeServer.TRANSPORT_PLAYER_PANEL_COMMAND, command)


## 显式推进进程内权威服务器，供暂停自动时钟的确定性测试调用。
## [param elapsed_seconds] 本次累计模拟时间，单位为秒。
## 设计：运行时只由服务端物理帧驱动；手动推进时调用方必须暂停服务端物理处理，不能叠加两套时钟。
func advance_simulation(elapsed_seconds: float) -> void:
	if _connected and authoritative_server != null:
		authoritative_server.advance_simulation(elapsed_seconds)


## 节点退出场景树时关闭本地权威服务器并提交最终存档。
func _exit_tree() -> void:
	close()


## 把客户端命令复制后排入下一消息循环，模拟真实传输的异步边界。
## [param command_type] 权威服务器支持的传输命令类型。
## [param payload] 不可信客户端载荷。
func _enqueue(command_type: StringName, payload: Dictionary) -> void:
	if not _connected or authoritative_server == null:
		return
	call_deferred("_dispatch", command_type, payload.duplicate(true))


## 将已跨过进程内传输边界的命令交给唯一权威服务器分派器。
## [param command_type] 权威服务器支持的传输命令类型。
## [param payload] 经过传输复制但仍需服务端校验的载荷。
func _dispatch(command_type: StringName, payload: Dictionary) -> void:
	if _connected and authoritative_server != null:
		authoritative_server.dispatch_transport_command(LOCAL_PEER_ID, command_type, payload)


## 异步完成本地连接，保证客户端先进入 CONNECTING 再收到 CONNECTED。
func _complete_connection() -> void:
	if authoritative_server == null:
		_emit_connection_failure()
		return
	_connected = true
	connected_to_server.emit()


## 发布本地权威服务器初始化失败。
func _emit_connection_failure() -> void:
	connection_failed.emit()


## 接收服务器可靠消息并转发给本地客户端。
## [param peer_id] 服务器会话绑定的 peer 标识。
## [param message] 与 ENet 可靠通道完全相同的消息字典。
func _on_server_message_generated(peer_id: int, message: Dictionary) -> void:
	if peer_id == LOCAL_PEER_ID and _connected:
		server_message_received.emit(message.duplicate(true))


## 接收服务器按 peer 生成的快照并转发给本地客户端。
## [param peer_id] 服务器会话绑定的 peer 标识。
## [param snapshot] 与 ENet 快照通道完全相同的权威快照。
func _on_peer_snapshot_generated(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id == LOCAL_PEER_ID and _connected:
		world_snapshot_received.emit(snapshot.duplicate(true))
