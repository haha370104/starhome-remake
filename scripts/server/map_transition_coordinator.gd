class_name MapTransitionCoordinator
extends RefCounted

const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const MapTransitionIntentContract := preload("res://scripts/network/contracts/map_transition_intent.gd")
const MapTransitionLandingResolverScript := preload(
	"res://scripts/maps/map_transition_landing_resolver.gd"
)

const MAX_TRANSITION_LANDING_CORRECTION_DISTANCE := 192.0

var _session_for_peer: Callable
var _source_instance_for_id: Callable
var _resolve_destination: Callable
var _player_for: Callable
var _capture_player: Callable
var _commit_player: Callable
var _prepare_loadout: Callable
var _configured := false


## 配置地图迁移所需的会话、地图、持久化和战斗装配端口。
## [param session_for_peer] 按 peer 查询当前权威会话。
## [param source_instance_for_id] 按 instance_id 查询地图实例。
## [param resolve_destination] 解析或惰性加载迁移目标地图。
## [param player_for] 查询在线玩家聚合；持久化关闭时可返回 null。
## [param capture_player] 采集迁移前的地图和战斗瞬时事实。
## [param commit_player] 提交迁移前玩家候选并更新生产跟踪。
## [param prepare_loadout] 为目标地图准备玩家专属战斗装配。
func configure(
	session_for_peer: Callable,
	source_instance_for_id: Callable,
	resolve_destination: Callable,
	player_for: Callable,
	capture_player: Callable,
	commit_player: Callable,
	prepare_loadout: Callable,
) -> DomainResult:
	var ports := [
		session_for_peer,
		source_instance_for_id,
		resolve_destination,
		player_for,
		capture_player,
		commit_player,
		prepare_loadout,
	]
	for port: Callable in ports:
		if not port.is_valid():
			return DomainResult.failure(&"map_transition.invalid_port", "all map transition ports are required")
	_session_for_peer = session_for_peer
	_source_instance_for_id = source_instance_for_id
	_resolve_destination = resolve_destination
	_player_for = player_for
	_capture_player = capture_player
	_commit_player = commit_player
	_prepare_loadout = prepare_loadout
	_configured = true
	return DomainResult.ok(self)


