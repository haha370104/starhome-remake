extends SceneTree

const TransportScript := preload(
	"res://scripts/network/transport/in_process_authoritative_transport.gd"
)
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")

var failures: PackedStringArray = []
var assertions := 0
var messages: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var database_path := ""


## 延迟运行进程内权威传输集成测试。
func _initialize() -> void:
	call_deferred("_run")


## 验证本地模式只替换传输，并完整经过正式服务器的会话、面板、移动与快照链路。
func _run() -> void:
	var transport := TransportScript.new()
	database_path = "res://in_process_transport_%d.tmp" % Time.get_ticks_usec()
	var config := ServerConfigScript.new()
	config.network_enabled = false
	config.player_state_store_path = database_path
	config.default_spawn = Vector2(480.0, 370.0)
	_expect(transport.configure_server(config), "进程内传输应允许测试注入正式服务器配置")
	transport.server_message_received.connect(
		func(message: Dictionary) -> void: messages.append(message.duplicate(true))
	)
	transport.world_snapshot_received.connect(
		func(snapshot: Dictionary) -> void: snapshots.append(snapshot.duplicate(true))
	)
	root.add_child(transport)
	var connection_error := transport.connect_client("ignored", 0)
	_expect(connection_error == OK, "进程内权威传输应成功初始化正式服务器：%s" % transport._initialization_error)
	await process_frame
	transport.request_session({
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	})
	await process_frame
	await process_frame
	var opened := _first_message(&"session_opened")
	_expect(not opened.is_empty(), "本地握手必须返回正式 session_opened 消息")
	if opened.is_empty():
		_finish(transport)
		return
	var opened_value: Dictionary = opened["result"]["value"]
	var joined: Dictionary = opened_value["map_joined"]
	var entity_id := String(joined["entity_id"])
	var map_instance_id := String(joined["map_instance_id"])
	_expect(entity_id.begins_with("player."), "玩家身份必须由正式服务器会话分配")
	_expect(not map_instance_id.is_empty(), "握手必须携带正式地图实例标识")

	transport.send_player_panel_command({"type": "query", "command_sequence": 1})
	await process_frame
	var panels := _first_message(&"player_panels")
	_expect(not panels.is_empty(), "本地面板查询必须经过正式服务器面板服务")
	if not panels.is_empty():
		var bundle: Dictionary = panels["result"]["value"]
		_expect(bundle.has("character") and bundle.has("inventory") and bundle.has("vehicle"),
			"本地面板回包必须使用与联机相同的三面板契约")

	var spawn_value: Variant = joined["spawn_position"]
	var spawn := Vector2(float(spawn_value["x"]), float(spawn_value["y"]))
	transport.send_move_intent({
		"map_instance_id": map_instance_id,
		"requested_world_point": {"x": spawn.x + 24.0, "y": spawn.y},
		"input_sequence": 1,
	})
	await process_frame
	transport.advance_simulation(0.2)
	_expect(not snapshots.is_empty(), "本地服务器必须按正式快照频率发布 peer 权威快照")
	if not snapshots.is_empty():
		var entities: Array = snapshots[-1].get("entities", [])
		var local_matches := entities.filter(func(entity: Dictionary) -> bool:
			return String(entity.get("entity_id", "")) == entity_id
		)
		_expect(local_matches.size() == 1, "本地快照必须包含服务器会话拥有的玩家实体")
		if not local_matches.is_empty():
			_expect(int(local_matches[0].get("acknowledged_input_sequence", 0)) == 1,
				"移动确认序号必须来自正式地图实例而非本地伪造")

	transport.send_map_transition_intent({
		"map_instance_id": map_instance_id,
		"transition_id": "exit_to_city",
		"destination_entry_number": 0,
		"input_sequence": 1,
	})
	await process_frame
	var transitioned := _last_message(&"map_joined")
	_expect(not transitioned.is_empty(), "本地切图必须调用与 ENet 相同的权威地图跳转处理器")
	if not transitioned.is_empty():
		var transitioned_value: Dictionary = transitioned["result"]["value"]["map_joined"]
		_expect(String(transitioned_value.get("map_id", "")) == "yian_harbor_city",
			"进程内传输不得自行推导目标地图或落点")
	_finish(transport)


## 查找首条指定类型的可靠服务器消息。
## [param message_type] session_opened、player_panels 等消息类型。
## 返回匹配消息的副本；不存在时返回空字典。
func _first_message(message_type: StringName) -> Dictionary:
	for message: Dictionary in messages:
		if StringName(message.get("type", "")) == message_type:
			return message.duplicate(true)
	return {}


## 查找最后一条指定类型的可靠服务器消息。
## [param message_type] map_joined 等可能在会话期间重复出现的消息类型。
## 返回最新匹配消息的副本；不存在时返回空字典。
func _last_message(message_type: StringName) -> Dictionary:
	for index in range(messages.size() - 1, -1, -1):
		var message: Dictionary = messages[index]
		if StringName(message.get("type", "")) == message_type:
			return message.duplicate(true)
	return {}


## 记录一个布尔断言。
## [param condition] 预期成立的条件。
## [param message] 失败时输出的信息。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


## 汇总断言、释放本地服务器并退出测试进程。
## [param transport] 本次测试创建的进程内传输节点。
func _finish(transport: Node) -> void:
	transport.call("close")
	transport.free()
	for path: String in [database_path, database_path + ".tmp", database_path + ".bak"]:
		if not path.is_empty() and FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if failures.is_empty():
		print("IN_PROCESS_AUTHORITATIVE_TRANSPORT_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
