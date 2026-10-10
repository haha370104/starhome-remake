class_name ClientMultiplayerSession
extends Node

const EntitySnapshotContract := preload("res://scripts/network/contracts/entity_snapshot.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const MapTransitionIntentContract := preload("res://scripts/network/contracts/map_transition_intent.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")
const VehicleRecoveryIntentContract := preload(
	"res://scripts/network/contracts/vehicle_recovery_intent.gd"
)
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

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
signal loot_picked_up(event: Dictionary, player_change: Dictionary)
signal player_change_received(change: Dictionary)
signal synchronization_started(sync_id: String)
signal mining_collected(event: Dictionary, player_change: Dictionary)
signal skill_level_up_received(event: Dictionary)
signal vehicle_recovery_scheduled(delay_seconds: float)
signal vehicle_recovery_failed(code: StringName, message: String)
signal social_event_received(message: Dictionary)

@export var offline_debug_enabled := false
@export var local_entity_id: StringName = &"player.local"
@export var local_display_name := ""
@export var current_map_id: StringName = &""
@export var current_map_instance_id := ""

var network_adapter: ClientNetworkAdapter
var local_predictor := LocalMovementPredictor.new()
var remote_interpolator := RemoteEntityInterpolator.new()
var _known_remote_entity_ids: Dictionary = {}
var _next_transition_sequence := 1
var _pending_map_change: Dictionary = {}
var _pending_world_snapshots: Dictionary = {}
var _pending_local_snapshots: Dictionary = {}
var _minimum_snapshot_server_tick := -1
var _last_combat_event_id := -1
var _suppress_local_presentation_signal := false
var _next_ability_sequence := 1
var _next_panel_command_sequence := 1
var _next_recovery_sequence := 1
var _pending_vehicle_recovery: Dictionary = {}


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
	network_adapter.authoritative_world_snapshot_received.connect(_on_world_snapshot)
	network_adapter.authoritative_local_snapshot_received.connect(_on_local_snapshot)
	local_predictor.presentation_state_changed.connect(_on_local_predictor_presentation_changed)
	local_predictor.move_intent_created.connect(_on_move_intent_created)
	remote_interpolator.presentation_state_changed.connect(remote_presentation_state_changed.emit)
	network_adapter.configure_offline_debug(offline_debug_enabled)
	network_adapter.local_display_name = local_display_name


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
	_pending_vehicle_recovery.clear()
	_pending_world_snapshots.clear()
	_pending_local_snapshots.clear()
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
## [param aim_world_position] 瞄准世界坐标，只用于表达发射方向。
## 返回该函数计算、查询或操作得到的结果。
func request_use_ability(ability_id: String, aim_world_position: Vector2) -> Dictionary:
	if current_map_instance_id.is_empty() or ability_id.is_empty() or not aim_world_position.is_finite():
		return {}
	var contract := UseAbilityIntentContract.new(
		current_map_instance_id, ability_id, aim_world_position, _next_ability_sequence
	)
	var validation = contract.validate()
	if not validation.is_ok:
		return {}
	var payload: Dictionary = contract.to_dictionary()
	if network_adapter.send_use_ability_intent(payload) != OK:
		return {}
	_next_ability_sequence += 1
	return payload


## 请求权威服务器在战车击毁后安排返回基地；地图、坐标和回血值不由客户端提供。
## 返回该函数计算、查询或操作得到的结果。
func request_vehicle_recovery() -> Dictionary:
	if network_adapter == null or current_map_instance_id.is_empty() \
			or not _pending_vehicle_recovery.is_empty():
		return {}
	var contract := VehicleRecoveryIntentContract.new(
		current_map_instance_id,
		VehicleRecoveryIntentContract.RETURN_TO_BASE,
		_next_recovery_sequence,
	)
	var validation = contract.validate()
	if not validation.is_ok:
		return {}
	var payload: Dictionary = contract.to_dictionary()
	if network_adapter.send_vehicle_recovery_intent(payload) != OK:
		return {}
	_pending_vehicle_recovery = payload.duplicate(true)
	_next_recovery_sequence += 1
	return payload


## 返回当前是否正在等待权威基地救援完成。
## 查询 `is_vehicle_recovery_pending` 对应的模块状态。
func is_vehicle_recovery_pending() -> bool:
	return not _pending_vehicle_recovery.is_empty()


## 请求拾取权威快照中可见的一件地面掉落物。
## [param loot_id] 服务端生成并随战斗快照发布的掉落实例标识。
## 返回实际发送的最小意图；会话不可用时返回空字典。
func request_loot_pickup(loot_id: String) -> Dictionary:
	if network_adapter == null or current_map_instance_id.is_empty() or loot_id.is_empty():
		return {}
	var payload := {"loot_id": loot_id}
	if network_adapter.send_pickup_loot_intent(payload) != OK:
		return {}
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


## 提交组队、聊天或玩家交易命令；载荷不附加角色身份或客户端状态。
## 返回实际发送的可靠命令，连接不可用时返回空字典。
func request_social_command(command: Dictionary) -> Dictionary:
	if network_adapter == null or command.is_empty():
		return {}
	var payload := command.duplicate(true)
	if network_adapter.send_social_command(payload) != OK:
		return {}
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


## 通知预测器本地路线已走完，并等待服务器权威实体抵达相同终点。
## [param input_sequence] 本次路线对应的移动输入序号。
## 返回该序号是否仍属于当前活动预测路线。
func finish_local_predicted_route(input_sequence: int) -> bool:
	return local_predictor.finish_local_route(input_sequence)


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
	if not _is_valid_world_snapshot(snapshot):
		return
	var key := _snapshot_key(snapshot)
	_pending_world_snapshots[key] = snapshot
	_prune_pending_snapshots(snapshot)
	_try_apply_snapshot_pair(key)


func _on_local_snapshot(snapshot: Dictionary) -> void:
	if not _is_valid_local_snapshot(snapshot):
		return
	var key := _snapshot_key(snapshot)
	_pending_local_snapshots[key] = snapshot
	_prune_pending_snapshots(snapshot)
	_try_apply_snapshot_pair(key)


func _try_apply_snapshot_pair(key: String) -> void:
	if not _pending_world_snapshots.has(key) or not _pending_local_snapshots.has(key):
		return
	var world: Dictionary = _pending_world_snapshots[key]
	var local: Dictionary = _pending_local_snapshots[key]
	_pending_world_snapshots.erase(key)
	_pending_local_snapshots.erase(key)
	var apply_started_at := PerformanceTelemetryScript.begin(&"client_world_snapshot_apply")
	var server_tick := int(world["server_tick"])
	var server_time := float(world["server_time_seconds"])
	var entities: Array = world["entities"]
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
				entity.action_id,
				entity.movement_speed,
			)
		else:
			remote_entities.append(raw_entity)
	if not remote_interpolator.push_snapshot(server_tick, server_time, remote_entities, world.get("player_presentation", {})):
		PerformanceTelemetryScript.end(&"client_world_snapshot_apply", apply_started_at)
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
	# 网络协议已拆分；这里才组合成表现层仍使用的单次状态投影。
	var combat_world: Dictionary = world["combat_world"]
	var establish_baseline := _last_combat_event_id < 0
	_last_combat_event_id = maxi(_last_combat_event_id, 0)
	var new_events: Array = []
	for event: Dictionary in combat_world["recent_events"]:
		var event_id := int(event.event_id)
		if event_id <= _last_combat_event_id: continue
		_last_combat_event_id = event_id
		if not establish_baseline: new_events.append(event)
	var combat_snapshot := combat_world.duplicate()
	combat_snapshot["server_tick"] = server_tick
	combat_snapshot["server_time_seconds"] = server_time
	combat_snapshot["recent_events"] = new_events
	combat_snapshot.merge(local)
	NetworkProtocol.freeze_snapshot(combat_snapshot)
	combat_snapshot_received.emit(combat_snapshot)
	PerformanceTelemetryScript.end(&"client_world_snapshot_apply", apply_started_at)