## 验证并原子提交一次权威地图迁移。
## [param peer_id] 真实网络连接身份。
## [param raw_intent] 未信任的客户端迁移意图。
## [param server_tick] 当前权威服务器 tick。
## [param server_time_seconds] 当前权威服务器时间。
## [param transition_radius] 权威出口激活半径。
## [param default_movement_speed] 非战斗地图的默认移动速度。
## [param session_override] 可选的无网络会话；为空时按 peer 查询。
## 返回与原服务器入口兼容的 wire-ready 结果。
func execute(
	peer_id: int,
	raw_intent: Variant,
	server_tick: int,
	server_time_seconds: float,
	transition_radius: float,
	default_movement_speed: float,
	session_override: ServerSession = null,
) -> Dictionary:
	if not _configured:
		return _failure(&"map_transition.coordinator_unavailable", "map transition coordinator is not configured")
	var session: ServerSession = session_override
	if session == null:
		session = _session_for_peer.call(peer_id)
	if session == null:
		return _failure(&"unauthenticated_peer", "open a session before changing maps")
	var intent_result: DomainResult = MapTransitionIntentContract.from_dictionary(raw_intent)
	if not intent_result.is_ok:
		return _failure(intent_result.error_code, intent_result.error_message)
	var intent: MapTransitionIntent = intent_result.value
	if intent.input_sequence <= session.last_transition_sequence:
		return _failure(ErrorCodes.STALE_SEQUENCE, "transition sequence was already acknowledged")
	if intent.map_instance_id != session.map_instance_id:
		return _failure(
			ErrorCodes.MAP_TRANSITION_SOURCE_MISMATCH,
			"transition intent does not target the session's current map",
		)
	var source_instance: AuthoritativeMapInstance = _source_instance_for_id.call(session.map_instance_id)
	if source_instance == null:
		return _failure(ErrorCodes.MAP_TRANSITION_SOURCE_MISMATCH, "source map is unavailable")
	var entity: AuthoritativeEntity = source_instance.entities.get(session.entity_id)
	if entity == null:
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "session entity is absent from source map")
	var transition: MapTransition = source_instance.definition.transition_by_id(
		StringName(intent.transition_id)
	)
	if transition == null:
		return _failure(ErrorCodes.MAP_TRANSITION_UNKNOWN_EXIT, "transition ID is unknown")
	if not transition.enabled:
		return _failure(ErrorCodes.MAP_TRANSITION_DISABLED, "transition is disabled")
	if intent.destination_entry_number != transition.destination_entry_number:
		return _failure(
			ErrorCodes.MAP_TRANSITION_ENTRY_MISMATCH,
			"destination entry number does not match the authoritative transition",
		)
	var exit_point := transition.approach_point
	if exit_point.is_zero_approx():
		exit_point = transition.source_anchor
	if entity.position.distance_to(exit_point) > transition_radius:
		return _failure(
			ErrorCodes.MAP_TRANSITION_TOO_FAR,
			"entity is outside the authoritative exit activation radius",
		)
	var destination_instance: AuthoritativeMapInstance = _resolve_destination.call(
		transition, source_instance.definition.world_id
	)
	if destination_instance == null:
		return _failure(
			ErrorCodes.MAP_TRANSITION_TARGET_UNRESOLVED,
			"transition target is not registered on this server",
		)
	var destination_spawn := _resolve_destination_spawn(
		source_instance, destination_instance, transition
	)
	if not destination_spawn.is_finite():
		return _failure(
			ErrorCodes.MAP_TRANSITION_ENTRY_MISMATCH,
			"destination map does not admit the requested entry number",
		)
	if not destination_instance.navigation.is_walkable(destination_spawn):
		var corrected_spawn: Vector2 = destination_instance.navigation.closest_walkable_position(
			destination_spawn
		)
		if (
			not corrected_spawn.is_finite()
			or corrected_spawn.distance_to(destination_spawn)
				> MAX_TRANSITION_LANDING_CORRECTION_DISTANCE
		):
			return _failure(
				ErrorCodes.MAP_TRANSITION_DESTINATION_BLOCKED,
				"destination entry has no nearby walkable landing point",
			)
		destination_spawn = corrected_spawn
	if destination_instance == source_instance:
		destination_spawn = destination_instance.admitted_spawn_position(
			destination_spawn, StringName(session.entity_id)
		)
		if not destination_spawn.is_finite():
			return _failure(
				ErrorCodes.MAP_TRANSITION_DESTINATION_BLOCKED,
				"same-map destination is occupied by another entity",
			)
	var committed_entity: AuthoritativeEntity
	if destination_instance == source_instance:
		committed_entity = entity
		place_transitioned_entity(committed_entity, destination_instance, destination_spawn)
	else:
		var transition_state: Player = _player_for.call(session.entity_id)
		if transition_state != null:
			var captured_transition: DomainResult = _capture_player.call(transition_state)
			if not captured_transition.is_ok:
				return _failure(captured_transition.error_code, captured_transition.error_message)
			transition_state.production.pause("离开设施地图后生产已暂停")
			var stored_transition: DomainResult = _commit_player.call(
				session.entity_id, transition_state
			)
			if not stored_transition.is_ok:
				return _failure(stored_transition.error_code, stored_transition.error_message)
			var prepared_loadout: Dictionary = _prepare_loadout.call(
				destination_instance, session.entity_id, transition_state
			)
			if not prepared_loadout.ok:
				return prepared_loadout
		var destination_speed := entity.movement_speed \
				if destination_instance.is_vehicle_combat_active() \
				else default_movement_speed
		var destination_spawn_result := destination_instance.spawn_entity(
				session.entity_id, destination_spawn, destination_speed
			)
		if not destination_spawn_result.ok:
			return _failure(
				ErrorCodes.MAP_TRANSITION_DESTINATION_BLOCKED,
				"destination rejected entity spawn: %s" % destination_spawn_result.get("message", ""),
			)
		committed_entity = destination_spawn_result.value
		copy_transitioned_entity_state(entity, committed_entity)
		copy_transitioned_vehicle_state(source_instance, destination_instance, session.entity_id)
		if not source_instance.remove_entity(session.entity_id):
			destination_instance.remove_entity(session.entity_id)
			return _failure(&"map_transition.atomic_commit_failed", "source entity disappeared during commit")
	session.map_instance_id = destination_instance.instance_id
	session.last_transition_sequence = intent.input_sequence
	var player: Player = _player_for.call(session.entity_id)
	if player != null:
		_capture_player.call(player)
	var joined := MapJoinedContract.new(
		String(destination_instance.definition.map_id),
		destination_instance.instance_id,
		session.entity_id,
		committed_entity.position,
		destination_instance.definition.schema_version,
		server_tick,
	)
	return _success({
		"map_joined": joined.to_dictionary(),
		"world_snapshot": destination_instance.world_snapshot(server_tick, server_time_seconds),
		"local_snapshot": destination_instance.local_snapshot_for_actor(
			server_tick, session.entity_id
		),
		"transition_sequence": intent.input_sequence,
	})


