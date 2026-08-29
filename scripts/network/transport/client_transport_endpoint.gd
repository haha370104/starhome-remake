class_name ClientTransportEndpoint
extends Node

signal connected_to_server
signal connection_failed
signal server_disconnected
signal server_message_received(message: Dictionary)
signal world_snapshot_received(snapshot: Dictionary)


## 建立客户端到权威服务器的传输连接。
## [param host] 远程实现使用的服务器地址；进程内实现可忽略。
## [param port] 远程实现使用的服务器端口；进程内实现可忽略。
## 返回连接启动结果；握手完成仍通过信号异步通知。
func connect_client(host: String, port: int) -> Error:
	push_error("Client transport must implement connect_client: %s:%d" % [host, port])
	return ERR_METHOD_NOT_FOUND


## 关闭传输并释放其拥有的会话资源。
func close() -> void:
	pass


## 发送会话握手请求。
## [param request] 仅含协议版本、内容版本及可选重连令牌的字典。
func request_session(request: Dictionary) -> void:
	push_error("Client transport must implement request_session: %s" % request)


## 发送移动意图。
## [param intent] 已由客户端会话校验的移动协议载荷。
func send_move_intent(intent: Dictionary) -> void:
	push_error("Client transport must implement send_move_intent: %s" % intent)


## 发送地图切换意图。
## [param intent] 已由客户端会话校验的地图切换协议载荷。
func send_map_transition_intent(intent: Dictionary) -> void:
	push_error("Client transport must implement send_map_transition_intent: %s" % intent)


## 发送能力使用意图。
## [param intent] 已由客户端会话校验的能力协议载荷。
func send_use_ability_intent(intent: Dictionary) -> void:
	push_error("Client transport must implement send_use_ability_intent: %s" % intent)


## 发送地面掉落拾取意图。
## [param intent] 仅含权威掉落实例标识的协议载荷。
func send_pickup_loot_intent(intent: Dictionary) -> void:
	push_error("Client transport must implement send_pickup_loot_intent: %s" % intent)


## 发送人物、背包或战车面板命令。
## [param command] 已由客户端会话补全序号和 revision 的协议载荷。
func send_player_panel_command(command: Dictionary) -> void:
	push_error("Client transport must implement send_player_panel_command: %s" % command)