func _prune_pending_snapshots(newest_snapshot: Dictionary) -> void:
	var map_instance_id := String(newest_snapshot["map_instance_id"])
	var server_tick := int(newest_snapshot["server_tick"])
	for pending_snapshots: Dictionary in [_pending_world_snapshots, _pending_local_snapshots]:
		for key: String in pending_snapshots.keys():
			var pending: Dictionary = pending_snapshots[key]
			if String(pending.get("map_instance_id", "")) == map_instance_id \
				and int(pending.get("server_tick", -1)) < server_tick:
				pending_snapshots.erase(key)


## 处理 `_on_session_opened` 对应的信号回调。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_session_opened(result: Dictionary) -> void:
	var value: Dictionary = result.get("value", {})
	synchronization_started.emit(String(value.get("session", {}).get("sync_id", "")))
	if not _commit_map_joined(value, false):
		connection_failed.emit("Server handshake contained an invalid initial map join")
		network_adapter.disconnect_from_server()
		return
	request_player_panel_command({"type": "query"})


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
	var world_value: Variant = value.get("world_snapshot")
	var local_value: Variant = value.get("local_snapshot")
	if not world_value is Dictionary or not local_value is Dictionary:
		_fail_pending_map_change(
			NetworkErrorCodes.INVALID_PAYLOAD,
			"Map join did not include both target-map snapshots",
		)
		return false
	var world: Dictionary = world_value
	var local: Dictionary = local_value
	if (
		not _is_valid_world_snapshot(world, joined.map_instance_id)
		or not _is_valid_local_snapshot(local, joined.map_instance_id)
		or String(world["map_instance_id"]) != joined.map_instance_id
		or String(local["map_instance_id"]) != joined.map_instance_id
		or int(world["server_tick"]) != joined.server_tick
		or int(local["server_tick"]) != joined.server_tick
	):
		_fail_pending_map_change(
			NetworkErrorCodes.INVALID_PAYLOAD,
			"Map join snapshot does not match the authoritative join tick",
		)
		return false
	world = world.duplicate(true)
	# 移动序号属于同一认证会话的单调序列；map_instance_id 负责隔离地图。
	# 切图只清除旧预测路线，不能把序号退回 1，否则服务端会将新地图首个输入判为重放。
	var next_movement_sequence := _movement_sequence_after_join(
		world, StringName(joined.entity_id)
	)

	_suppress_local_presentation_signal = true
	local_entity_id = StringName(joined.entity_id)
	current_map_id = StringName(joined.map_id)
	current_map_instance_id = joined.map_instance_id
	network_adapter.entity_id = joined.entity_id
	network_adapter.map_id = joined.map_id
	network_adapter.map_instance_id = joined.map_instance_id
	_minimum_snapshot_server_tick = joined.server_tick
	_last_combat_event_id = -1
	local_predictor.reset(joined.spawn_position, next_movement_sequence, false)
	_clear_remote_entities()
	remote_interpolator.reset()
	_pending_world_snapshots.clear()
	_pending_local_snapshots.clear()
	_pending_map_change.clear()
	var joined_snapshot_key := _snapshot_key(world)
	_pending_world_snapshots[joined_snapshot_key] = world
	_pending_local_snapshots[joined_snapshot_key] = local
	_try_apply_snapshot_pair(joined_snapshot_key)
	_suppress_local_presentation_signal = false
	map_joined.emit(
		current_map_id,
		current_map_instance_id,
		joined.spawn_position,
		joined.definition_version,
	)
	local_presentation_state_changed.emit(local_predictor.presentation_state())
	return true