## 使用已认证的无网络会话复用同一套权威地图迁移事务。
func execute_for_session(
	session: ServerSession,
	raw_intent: Variant,
	server_tick: int,
	server_time_seconds: float,
	transition_radius: float,
	default_movement_speed: float,
) -> Dictionary:
	return execute(
		-1,
		raw_intent,
		server_tick,
		server_time_seconds,
		transition_radius,
		default_movement_speed,
		session,
	)


## 解析目标地图的权威落点，不接受客户端直接提供的出生坐标。
func _resolve_destination_spawn(
	source_instance: AuthoritativeMapInstance,
	destination_instance: AuthoritativeMapInstance,
	transition: MapTransition,
) -> Vector2:
	if transition.kind == MapTransition.Kind.CLIENT_POINT and transition.has_destination_landing_point:
		return transition.destination_landing_point
	var landing: Dictionary = MapTransitionLandingResolverScript.resolve_landing(
		source_instance.definition,
		transition,
		destination_instance.definition,
	)
	return landing.get("position", Vector2.INF) if not landing.is_empty() else Vector2.INF


## 复制玩家实体的权威输入与表现状态，迁移后从 idle 状态重新开始。
func copy_transitioned_entity_state(
	source: AuthoritativeEntity,
	destination: AuthoritativeEntity,
) -> void:
	destination.sex = source.sex
	destination.last_input_sequence = source.last_input_sequence
	destination.facing_index = source.facing_index
	destination.state_revision = source.state_revision + 1
	destination.action = &"idle"
	destination.path = PackedVector2Array([destination.position])
	destination.path_index = destination.path.size()
	destination.target_position = destination.position


## 复制跨地图迁移时服务器拥有的战车资源状态。
func copy_transitioned_vehicle_state(
	source_instance: AuthoritativeMapInstance,
	destination_instance: AuthoritativeMapInstance,
	entity_id: String,
) -> void:
	var source_state := source_instance.vehicle_combat_state_for(entity_id)
	var destination_state := destination_instance.vehicle_combat_state_for(entity_id)
	if source_state == null or destination_state == null:
		return
	destination_state.health = clampi(source_state.health, 0, destination_state.max_health)
	destination_state.reserve_energy = clampf(
		source_state.reserve_energy, 0.0, destination_state.reserve_energy_capacity
	)
	destination_state.working_energy = clampf(
		source_state.working_energy, 0.0, destination_state.working_energy_capacity
	)


## 将同一地图迁移的实体重新放置到权威落点并清理旧路径。
func place_transitioned_entity(
	entity: AuthoritativeEntity,
	destination_instance: AuthoritativeMapInstance,
	spawn_position: Vector2,
) -> void:
	entity.map_instance_id = destination_instance.instance_id
	entity.position = spawn_position
	entity.target_position = spawn_position
	entity.path = PackedVector2Array([spawn_position])
	entity.path_index = entity.path.size()
	entity.action = &"idle"
	entity.state_revision += 1
	destination_instance.refresh_dynamic_entity_position(entity.entity_id)


func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
