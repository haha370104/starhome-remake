extends SceneTree

const ConfigScript := preload("res://scripts/server/server_config.gd")
const ServerScript := preload("res://scripts/server/authoritative_server.gd")
const MoveIntentContract := preload("res://scripts/network/contracts/move_intent.gd")
const MapTransitionIntentContract := preload("res://scripts/network/contracts/map_transition_intent.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const EntitySnapshotContract := preload("res://scripts/network/contracts/entity_snapshot.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")

var failures: PackedStringArray = []
var assertions := 0


## 依次运行权威移动、重连清理和固定帧率服务器冒烟测试并汇总退出码。
## Design: 该入口作为无测试框架的独立夹具，失败信息统一累积后输出。
func _initialize() -> void:
	_test_authoritative_movement()
	_test_dynamic_entity_blocking()
	_test_session_reconnect_and_cleanup()
	_test_authoritative_map_transition()
	_test_fixed_tick_and_snapshot_rate()
	if failures.is_empty():
		print("AUTHORITATIVE_SERVER_SMOKE_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


## 创建禁用真实网络的权威服务器夹具，并配置重连及动态实体阻挡策略。
## [param reconnect_seconds] 断线实体继续保留的秒数。
## [param dynamic_blocking_enabled] 是否启用实体脚点动态阻挡。
## [param dynamic_blocking_radius] 实体脚点之间必须保持的最小距离。
## Returns 初始化完成且已通过大厅资源校验的服务器实例。
## Design: 默认配置与阶段1生产验收一致，用例仅显式覆盖所需策略参数。
func _new_server(
	reconnect_seconds := 30.0,
	dynamic_blocking_enabled := true,
	dynamic_blocking_radius := 18.0,
):
	var config := ConfigScript.new()
	config.network_enabled = false
	config.reconnect_grace_seconds = reconnect_seconds
	config.dynamic_blocking_enabled = dynamic_blocking_enabled
	config.dynamic_blocking_radius = dynamic_blocking_radius
	var server = ServerScript.new()
	var result := server.initialize(config)
	_expect(result.ok, "服务器应加载荣耀版大厅：%s" % result)
	return server


## 验证会话建立、移动意图排序、服务器裁决和快照确认的完整链路。
## Design: 该用例覆盖客户端意图到权威状态的协议边界，客户端坐标从不直接成为最终状态。
func _test_authoritative_movement() -> void:
	var server = _new_server()
	var opened := server.open_session(11, _handshake(), 1000)
	_expect(opened.ok, "合法 peer 应建立临时会话")
	var entity_id: String = opened.value.session.entity_id
	var token: String = opened.value.session.reconnect_token
	_expect(entity_id.begins_with("player.") and not token.is_empty(), "会话应分配业务实体和临时重连令牌")
	var map_instance_id: String = server.map_instance.instance_id
	_expect(
		map_instance_id == "yian_harbor_hall_floor_1.instance.1",
		"地图实例应使用稳定业务 ID",
	)
	var blocked_target := Vector2(960, 900)
	var blocked_contract = MoveIntentContract.new(map_instance_id, blocked_target, 1)
	var blocked_payload: Dictionary = blocked_contract.to_dictionary()
	var restored_intent = MoveIntentContract.from_dictionary(blocked_payload)
	_expect(restored_intent.is_ok, "客户端移动契约应在服务端边界完整 round-trip")
	_expect(
		restored_intent.value.requested_world_point == blocked_target,
		"移动契约 round-trip 不得改变目标点",
	)
	var adjusted := server.handle_peer_move(11, blocked_payload)
	_expect(adjusted.ok, "阻挡目标应被服务端调整到就近可达点：%s" % adjusted)
	_expect(adjusted.value.adjusted, "阻挡目标响应应明确标记 adjusted")
	_expect(
		server.map_instance.navigation.is_walkable(adjusted.value.authoritative_target),
		"服务端回退目标必须可行走",
	)
	var outside_contract = MoveIntentContract.new(map_instance_id, Vector2(99999, -500), 2)
	var outside := server.handle_peer_move(11, outside_contract.to_dictionary())
	_expect(outside.ok and outside.value.adjusted, "地图外目标也应回退到同一连通区")
	_expect(
		server.map_instance.navigation.is_walkable(outside.value.authoritative_target),
		"地图外目标的权威落点必须可行走",
	)
	var stale_contract = MoveIntentContract.new(map_instance_id, Vector2(800, 1200), 2)
	var stale := server.handle_peer_move(11, stale_contract.to_dictionary())
	_expect(not stale.ok and stale.code == ErrorCodes.STALE_SEQUENCE, "旧输入序列必须被拒绝")
	var wrong_map_contract = MoveIntentContract.new("another_map.instance.1", Vector2(800, 1200), 3)
	var wrong_map := server.handle_peer_move(11, wrong_map_contract.to_dictionary())
	_expect(
		not wrong_map.ok and wrong_map.code == ErrorCodes.INVALID_IDENTIFIER,
		"错误地图实例意图必须被拒绝",
	)
	var malformed := server.handle_peer_move(11, {
		"map_instance_id": map_instance_id,
		"requested_world_point": {"x": "not-a-number", "y": 1200},
		"input_sequence": 3,
	})
	_expect(
		not malformed.ok and malformed.code == ErrorCodes.INVALID_FIELD_TYPE,
		"移动输入必须直接执行共享契约校验",
	)
	var entity = server.map_instance.entities[entity_id]
	var server_owned_speed: float = entity.movement_speed
	for forged_field in [&"speed", &"velocity", &"position"]:
		var forged_payload := MoveIntentContract.new(
			map_instance_id, Vector2(800, 1200), 3
		).to_dictionary()
		forged_payload[forged_field] = 99999.0
		var forged := server.handle_peer_move(11, forged_payload)
		_expect(
			not forged.ok and forged.code == ErrorCodes.INVALID_PAYLOAD,
			"服务端必须拒绝客户端伪造字段 %s" % forged_field,
		)
		_expect(
			is_equal_approx(entity.movement_speed, server_owned_speed),
			"伪造字段 %s 不得改变服务端 movement_speed" % forged_field,
		)
	var unknown_entity: Dictionary = server.map_instance.handle_move_intent(
		"player.unknown",
		MoveIntentContract.new(map_instance_id, Vector2(800, 1200), 3).to_dictionary(),
	)
	_expect(
		not unknown_entity.ok and unknown_entity.code == ErrorCodes.INVALID_IDENTIFIER,
		"地图实例必须拒绝未知业务实体",
	)
	var before: Vector2 = entity.position
	server.advance_simulation(1.0, 2000)
	_expect(
		before.distance_to(entity.position) <= server.config.default_movement_speed + 0.01,
		"一秒内权威位移不能超过服务端速度上限",
	)
	server.free()


## 验证默认动态阻挡、目标预约、逐 tick 防穿透及显式关闭策略。
## Design: 静态地图寻路保持原样；动态阻挡只在权威实例层叠加实体脚点占用。
func _test_dynamic_entity_blocking() -> void:
	var blocking_radius := 24.0
	var server = _new_server(30.0, true, blocking_radius)
	var first_opened := server.open_session(41, _handshake(), 1000)
	var second_opened := server.open_session(42, _handshake(), 1000)
	_expect(first_opened.ok and second_opened.ok, "两个 peer 应能在同一地图建立会话")
	var first_id: String = first_opened.value.session.entity_id
	var second_id: String = second_opened.value.session.entity_id
	var first = server.map_instance.entities[first_id]
	var second = server.map_instance.entities[second_id]
	_expect(
		first.position.distance_to(second.position) + 0.001 >= blocking_radius,
		"同点出生的实体应自动分配满足动态阻挡半径的脚点",
	)
	var requested_occupied_position: Vector2 = second.position
	var move_result := server.handle_peer_move(
		41,
		MoveIntentContract.new(
			server.map_instance.instance_id,
			requested_occupied_position,
			1,
		).to_dictionary(),
	)
	_expect(move_result.ok and move_result.value.dynamic_adjusted, "已占用目标必须由服务端动态调整")
	_expect(
		move_result.value.authoritative_target.distance_to(second.position) + 0.001 >= blocking_radius,
		"调整后的目标必须保持配置化脚点间距",
	)
	for tick_index in range(240):
		server.map_instance.simulate(1.0 / 20.0)
		_expect(
			first.position.distance_to(second.position) + 0.001 >= blocking_radius,
			"动态模拟第 %d tick 不得发生脚点重叠或高速穿透" % tick_index,
		)
	server.free()

	var non_blocking_server = _new_server(30.0, false, blocking_radius)
	var non_blocking_opened := non_blocking_server.open_session(51, _handshake(), 1000)
	var non_blocking_first_id: String = non_blocking_opened.value.session.entity_id
	var non_blocking_first = non_blocking_server.map_instance.entities[non_blocking_first_id]
	var overlapping_spawn: Dictionary = non_blocking_server.map_instance.spawn_entity(
		"test.overlapping_entity",
		non_blocking_first.position,
		non_blocking_server.config.default_movement_speed,
	)
	_expect(
		overlapping_spawn.ok
		and overlapping_spawn.value.position.is_equal_approx(non_blocking_first.position),
		"关闭动态阻挡后应保留无实体碰撞的可配置语义",
	)
	non_blocking_server.free()


## 验证断线宽限期内重连、超期实体清理与过期令牌拒绝规则。
## Design: 用显式时间戳驱动会话生命周期，避免测试依赖真实时钟。
func _test_session_reconnect_and_cleanup() -> void:
	var server = _new_server(0.5)
	var opened := server.open_session(21, _handshake(), 1000)
	var entity_id: String = opened.value.session.entity_id
	var token: String = opened.value.session.reconnect_token
	_expect(server.disconnect_session(21, 1100).ok, "断线应进入临时保留期")
	_expect(server.map_instance.entities.has(entity_id), "保留期内角色实体应继续存在")
	var reconnect_request := _handshake()
	reconnect_request["reconnect_token"] = token
	var reconnected := server.open_session(22, reconnect_request, 1400)
	_expect(reconnected.ok and reconnected.value.resumed, "有效令牌应恢复原会话")
	_expect(reconnected.value.session.entity_id == entity_id, "重连不得创建新实体")
	server.disconnect_session(22, 1500)
	server.advance_simulation(0.05, 2001)
	_expect(not server.map_instance.entities.has(entity_id), "重连超时后服务端应清理实体")
	var expired_request := _handshake()
	expired_request["reconnect_token"] = token
	var expired := server.open_session(23, expired_request, 2100)
	_expect(not expired.ok and expired.code == &"invalid_reconnect_token", "已清理令牌不能再次恢复")
	server.free()


## 验证出口距离、入口号、未解析目标、原子迁移和逐地图快照隔离。
## Design: 两张地图均由测试注入且复用已验证导航，不依赖阶段2尚未落地的真实第二张地图文件。
func _test_authoritative_map_transition() -> void:
	var config := ConfigScript.new()
	config.network_enabled = false
	config.dynamic_blocking_enabled = false
	var source: AuthoritativeMapInstance = MapInstanceScript.new()
	var destination: AuthoritativeMapInstance = MapInstanceScript.new()
	_expect(source.load_map(config.map_config_path).ok, "切图夹具源地图应加载")
	_expect(destination.load_map(config.map_config_path).ok, "切图夹具目标地图应加载")
	destination.definition.map_id = &"fixture_destination"
	destination.definition.legacy_codes = PackedStringArray(["fixture_dest_legacy"])
	destination.instance_id = "fixture_destination.instance.1"
	var transition: MapTransition = source.definition.transitions[0]
	transition.destination_map_id = &"fixture_destination"
	transition.destination_legacy_code = ""
	transition.destination_entry_number = 2
	transition.external_target = false
	transition.has_destination_landing_point = true
	transition.destination_landing_point = config.default_spawn
	var injected: Array[AuthoritativeMapInstance] = [source, destination]
	var server = ServerScript.new()
	var initialized := server.initialize(config, injected)
	_expect(initialized.ok, "注入双地图注册表应初始化：%s" % initialized)
	var first_opened := server.open_session(61, _handshake(), 1000)
	var observer_opened := server.open_session(62, _handshake(), 1000)
	_expect(first_opened.ok and observer_opened.ok, "源地图应接纳两个切图测试会话")
	var entity_id: String = first_opened.value.session.entity_id
	var observer_id: String = observer_opened.value.session.entity_id
	var entity: AuthoritativeEntity = source.entities[entity_id]
	entity.last_input_sequence = 44
	entity.facing_index = 6
	entity.state_revision = 8
	transition.approach_point = entity.position + Vector2(500.0, 0.0)
	var too_far := server.handle_peer_map_transition(
		61,
		MapTransitionIntentContract.new(source.instance_id, String(transition.transition_id), 2, 1).to_dictionary(),
	)
	_expect(not too_far.ok and too_far.code == ErrorCodes.MAP_TRANSITION_TOO_FAR, "远离出口必须拒绝切图")
	_expect(source.entities.has(entity_id) and not destination.entities.has(entity_id), "距离拒绝必须保持源地图原子状态")
	transition.approach_point = entity.position
	var wrong_entry := server.handle_peer_map_transition(
		61,
		MapTransitionIntentContract.new(source.instance_id, String(transition.transition_id), 9, 1).to_dictionary(),
	)
	_expect(not wrong_entry.ok and wrong_entry.code == ErrorCodes.MAP_TRANSITION_ENTRY_MISMATCH, "伪造目标入口号必须拒绝")
	var registered_target := transition.destination_map_id
	transition.destination_map_id = &"fixture_missing_target"
	var unresolved := server.handle_peer_map_transition(
		61,
		MapTransitionIntentContract.new(source.instance_id, String(transition.transition_id), 2, 1).to_dictionary(),
	)
	_expect(
		not unresolved.ok and unresolved.code == ErrorCodes.MAP_TRANSITION_TARGET_UNRESOLVED,
		"未注册目标必须返回稳定 target_unresolved 错误码",
	)
	_expect(source.entities.has(entity_id) and not destination.entities.has(entity_id), "未解析目标不得部分移除源实体")
	transition.destination_map_id = registered_target
	var transferred := server.handle_peer_map_transition(
		61,
		MapTransitionIntentContract.new(source.instance_id, String(transition.transition_id), 2, 1).to_dictionary(),
	)
	_expect(transferred.ok, "合法出口应原子迁移：%s" % transferred)
	_expect(not source.entities.has(entity_id) and destination.entities.has(entity_id), "实体只应存在于目标地图")
	var destination_entity: AuthoritativeEntity = destination.entities[entity_id]
	_expect(
		destination_entity.last_input_sequence == 44
		and destination_entity.facing_index == 6
		and destination_entity.state_revision == 9,
		"跨图迁移应保留输入排序与朝向并单调推进状态 revision",
	)
	_expect(server.sessions.session_for_peer(61).map_instance_id == destination.instance_id, "会话当前地图必须随原子提交更新")
	var joined_result = MapJoinedContract.from_dictionary(transferred.value.map_joined)
	_expect(joined_result.is_ok and joined_result.value.entity_id == entity_id, "成功响应必须符合 MapJoined 契约")
	_expect(transferred.value.transition_sequence == 1, "成功响应必须确认切图命令序列")
	var moved_snapshot := server.snapshot_for_peer(61)
	var observer_snapshot := server.snapshot_for_peer(62)
	_expect(_snapshot_has_entity(moved_snapshot, entity_id), "迁移玩家应收到目标地图实体")
	_expect(not _snapshot_has_entity(moved_snapshot, observer_id), "目标地图快照不得泄漏源地图观察者")
	_expect(_snapshot_has_entity(observer_snapshot, observer_id), "源地图观察者仍应收到自身实体")
	_expect(not _snapshot_has_entity(observer_snapshot, entity_id), "源地图快照不得包含已迁移实体")
	var stale := server.handle_peer_map_transition(
		61,
		MapTransitionIntentContract.new(destination.instance_id, "missing_reverse", 0, 1).to_dictionary(),
	)
	_expect(not stale.ok and stale.code == ErrorCodes.STALE_SEQUENCE, "已确认切图序列不得重放")
	var same_map_transition: MapTransition = destination.definition.transitions[0]
	same_map_transition.destination_map_id = destination.definition.map_id
	same_map_transition.destination_legacy_code = ""
	same_map_transition.destination_entry_number = 0
	same_map_transition.external_target = false
	same_map_transition.enabled = true
	same_map_transition.approach_point = destination_entity.position
	var same_map_entity_reference := destination_entity
	var same_map_result := server.handle_peer_map_transition(
		61,
		MapTransitionIntentContract.new(
			destination.instance_id, String(same_map_transition.transition_id), 0, 2
		).to_dictionary(),
	)
	_expect(same_map_result.ok, "同实例传送应直接重定位而不是因重复实体 ID 失败")
	_expect(
		destination.entities[entity_id] == same_map_entity_reference,
		"同实例传送必须复用原权威实体对象",
	)
	server.free()


## 验证固定模拟 tick、快照频率、协议版本拒绝和快照字段契约。
## Design: 通过一次确定性的时间推进同时检查模拟时钟与网络发布节奏。
func _test_fixed_tick_and_snapshot_rate() -> void:
	var server = _new_server()
	server.advance_simulation(0.5, 1000)
	_expect(server.server_tick == 10, "20 Hz 模拟在 0.5 秒应执行 10 tick")
	_expect(server.emitted_snapshot_count == 5, "10 Hz 快照在 0.5 秒应生成 5 次")
	var mismatch := server.open_session(31, {
		"protocol_version": 999,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}, 1100)
	_expect(
		not mismatch.ok and mismatch.code == ErrorCodes.UNSUPPORTED_PROTOCOL_VERSION,
		"协议版本不匹配必须使用共享错误码拒绝",
	)
	var content_mismatch := server.open_session(32, {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION + 1,
	}, 1100)
	_expect(
		not content_mismatch.ok and content_mismatch.code == ErrorCodes.CONTENT_VERSION_MISMATCH,
		"内容版本不匹配必须使用共享错误码拒绝",
	)
	var opened := server.open_session(33, _handshake(), 1100)
	var entity_id: String = opened.value.session.entity_id
	var world_snapshot: Dictionary = server.map_instance.snapshot(10, 0.5)
	_expect(
		world_snapshot.keys().all(func(key): return key in ["server_tick", "server_time_seconds", "entities"]),
		"世界快照只使用统一顶层字段",
	)
	var local_snapshot: Dictionary = world_snapshot.entities[0]
	var restored = EntitySnapshotContract.from_dictionary(local_snapshot)
	_expect(restored.is_ok, "服务端实体快照必须通过共享契约 round-trip：%s" % restored.error_message)
	_expect(restored.value.entity_id == entity_id, "快照应携带业务实体 ID")
	_expect(local_snapshot.has("acknowledged_input_sequence"), "本地实体快照应携带输入确认序号")
	server.free()


## Reports whether [param snapshot] contains an entity matching [param entity_id].
## [param snapshot] Map-scoped world snapshot produced by server authority.
## [param entity_id] Stable entity identifier searched in the snapshot.
## Returns true when exactly the requested entity is visible in this map snapshot.
func _snapshot_has_entity(snapshot: Dictionary, entity_id: String) -> bool:
	for entity: Dictionary in snapshot.get("entities", []):
		if String(entity.get("entity_id", "")) == entity_id:
			return true
	return false


## 构造与当前公开内容版本匹配的客户端握手载荷。
## Returns 可直接提交给服务器会话入口的握手字典。
func _handshake() -> Dictionary:
	return {
		"protocol_version": Protocol.PROTOCOL_VERSION,
		"content_version": Protocol.PUBLIC_CONTENT_VERSION,
	}


## 统计一条断言，并在 [param condition] 失败时记录 [param message]。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
