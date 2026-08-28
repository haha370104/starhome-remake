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
signal player_panel_bundle_received(bundle: Dictionary)

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
var _next_panel_command_sequence := 1


## 节点进入场景树后初始化运行依赖。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 按渲染帧推进当前节点的表现状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _process(delta: float) -> void:
	local_predictor.advance(delta)
	remote_interpolator.advance(delta)


## 执行 `connect_to_server` 对应的模块操作。
## [param host] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param port] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func connect_to_server(host: String, port: int = ClientNetworkAdapter.DEFAULT_PORT) -> Error:
	return network_adapter.connect_to_server(host, port)


## 执行 `disconnect_from_server` 对应的模块操作。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func disconnect_from_server() -> void:
	network_adapter.disconnect_from_server()
	_clear_remote_entities()


## 配置并初始化 `initialize_local_player` 对应的模块状态。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func initialize_local_player(position: Vector2) -> void:
	local_predictor.reset(position)


## 配置并初始化 `configure_map_instance` 对应的模块状态。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func configure_map_instance(map_instance_id: String) -> void:
	current_map_instance_id = map_instance_id


## 校验并处理 `request_move` 对应的模块状态。
## [param requested_world_point] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func request_move(requested_world_point: Vector2) -> Dictionary:
	if current_map_instance_id.is_empty() or not _pending_map_change.is_empty():
		return {}
	return local_predictor.create_move_intent(current_map_instance_id, requested_world_point)


## 执行 `request_use_ability` 对应的模块操作。
## [param ability_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param target_entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
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


## 提交人物、背包或战车面板命令，并附加单调客户端序号。
## [param command] 查询、移动、整理或换装意图；不得包含角色所有权和权威数值。
## 返回实际发送的载荷；会话不可用时返回空字典。
## 设计：客户端不预测物品或装备状态，只有 player_panels 回包会改变面板快照。
func request_player_panel_command(command: Dictionary) -> Dictionary:
	if network_adapter == null or command.is_empty():
		return {}
	var payload := command.duplicate(true)
	payload["command_sequence"] = _next_panel_command_sequence
	if network_adapter.send_player_panel_command(payload) != OK:
		return {}
	_next_panel_command_sequence += 1
	return payload


## 执行 `request_map_change` 对应的模块操作。
## [param transition_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param destination_entry_number] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 判断 `is_map_change_pending` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func is_map_change_pending() -> bool:
	return not _pending_map_change.is_empty()


## 执行 `record_local_predicted_delta` 对应的模块操作。
## [param input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param displacement] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func record_local_predicted_delta(input_sequence: int, displacement: Vector2) -> bool:
	return local_predictor.apply_predicted_delta(input_sequence, displacement)


## 执行 `local_presentation_state` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func local_presentation_state() -> Dictionary:
	return local_predictor.presentation_state()


## 执行 `remote_presentation_states` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func remote_presentation_states() -> Dictionary:
	return remote_interpolator.presentation_states()


## 执行 `inject_offline_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func inject_offline_snapshot(snapshot: Dictionary) -> void:
	network_adapter.inject_authoritative_snapshot(snapshot)


## 处理 `_on_move_intent_created` 对应的信号回调。
## [param payload] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_move_intent_created(payload: Dictionary) -> void:
	movement_intent_created.emit(payload.duplicate(true))
	network_adapter.send_move_intent(payload)


## 处理 `_on_world_snapshot` 对应的信号回调。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 处理 `_on_session_opened` 对应的信号回调。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_session_opened(result: Dictionary) -> void:
	var value: Dictionary = result.get("value", {})
	if not _commit_map_joined(value, false):
		connection_failed.emit("Server handshake contained an invalid initial map join")
		network_adapter.disconnect_from_server()


## 处理 `_on_map_joined_received` 对应的信号回调。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_map_joined_received(result: Dictionary) -> void:
	var value: Dictionary = result.get("value", {})
	if _pending_map_change.is_empty():
		return
	if int(value.get("transition_sequence", -1)) != int(_pending_map_change["input_sequence"]):
		return
	_commit_map_joined(value, true)


## 执行 `commit_map_joined` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param explicit_transition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
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


## 处理 `_on_local_predictor_presentation_changed` 对应的信号回调。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_local_predictor_presentation_changed(state: Dictionary) -> void:
	if _suppress_local_presentation_signal:
		return
	local_presentation_state_changed.emit(state.duplicate(true))


## 处理 `_on_command_rejected` 对应的信号回调。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_command_rejected(code: StringName, message: String) -> void:
	command_rejected.emit(code, message)
	# The adapter's compact signal intentionally excludes protocol context. Inspect the last
	# reliable envelope so map-change completion still requires an exact command/sequence match.
	# Context-aware handling is performed in `_on_server_message_received`.


## 处理 `_on_server_message_received` 对应的信号回调。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_server_message_received(message: Dictionary) -> void:
	if StringName(message.get("type", "")) == &"player_panels":
		var panels_result: Dictionary = message.get("result", {})
		var panels_value: Variant = panels_result.get("value")
		if bool(panels_result.get("ok", false)) and panels_value is Dictionary:
			player_panel_bundle_received.emit((panels_value as Dictionary).duplicate(true))
		return
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


## 执行 `is_valid_combat_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _is_valid_combat_snapshot(snapshot: Dictionary) -> bool:
	if typeof(snapshot.get("server_tick")) != TYPE_INT:
		return false
	if typeof(snapshot.get("local_entity_id")) != TYPE_STRING \
		or not snapshot.get("local_vehicle") is Dictionary \
		or not snapshot.get("monsters") is Array \
		or not snapshot.get("recent_events") is Array:
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
	for raw_event: Variant in snapshot["recent_events"]:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = raw_event
		var event_type_kind := typeof(event.get("event_type"))
		if typeof(event.get("event_id")) != TYPE_INT \
			or event_type_kind not in [TYPE_STRING, TYPE_STRING_NAME] \
			or typeof(event.get("target_entity_id")) != TYPE_STRING \
			or typeof(event.get("damage")) != TYPE_INT:
			return false
	return true


## 执行 `fail_pending_map_change` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _fail_pending_map_change(code: StringName, message: String) -> void:
	if _pending_map_change.is_empty():
		return
	var transition_id := StringName(_pending_map_change.get("transition_id", ""))
	_pending_map_change.clear()
	map_change_failed.emit(transition_id, code, message)


## 转发网络连接状态，并在连接关闭后清理所有远端表现实体。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：会话层拥有远端实体生命周期，表现层无需理解传输断开细节。
func _on_connection_state_changed(state: ClientNetworkAdapter.ConnectionState) -> void:
	connection_state_changed.emit(state)
	if state == ClientNetworkAdapter.ConnectionState.DISCONNECTED:
		if not _pending_map_change.is_empty():
			_fail_pending_map_change(&"network.disconnected", "Disconnected during map transition")
		_clear_remote_entities()


## 清空插值器中的远端轨迹，并为每个已知实体发布一次移除事件。
## 设计：快照差分与断线清理由会话层统一收口，避免场景遗留幽灵角色。
func _clear_remote_entities() -> void:
	for entity_id in _known_remote_entity_ids:
		remote_interpolator.remove_entity(entity_id)
		remote_entity_removed.emit(entity_id)
	_known_remote_entity_ids.clear()