## 保留本会话尚未使用的序号，并在重连时至少越过服务器已确认值。
## [param snapshot] 调用方传入的 `snapshot` 参数。
## [param joined_entity_id] 调用方传入的 `joined_entity_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _movement_sequence_after_join(snapshot: Dictionary, joined_entity_id: StringName) -> int:
	var result := local_predictor.next_input_sequence
	for raw_entity: Variant in snapshot.get("entities", []):
		if not raw_entity is Dictionary:
			continue
		var entity: Dictionary = raw_entity
		if StringName(entity.get("entity_id", &"")) != joined_entity_id:
			continue
		return maxi(result, int(entity.get("acknowledged_input_sequence", 0)) + 1)
	return result


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
	if not network_adapter.session_ready:
		connection_failed.emit(message if not message.is_empty() else String(code))
		network_adapter.disconnect_from_server()
		return
	# The adapter's compact signal intentionally excludes protocol context. Inspect the last
	# reliable envelope so map-change completion still requires an exact command/sequence match.
	# Context-aware handling is performed in `_on_server_message_received`.


## 处理 `_on_server_message_received` 对应的信号回调。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func _on_server_message_received(message: Dictionary) -> void:
	var message_type := StringName(message.get("type", ""))
	if message_type in [
		&"social_result", &"party_invite", &"party_join_request", &"party_invite_declined", &"party_invite_cancelled", &"party_removed", &"party_state",
			&"chat_event", &"trade_invite", &"trade_invite_declined", &"trade_state", &"trade_completed",
			&"trade_cancelled", &"trade_invite_cancelled", &"friend_invite", &"friend_invite_declined",
			&"friend_invite_cancelled", &"friend_state",
			&"mail_state", &"mail_received",
	]:
		social_event_received.emit(message.duplicate(true))
		return
	if message_type == &"vehicle_recovery_scheduled":
		var scheduled_result: Dictionary = message.get("result", {})
		var scheduled_value: Variant = scheduled_result.get("value")
		if bool(scheduled_result.get("ok", false)) and scheduled_value is Dictionary \
				and not _pending_vehicle_recovery.is_empty() \
				and int(scheduled_value.get("input_sequence", -1)) \
				== int(_pending_vehicle_recovery["input_sequence"]):
			vehicle_recovery_scheduled.emit(float(scheduled_value.get("delay_seconds", 3.0)))
		return
	if message_type == &"vehicle_recovery_completed":
		var completed_result: Dictionary = message.get("result", {})
		var completed_value: Variant = completed_result.get("value")
		if bool(completed_result.get("ok", false)) and completed_value is Dictionary \
				and not _pending_vehicle_recovery.is_empty() \
				and int(completed_value.get("input_sequence", -1)) \
				== int(_pending_vehicle_recovery["input_sequence"]):
			if _commit_map_joined(completed_value, true):
				_pending_vehicle_recovery.clear()
				request_player_panel_command({"type": "query"})
		return
	if message_type == &"skill_level_up":
		var skill_result: Dictionary = message.get("result", {})
		var skill_value: Variant = skill_result.get("value")
		if bool(skill_result.get("ok", false)) and skill_value is Dictionary:
			skill_level_up_received.emit((skill_value as Dictionary).duplicate(true))
		return
	if message_type == &"loot_picked_up":
		var loot_result: Dictionary = message.get("result", {})
		var loot_value: Variant = loot_result.get("value")
		if bool(loot_result.get("ok", false)) and loot_value is Dictionary:
			var value: Dictionary = loot_value
			loot_picked_up.emit(
				(value.get("loot_event", {}) as Dictionary).duplicate(true),
				(value.get("player_change", {}) as Dictionary).duplicate(true),
			)
			if value.has("manufacturing"): player_panel_bundle_received.emit(value)
		return
	if message_type == &"mining_collected":
		var mining_result: Dictionary = message.get("result", {})
		var mining_value: Variant = mining_result.get("value")
		if bool(mining_result.get("ok", false)) and mining_value is Dictionary:
			var value: Dictionary = mining_value
			mining_collected.emit(
				(value.get("mining_event", {}) as Dictionary).duplicate(true),
				(value.get("player_change", {}) as Dictionary).duplicate(true),
			)
			if value.has("manufacturing"): player_panel_bundle_received.emit(value)
		return
	if message_type == &"player_changed":
		var change_result: Dictionary = message.get("result", {})
		if bool(change_result.get("ok", false)) and change_result.get("value", {}).get("player_change") is Dictionary:
			player_change_received.emit(change_result.value.player_change.duplicate(true))
			if change_result.value.has("manufacturing"): player_panel_bundle_received.emit(change_result.value)
		return
	if message_type == &"player_panels":
		var panels_result: Dictionary = message.get("result", {})
		var panels_value: Variant = panels_result.get("value")
		if bool(panels_result.get("ok", false)) and panels_value is Dictionary:
			player_panel_bundle_received.emit((panels_value as Dictionary).duplicate(true))
		return
	if message_type == &"combat_event":
		var combat_result: Dictionary = message.get("result", {})
		if bool(combat_result.get("ok", false)) and combat_result.get("value") is Dictionary:
			var event: Dictionary = (combat_result["value"] as Dictionary).duplicate(true)
			CombatTraceLogger.record(&"client", &"authoritative_combat_event_received", event)
			combat_event_received.emit(event)
		return
	if message_type != &"command_rejected":
		return
	var result: Dictionary = message.get("result", {})
	CombatTraceLogger.record(&"client", &"command_rejected_received", result)
	var context: Dictionary = result.get("value", {}) if result.get("value") is Dictionary else {}
	if context.get("operation") == "prepare_exit":
		player_panel_bundle_received.emit({"exit_failure": {"request_id": String(context.get("request_id", "")),
			"code": String(result.get("code", "")), "message": String(result.get("message", "保存失败"))}})
		return
	if StringName(context.get("command_type", "")) == Protocol.VEHICLE_RECOVERY_INTENT \
			and not _pending_vehicle_recovery.is_empty() \
			and int(context.get("input_sequence", -1)) \
			== int(_pending_vehicle_recovery["input_sequence"]):
		_pending_vehicle_recovery.clear()
		vehicle_recovery_failed.emit(
			StringName(result.get("code", NetworkErrorCodes.INVALID_PAYLOAD)),
			String(result.get("message", "Server rejected vehicle recovery")),
		)
		return
	if _pending_map_change.is_empty():
		return
	if StringName(context.get("command_type", "")) != Protocol.MAP_TRANSITION_INTENT:
		return
	if int(context.get("transition_sequence", -1)) != int(_pending_map_change["input_sequence"]):
		return
	_fail_pending_map_change(
		StringName(result.get("code", NetworkErrorCodes.INVALID_PAYLOAD)),
		String(result.get("message", "Server rejected the map transition")),
	)


func _snapshot_key(snapshot: Dictionary) -> String:
	return "%s:%d" % [String(snapshot["map_instance_id"]), int(snapshot["server_tick"])]


func _is_valid_world_snapshot(snapshot: Dictionary, expected_map_instance_id := "") -> bool:
	var required_map_instance_id := expected_map_instance_id if not expected_map_instance_id.is_empty() else current_map_instance_id
	if not required_map_instance_id.is_empty() \
		and String(snapshot.get("map_instance_id", "")) != required_map_instance_id:
		return false
	if typeof(snapshot.get("map_instance_id")) != TYPE_STRING \
		or String(snapshot["map_instance_id"]).is_empty() \
		or typeof(snapshot.get("server_tick")) != TYPE_INT \
		or int(snapshot["server_tick"]) < _minimum_snapshot_server_tick \
		or typeof(snapshot.get("server_time_seconds")) not in [TYPE_INT, TYPE_FLOAT] \
		or not snapshot.get("entities") is Array \
		or not snapshot.get("combat_world") is Dictionary:
		return false
	var combat_world: Dictionary = snapshot["combat_world"]
	if not combat_world.get("monsters") is Array \
		or not combat_world.get("ground_loot") is Array \
		or not combat_world.get("mine_sources") is Array \
		or not combat_world.get("corrosive_clouds") is Array \
		or not combat_world.get("recent_events") is Array \
		or typeof(combat_world.get("vehicle_combat_active")) != TYPE_BOOL:
		return false
	for raw_event: Variant in combat_world["recent_events"]:
		if not raw_event is Dictionary:
			return false
		var event: Dictionary = raw_event
		if typeof(event.get("event_id")) != TYPE_INT:
			return false
	return true


func _is_valid_local_snapshot(snapshot: Dictionary, expected_map_instance_id := "") -> bool:
	var required_map_instance_id := expected_map_instance_id if not expected_map_instance_id.is_empty() else current_map_instance_id
	if not required_map_instance_id.is_empty() \
		and String(snapshot.get("map_instance_id", "")) != required_map_instance_id:
		return false
	if not (typeof(snapshot.get("map_instance_id")) == TYPE_STRING \
		and not String(snapshot["map_instance_id"]).is_empty() \
		and typeof(snapshot.get("server_tick")) == TYPE_INT \
		and typeof(snapshot.get("local_entity_id")) == TYPE_STRING \
		and not String(snapshot["local_entity_id"]).is_empty() \
		and snapshot.get("local_vehicle") is Dictionary \
		and snapshot.get("local_weapon_flight") is Dictionary \
		and snapshot.get("local_sama_effects") is Array \
		and snapshot.get("local_mining") is Dictionary):
		return false
	var mining: Dictionary = snapshot["local_mining"]
	if typeof(mining.get("active")) != TYPE_BOOL:
		return false
	if mining.active:
		var target: Variant = mining.get("target_position")
		if not target is Array or target.size() != 2:
			return false
		for coordinate: Variant in target:
			if typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(coordinate)):
				return false
	return int(snapshot["server_tick"]) >= _minimum_snapshot_server_tick


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
