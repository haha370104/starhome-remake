class_name AuthoritativeServer
extends Node

const ConfigScript := preload("res://scripts/server/server_config.gd")
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const MapRegistryScript := preload("res://scripts/server/authoritative_map_registry.gd")
const SessionRegistryScript := preload("res://scripts/server/session_registry.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const MapTransitionIntentContract := preload("res://scripts/network/contracts/map_transition_intent.gd")
const VehicleRecoveryIntentContract := preload(
	"res://scripts/network/contracts/vehicle_recovery_intent.gd"
)
const TransportEndpointScript := preload("res://scripts/network/transport/network_transport_endpoint.gd")
const CombatCatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const FilePlayerStateRepositoryScript := preload("res://scripts/server/persistence/file_player_state_repository.gd")
const AutosaveServiceScript := preload("res://scripts/server/persistence/authoritative_autosave_service.gd")
const PlayerPanelServiceScript := preload("res://scripts/server/player_panels/authoritative_player_panel_service.gd")
const DomainResultScript := preload("res://scripts/core/domain_result.gd")

signal snapshot_generated(snapshot: Dictionary)
signal command_rejected(peer_id: int, code: StringName)
signal server_message_generated(peer_id: int, message: Dictionary)
signal peer_snapshot_generated(peer_id: int, snapshot: Dictionary)

const TRANSPORT_SESSION_REQUEST := &"session_request"
const TRANSPORT_PLAYER_PANEL_COMMAND := &"player_panel_command"
const BASE_HALL_MAP_ID := "yian_harbor_hall_floor_1"
const VEHICLE_RECOVERY_DELAY_SECONDS := 3.0
const VEHICLE_RECOVERY_HEALTH_RATIO := 0.10

var config: DedicatedServerConfig
var map_instance: AuthoritativeMapInstance
var map_registry: AuthoritativeMapRegistry
var sessions: SessionRegistry
var server_tick := 0
var emitted_snapshot_count := 0
var _simulation_accumulator := 0.0
var _ticks_per_snapshot := 2
var _next_entity_number := 1
var _network_started := false
var _transport_endpoint: NetworkTransportEndpoint
var _combat_catalog
var player_state_repository: PlayerStateRepository
var autosave_service: AuthoritativeAutosaveService
var player_panel_service: AuthoritativePlayerPanelService
var _pending_vehicle_recoveries: Dictionary = {}


## 节点进入场景树后初始化运行依赖。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _ready() -> void:
	if config == null:
		config = ConfigScript.from_command_line(OS.get_cmdline_user_args())
	var result := initialize(config)
	if not result.ok:
		push_error("Dedicated server initialization failed [%s]: %s" % [result.code, result.message])
		get_tree().quit(1)
		return
	if config.network_enabled:
		var network_result := start_network()
		if not network_result.ok:
			push_error("Dedicated server network failed [%s]: %s" % [
				network_result.code, network_result.message,
			])
			get_tree().quit(1)
			return
	print(
		"STARHOME_SERVER_READY protocol=%d content=%s simulation=%dHz snapshot=%dHz address=%s port=%d"
		% [
			config.protocol_version,
			config.content_version,
			config.simulation_hz,
			config.snapshot_hz,
			config.listen_address,
			config.port,
		]
	)
	if config.smoke_test:
		call_deferred("_finish_smoke_test")


## 配置并初始化 `initialize` 对应的模块状态。
## [param requested_config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param injected_map_instances] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param injected_repository] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func initialize(
	requested_config: DedicatedServerConfig,
	injected_map_instances: Array[AuthoritativeMapInstance] = [],
	injected_repository: PlayerStateRepository = null,
) -> Dictionary:
	config = requested_config
	var errors := config.validation_errors()
	if not errors.is_empty():
		return _failure(&"invalid_server_config", "; ".join(errors))
	map_registry = MapRegistryScript.new()
	var combat_catalog_result = CombatCatalogScript.load_default()
	if not combat_catalog_result.is_ok:
		return _failure(combat_catalog_result.error_code, combat_catalog_result.error_message)
	_combat_catalog = combat_catalog_result.value
	if injected_map_instances.is_empty():
		var load_result := _load_configured_map_instances()
		if not load_result.ok:
			return load_result
	else:
		for injected_instance: AuthoritativeMapInstance in injected_map_instances:
			_configure_map_instance(injected_instance)
			var registration := map_registry.register_instance(injected_instance)
			if not registration.ok:
				return registration
		map_instance = injected_map_instances[0]
	sessions = SessionRegistryScript.new()
	sessions.configure(config.reconnect_grace_seconds)
	_pending_vehicle_recoveries.clear()
	var persistence_result := _initialize_persistence(injected_repository)
	if not persistence_result.ok:
		return persistence_result
	player_panel_service = PlayerPanelServiceScript.new()
	var panel_result = player_panel_service.initialize()
	if not panel_result.is_ok:
		return _failure(panel_result.error_code, panel_result.error_message)
	_ticks_per_snapshot = config.simulation_hz / config.snapshot_hz
	return _success(map_instance.definition.map_id)


## 执行 `start_network` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func start_network() -> Dictionary:
	if _network_started:
		return _failure(&"network_already_started", "ENet server is already listening")
	_ensure_transport_endpoint()
	var error := _transport_endpoint.start_server(
		config.listen_address, config.port, config.max_clients
	)
	if error != OK:
		return _failure(&"enet_listen_failed", error_string(error))
	_network_started = true
	return _success(config.port)


## 执行 `stop_network` 对应的模块操作。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func stop_network() -> void:
	_save_all_persistent_players()
	if not _network_started:
		return
	_transport_endpoint.close()
	_network_started = false


## 执行 `ensure_transport_endpoint` 对应的模块操作。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _ensure_transport_endpoint() -> void:
	if _transport_endpoint != null:
		return
	var existing := get_tree().root.get_node_or_null(TransportEndpointScript.ROOT_NODE_NAME)
	if existing != null:
		_transport_endpoint = existing
	else:
		_transport_endpoint = TransportEndpointScript.new()
		_transport_endpoint.name = TransportEndpointScript.ROOT_NODE_NAME
		get_tree().root.add_child(_transport_endpoint)
	_transport_endpoint.session_request_received.connect(_on_transport_session_request)
	_transport_endpoint.move_intent_received.connect(_on_transport_move_intent)
	_transport_endpoint.map_transition_intent_received.connect(_on_transport_map_transition_intent)
	_transport_endpoint.use_ability_intent_received.connect(_on_transport_use_ability_intent)
	_transport_endpoint.vehicle_recovery_intent_received.connect(
		_on_transport_vehicle_recovery_intent
	)
	_transport_endpoint.pickup_loot_intent_received.connect(_on_transport_pickup_loot_intent)
	_transport_endpoint.player_panel_command_received.connect(_on_transport_player_panel_command)
	_transport_endpoint.peer_disconnected.connect(_on_peer_disconnected)


## 按物理帧推进当前节点的确定性状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _physics_process(delta: float) -> void:
	advance_simulation(delta, Time.get_ticks_msec())


## 推进并更新 `advance_simulation` 对应的模块状态。
## [param elapsed_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func advance_simulation(elapsed_seconds: float, now_msec := -1) -> void:
	if map_instance == null or elapsed_seconds <= 0.0:
		return
	_simulation_accumulator += elapsed_seconds
	var fixed_delta := 1.0 / float(config.simulation_hz)
	while _simulation_accumulator + 0.000001 >= fixed_delta:
		_simulation_accumulator -= fixed_delta
		server_tick += 1
		for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
			registered_instance.simulate(fixed_delta)
			for progression_event: Dictionary in registered_instance.drain_skill_progression_events():
				_apply_skill_progression_event(progression_event)
		_complete_due_vehicle_recoveries()
		if server_tick % _ticks_per_snapshot == 0:
			_emit_snapshot()
	if autosave_service != null:
		var autosave_result := autosave_service.advance(
			elapsed_seconds,
			Callable(self, "_capture_persistent_player_state"),
		)
		if not autosave_result.is_ok:
			push_error("Authoritative autosave failed [%s]: %s" % [
				autosave_result.error_code, autosave_result.error_message,
			])
	var cleanup_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	if autosave_service != null:
		for expiring_session: ServerSession in sessions.all_sessions():
			if (
				not expiring_session.has_active_peer()
				and expiring_session.expires_at_msec >= 0
				and cleanup_time > expiring_session.expires_at_msec
			):
				autosave_service.save_player(
					expiring_session.entity_id,
					Callable(self, "_capture_persistent_player_state"),
				)
	for entity_id in sessions.cleanup_expired(cleanup_time):
		if autosave_service != null:
			autosave_service.unregister_player(entity_id)
		_remove_entity_from_registered_map(entity_id)


## 执行 `open_session` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param request] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func open_session(peer_id: int, request: Dictionary, now_msec := -1) -> Dictionary:
	if map_instance == null:
		return _failure(&"server_not_initialized", "server has no active map")
	var version_result = Protocol.validate_versions(
		int(request.get("protocol_version", -1)),
		int(request.get("content_version", -1)),
	)
	if not version_result.is_ok:
		return _failure(version_result.error_code, version_result.error_message)
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	var reconnect_token := String(request.get("reconnect_token", ""))
	if not reconnect_token.is_empty():
		var reconnect_result := sessions.reconnect(peer_id, reconnect_token, current_time)
		if not reconnect_result.ok:
			return reconnect_result
		return _session_response(reconnect_result.value, true)
	var entity_id := "player.%d" % _next_entity_number
	_next_entity_number += 1
	var spawn_result := map_instance.spawn_entity(
		entity_id, config.default_spawn, config.default_movement_speed
	)
	if not spawn_result.ok:
		return spawn_result
	var persistence_state_result = _register_persistent_player(
		spawn_result.value,
		map_instance,
	)
	if not persistence_state_result.is_ok:
		map_instance.remove_entity(entity_id)
		return _failure(persistence_state_result.error_code, persistence_state_result.error_message)
	var session_result := sessions.create(peer_id, entity_id, current_time)
	if not session_result.ok:
		map_instance.remove_entity(entity_id)
		if autosave_service != null:
			autosave_service.unregister_player(entity_id)
		return session_result
	session_result.value.map_instance_id = map_instance.instance_id
	if persistence_state_result.value is PlayerStateRecord:
		_restore_persistent_player_state(session_result.value, persistence_state_result.value)
	return _session_response(session_result.value, false)


## 执行 `disconnect_session` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func disconnect_session(peer_id: int, now_msec := -1) -> Dictionary:
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return sessions.mark_disconnected(peer_id, current_time)


## 校验并处理 `handle_peer_move` 对应的模块状态。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func handle_peer_move(peer_id: int, intent: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"unauthenticated_peer", "open a session before sending movement")
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		return _failure(&"session_map_unavailable", "session map is not registered")
	var result := current_instance.handle_move_intent(session.entity_id, intent)
	if not result.ok:
		command_rejected.emit(peer_id, result.code)
	return result


## 执行 `handle_peer_use_ability` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func handle_peer_use_ability(peer_id: int, intent: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"unauthenticated_peer", "open a session before using abilities")
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		return _failure(&"session_map_unavailable", "session map is not registered")
	var authoritative_context: Dictionary = {}
	if String(intent.get("ability_id", "")) == AuthoritativeCombatModule.SELF_REPAIR_ABILITY_ID:
		if autosave_service == null:
			return _failure(&"combat.persistence_required", "self-repair requires authoritative player state")
		var current := autosave_service.state_for(session.entity_id)
		if current == null:
			return _failure(&"combat.player_state_missing", "self-repair player state is unavailable")
		var repair_state: Variant = current.character_skills.get("repair", {})
		if not repair_state is Dictionary:
			return _failure(&"combat.repair_skill_missing", "repair skill state is invalid")
		authoritative_context["repair_skill_level"] = maxi(0, int(repair_state.get("level", 0)))
	var result: Dictionary = current_instance.handle_use_ability(
		session.entity_id, intent, authoritative_context
	)
	if not result.ok:
		command_rejected.emit(peer_id, result.code)
	return result


## 执行 `handle_peer_map_transition` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param raw_intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func handle_peer_map_transition(peer_id: int, raw_intent: Variant) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"unauthenticated_peer", "open a session before changing maps")
	var intent_result = MapTransitionIntentContract.from_dictionary(raw_intent)
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
	var source_instance := map_registry.instance_by_id(session.map_instance_id)
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
	if entity.position.distance_to(exit_point) > config.map_transition_radius:
		return _failure(
			ErrorCodes.MAP_TRANSITION_TOO_FAR,
			"entity is outside the authoritative exit activation radius",
		)
	var destination_instance := map_registry.resolve_transition_target(transition)
	if destination_instance == null:
		return _failure(
			ErrorCodes.MAP_TRANSITION_TARGET_UNRESOLVED,
			"transition target is not registered on this server",
		)
	var destination_spawn := Vector2.INF
	if transition.kind == MapTransition.Kind.CLIENT_POINT and transition.has_destination_landing_point:
		destination_spawn = transition.destination_landing_point
	else:
		var destination_entry: MapSpawnPoint = destination_instance.definition.spawn_for_entry(
			transition.destination_entry_number
		)
		if destination_entry == null:
			return _failure(
				ErrorCodes.MAP_TRANSITION_ENTRY_MISMATCH,
				"destination map does not admit the requested entry number",
			)
		destination_spawn = destination_entry.position
	if not destination_instance.navigation.is_walkable(destination_spawn):
		return _failure(
			ErrorCodes.MAP_TRANSITION_DESTINATION_BLOCKED,
			"destination entry landing point is not walkable",
		)
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
		_place_transitioned_entity(committed_entity, destination_instance, destination_spawn)
	else:
		var destination_spawn_result := destination_instance.spawn_entity(
			session.entity_id, destination_spawn, entity.movement_speed
		)
		if not destination_spawn_result.ok:
			return _failure(
				ErrorCodes.MAP_TRANSITION_DESTINATION_BLOCKED,
				"destination rejected entity spawn: %s" % destination_spawn_result.get("message", ""),
			)
		committed_entity = destination_spawn_result.value
		_copy_transitioned_entity_state(entity, committed_entity)
		_copy_transitioned_vehicle_state(source_instance, destination_instance, session.entity_id)
		if not source_instance.remove_entity(session.entity_id):
			destination_instance.remove_entity(session.entity_id)
			return _failure(&"map_transition.atomic_commit_failed", "source entity disappeared during commit")
	session.map_instance_id = destination_instance.instance_id
	session.last_transition_sequence = intent.input_sequence
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
		"snapshot": destination_instance.snapshot_for_actor(
			server_tick, float(server_tick) / float(config.simulation_hz)
			, session.entity_id
		),
		"transition_sequence": intent.input_sequence,
	})


## 校验战车确已击毁，并由权威时钟预约三秒后的基地救援。
func handle_peer_vehicle_recovery(peer_id: int, raw_intent: Variant) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"vehicle_recovery.session_missing", "peer has no active session")
	var intent_result = VehicleRecoveryIntentContract.from_dictionary(raw_intent)
	if not intent_result.is_ok:
		return _failure(intent_result.error_code, intent_result.error_message)
	var intent = intent_result.value
	if intent.input_sequence <= session.last_recovery_sequence:
		return _failure(ErrorCodes.STALE_SEQUENCE, "recovery sequence was already acknowledged")
	if intent.map_instance_id != session.map_instance_id:
		return _failure(&"vehicle_recovery.map_mismatch", "recovery targets another map")
	if intent.action != VehicleRecoveryIntentContract.RETURN_TO_BASE:
		return _failure(&"vehicle_recovery.invalid_action", "unsupported recovery action")
	if _pending_vehicle_recoveries.has(session.entity_id):
		return _failure(&"vehicle_recovery.already_pending", "base rescue is already pending")
	var source := map_registry.instance_by_id(session.map_instance_id)
	if source == null or not source.is_vehicle_combat_active():
		return _failure(
			&"vehicle_recovery.not_in_combat", "vehicle recovery is only available on combat maps"
		)
	var vehicle_state := source.vehicle_combat_state_for(session.entity_id) if source != null else null
	if vehicle_state == null or vehicle_state.health > 0:
		return _failure(&"vehicle_recovery.not_destroyed", "only a destroyed vehicle may return")
	session.last_recovery_sequence = intent.input_sequence
	var complete_at_tick := server_tick + maxi(
		1, roundi(VEHICLE_RECOVERY_DELAY_SECONDS * float(config.simulation_hz))
	)
	_pending_vehicle_recoveries[session.entity_id] = {
		"peer_id": peer_id,
		"source_instance_id": session.map_instance_id,
		"complete_at_tick": complete_at_tick,
		"input_sequence": intent.input_sequence,
	}
	return _success({
		"event_type": &"vehicle_recovery_scheduled",
		"server_tick": server_tick,
		"complete_at_tick": complete_at_tick,
		"delay_seconds": VEHICLE_RECOVERY_DELAY_SECONDS,
		"input_sequence": intent.input_sequence,
	})


## 完成到期救援；传送、出生点和 10% 生命均由服务器确定。
func _complete_due_vehicle_recoveries() -> void:
	var entity_ids := _pending_vehicle_recoveries.keys()
	entity_ids.sort()
	for entity_id: String in entity_ids:
		var pending: Dictionary = _pending_vehicle_recoveries[entity_id]
		if server_tick < int(pending["complete_at_tick"]):
			continue
		_pending_vehicle_recoveries.erase(entity_id)
		var result := _recover_destroyed_vehicle_to_base(entity_id, pending)
		_send_reliable(int(pending["peer_id"]), {
			"type": "vehicle_recovery_completed" if result.ok else "command_rejected",
			"result": _wire_result(result),
		})


## 原子地把击毁实体迁移到大厅一层，并把新实例生命设置为最大值的 10%。
func _recover_destroyed_vehicle_to_base(entity_id: String, pending: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_entity(entity_id)
	if session == null or session.map_instance_id != String(pending["source_instance_id"]):
		return _failure(&"vehicle_recovery.session_changed", "session changed during rescue")
	var source := map_registry.instance_by_id(session.map_instance_id)
	var destination := map_registry.instance_by_map_id(BASE_HALL_MAP_ID)
	var source_entity: AuthoritativeEntity = source.entities.get(entity_id) if source != null else null
	var source_vehicle := source.vehicle_combat_state_for(entity_id) if source != null else null
	if source_entity == null or source_vehicle == null or source_vehicle.health > 0:
		return _failure(&"vehicle_recovery.no_longer_destroyed", "vehicle is no longer destroyed")
	if destination == null:
		return _failure(&"vehicle_recovery.base_unavailable", "base hall is unavailable")
	var spawn_point: MapSpawnPoint = destination.definition.spawn_by_id(
		destination.definition.default_spawn_id
	)
	if spawn_point == null:
		return _failure(&"vehicle_recovery.spawn_unavailable", "base spawn is unavailable")
	var spawn_position := destination.admitted_spawn_position(
		spawn_point.position, StringName(entity_id) if destination == source else &""
	)
	if not spawn_position.is_finite():
		return _failure(&"vehicle_recovery.spawn_blocked", "base spawn is blocked")
	var recovered_entity := source_entity
	if destination == source:
		_place_transitioned_entity(recovered_entity, destination, spawn_position)
	else:
		var spawned := destination.spawn_entity(
			entity_id, spawn_position, source_entity.movement_speed
		)
		if not spawned.ok:
			return _failure(&"vehicle_recovery.spawn_blocked", "base rejected rescue spawn")
		recovered_entity = spawned.value
		_copy_transitioned_entity_state(source_entity, recovered_entity)
		_copy_transitioned_vehicle_state(source, destination, entity_id)
		if not source.remove_entity(entity_id):
			destination.remove_entity(entity_id)
			return _failure(&"vehicle_recovery.atomic_commit_failed", "source entity disappeared")
		session.map_instance_id = destination.instance_id
	var recovered_vehicle := destination.vehicle_combat_state_for(entity_id)
	if recovered_vehicle == null:
		return _failure(&"vehicle_recovery.combat_state_missing", "base vehicle state is missing")
	recovered_vehicle.health = maxi(
		1, ceili(float(recovered_vehicle.max_health) * VEHICLE_RECOVERY_HEALTH_RATIO)
	)
	var joined := MapJoinedContract.new(
		String(destination.definition.map_id), destination.instance_id, entity_id,
		recovered_entity.position, destination.definition.schema_version, server_tick,
	)
	return _success({
		"map_joined": joined.to_dictionary(),
		"snapshot": destination.snapshot_for_actor(
			server_tick, float(server_tick) / float(config.simulation_hz), entity_id
		),
		"recovered_health": recovered_vehicle.health,
		"input_sequence": int(pending["input_sequence"]),
	})


## 执行 `snapshot_for_peer` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot_for_peer(peer_id: int) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return {}
	var session_map := map_registry.instance_by_id(session.map_instance_id)
	if session_map == null:
		return {}
	return session_map.snapshot_for_actor(
		server_tick, float(server_tick) / float(config.simulation_hz), session.entity_id
	)


## 处理绑定到 peer 会话的人物、背包与战车面板命令。
## [param peer_id] 由传输层提供的不可伪造 peer 标识。
## [param command] 客户端面板操作意图。
## 返回包含同一事务 revision 的三面板权威快照或拒绝原因。
## 设计：角色身份只取自会话；变更由领域服务校验后一次性提交完整玩家聚合。
func handle_peer_player_panel_command(peer_id: int, command: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"panels.session_missing", "peer has no active authoritative session")
	if autosave_service == null or player_panel_service == null:
		return _failure(&"panels.persistence_required", "player panels require authoritative persistence")
	var current := autosave_service.state_for(session.entity_id)
	if current == null:
		return _failure(&"panels.state_missing", "authoritative player state is not registered")
	var executed = player_panel_service.execute(current, command)
	if not executed.is_ok:
		return _failure(executed.error_code, executed.error_message)
	var value: Dictionary = executed.value
	if not bool(value.get("changed", false)):
		return _success(value["panel_bundle"])
	var committed = autosave_service.commit_player_state(session.entity_id, value["candidate"])
	if not committed.is_ok:
		return _failure(committed.error_code, committed.error_message)
	return _success(player_panel_service.build_bundle(committed.value))


## 应用地图实例产出的权威技能成长事件，并按升级语义选择即时提交或自动存档。
## [param progression_event] 含玩家实体、技能、来源及客观结算值的内部事件。
## 设计：普通进度写入三秒自动存档内存；技能升级立即落盘并同步综合等级。
func _apply_skill_progression_event(progression_event: Dictionary) -> void:
	if autosave_service == null or player_panel_service == null:
		return
	var entity_id := String(progression_event.get("entity_id", ""))
	if entity_id.is_empty():
		return
	var current := autosave_service.state_for(entity_id)
	if current == null:
		return
	var granted := player_panel_service.grant_skill_progression(current, progression_event)
	if not granted.is_ok:
		if granted.error_code != &"progression.no_experience":
			push_warning("Skill progression rejected [%s]: %s" % [
				granted.error_code, granted.error_message,
			])
		return
	var value: Dictionary = granted.value
	var progression: Dictionary = value["progression"]
	var stored := autosave_service.commit_player_state(entity_id, value["candidate"]) \
		if bool(progression.get("upgraded", false)) \
		else autosave_service.update_runtime_state(entity_id, value["candidate"])
	if not stored.is_ok:
		push_error("Skill progression persistence failed [%s]: %s" % [
			stored.error_code, stored.error_message,
		])
		return
	var session: ServerSession = sessions.session_for_entity(entity_id)
	if bool(progression.get("upgraded", false)) and session != null and session.has_active_peer():
		_send_reliable(session.peer_id, {
			"type": "skill_level_up",
			"result": _wire_result(_success({
				"skill_id": String(progression.get("skill_id", "")),
				"new_level": int(progression.get("new_level", 0)),
			})),
		})
	if bool(progression.get("visible_progress_changed", false)):
		if session != null and session.has_active_peer():
			_send_reliable(session.peer_id, {
				"type": "player_panels",
				"result": _wire_result(_success(player_panel_service.build_bundle(stored.value))),
			})


## 处理玩家对地面掉落物的拾取请求并原子写入持久化背包。
## [param peer_id] 由传输层提供的不可伪造 peer 标识。
## [param intent] 仅包含 loot_id 的客户端意图。
## 返回拾取事件与更新后的面板快照，或身份、距离、容量和持久化错误。
## 设计：先预检地面实体，再提交背包，最后移除掉落；服务器主线程保证两阶段期间无并发插入。
func handle_peer_loot_pickup(peer_id: int, intent: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"loot.session_missing", "peer has no active authoritative session")
	if autosave_service == null or player_panel_service == null:
		return _failure(&"loot.persistence_required", "loot pickup requires authoritative persistence")
	var loot_id := String(intent.get("loot_id", ""))
	if loot_id.is_empty() or intent.size() != 1:
		return _failure(&"loot.invalid_payload", "loot pickup intent must contain only loot_id")
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		return _failure(&"loot.map_unavailable", "session map instance is unavailable")
	var prepared := current_instance.prepare_loot_pickup(session.entity_id, loot_id)
	if not prepared.is_ok:
		return _failure(prepared.error_code, prepared.error_message)
	var current := autosave_service.state_for(session.entity_id)
	if current == null:
		return _failure(&"loot.state_missing", "authoritative player state is not registered")
	var granted := player_panel_service.grant_loot(current, prepared.value)
	if not granted.is_ok:
		return _failure(granted.error_code, granted.error_message)
	var grant_value: Dictionary = granted.value
	var committed := autosave_service.commit_player_state(
		session.entity_id, grant_value["candidate"]
	)
	if not committed.is_ok:
		return _failure(committed.error_code, committed.error_message)
	var pickup := current_instance.commit_loot_pickup(session.entity_id, loot_id)
	if not pickup.is_ok:
		return _failure(pickup.error_code, pickup.error_message)
	return _success({
		"loot_event": pickup.value,
		"panel_bundle": player_panel_service.build_bundle(committed.value),
	})


## 通过唯一入口分派来自任意传输实现的客户端命令。
## [param peer_id] 由 ENet 或进程内传输提供、客户端无法伪造的会话标识。
## [param command_type] 会话、移动、切图、能力、拾取或面板命令类型。
## [param payload] 已跨过传输复制边界但仍不可信的客户端载荷。
## 设计：传输实现只能改变数据如何抵达，不能选择不同的业务处理器或返回格式。
func dispatch_transport_command(
	peer_id: int,
	command_type: StringName,
	payload: Dictionary,
) -> void:
	match command_type:
		TRANSPORT_SESSION_REQUEST:
			var result := open_session(peer_id, payload)
			_send_reliable(peer_id, {
				"type": "session_opened" if result.ok else "command_rejected",
				"result": _wire_result(result),
			})
		Protocol.MOVE_INTENT:
			var result := handle_peer_move(peer_id, payload)
			if not result.ok:
				_send_reliable(peer_id, {
					"type": "command_rejected", "result": _wire_result(result),
				})
		Protocol.USE_ABILITY_INTENT:
			var result := handle_peer_use_ability(peer_id, payload)
			_send_reliable(peer_id, {
				"type": "combat_event" if result.ok else "command_rejected",
				"result": _wire_result(result),
			})
		Protocol.PICKUP_LOOT_INTENT:
			var result := handle_peer_loot_pickup(peer_id, payload)
			_send_reliable(peer_id, {
				"type": "loot_picked_up" if result.ok else "command_rejected",
				"result": _wire_result(result),
			})
		Protocol.VEHICLE_RECOVERY_INTENT:
			var result := handle_peer_vehicle_recovery(peer_id, payload)
			if result.ok:
				_send_reliable(peer_id, {
					"type": "vehicle_recovery_scheduled", "result": _wire_result(result),
				})
				return
			var wire_result := _wire_result(result)
			wire_result["value"] = {
				"command_type": String(Protocol.VEHICLE_RECOVERY_INTENT),
				"input_sequence": int(payload.get("input_sequence", -1)),
			}
			_send_reliable(peer_id, {"type": "command_rejected", "result": wire_result})
		TRANSPORT_PLAYER_PANEL_COMMAND:
			var result := handle_peer_player_panel_command(peer_id, payload)
			_send_reliable(peer_id, {
				"type": "player_panels" if result.ok else "command_rejected",
				"result": _wire_result(result),
			})
		Protocol.MAP_TRANSITION_INTENT:
			var result := handle_peer_map_transition(peer_id, payload)
			if result.ok:
				_send_reliable(peer_id, {
					"type": "map_joined", "result": _wire_result(result),
				})
				return
			var wire_result := _wire_result(result)
			wire_result["value"] = {
				"command_type": String(Protocol.MAP_TRANSITION_INTENT),
				"transition_sequence": int(payload.get("input_sequence", -1)),
			}
			_send_reliable(peer_id, {"type": "command_rejected", "result": wire_result})
		_:
			_send_reliable(peer_id, {
				"type": "command_rejected",
				"result": _wire_result(_failure(
					&"network.unsupported_command",
					"transport command type is not supported",
				)),
			})


## 处理 `_on_peer_disconnected` 对应的信号回调。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _on_peer_disconnected(peer_id: int) -> void:
	disconnect_session(peer_id)


## 处理 `_on_transport_session_request` 对应的信号回调。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param request] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_transport_session_request(peer_id: int, request: Dictionary) -> void:
	dispatch_transport_command(peer_id, TRANSPORT_SESSION_REQUEST, request)


## 处理 `_on_transport_move_intent` 对应的信号回调。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_transport_move_intent(peer_id: int, intent: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.MOVE_INTENT, intent)


## 处理 `_on_transport_use_ability_intent` 对应的信号回调。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _on_transport_use_ability_intent(peer_id: int, intent: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.USE_ABILITY_INTENT, intent)


## 将战车恢复意图交给统一权威命令分派器。
func _on_transport_vehicle_recovery_intent(peer_id: int, intent: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.VEHICLE_RECOVERY_INTENT, intent)


## 处理可靠通道收到的地面掉落拾取意图。
## [param peer_id] 发送命令的远端 peer。
## [param intent] 仅含 loot_id 的拾取目标。
func _on_transport_pickup_loot_intent(peer_id: int, intent: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.PICKUP_LOOT_INTENT, intent)


## 处理可靠通道收到的面板命令并回传完整权威快照。
## [param peer_id] 发送命令的远端 peer。
## [param command] 客户端面板操作意图。
func _on_transport_player_panel_command(peer_id: int, command: Dictionary) -> void:
	dispatch_transport_command(peer_id, TRANSPORT_PLAYER_PANEL_COMMAND, command)


## 处理 `_on_transport_map_transition_intent` 对应的信号回调。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _on_transport_map_transition_intent(peer_id: int, intent: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.MAP_TRANSITION_INTENT, intent)


## 发布 `emit_snapshot` 对应的模块状态。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _emit_snapshot() -> void:
	emitted_snapshot_count += 1
	for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
		var snapshot := registered_instance.snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		)
		snapshot_generated.emit(snapshot)
	for session: ServerSession in sessions.active_sessions():
		var session_snapshot := snapshot_for_peer(session.peer_id)
		if not session_snapshot.is_empty():
			peer_snapshot_generated.emit(session.peer_id, session_snapshot.duplicate(true))
			if _network_started:
				_transport_endpoint.send_world_snapshot(session.peer_id, session_snapshot)


## 执行 `send_reliable` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _send_reliable(peer_id: int, message: Dictionary) -> void:
	if peer_id > 0:
		server_message_generated.emit(peer_id, message.duplicate(true))
	if _network_started and peer_id > 0:
		_transport_endpoint.send_server_message(peer_id, message)


## 执行 `session_response` 对应的模块操作。
## [param session] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param resumed] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _session_response(session: ServerSession, resumed: bool) -> Dictionary:
	var session_map := map_registry.instance_by_id(session.map_instance_id)
	if session_map == null:
		return _failure(&"session_map_unavailable", "session map is not registered")
	var entity: AuthoritativeEntity = session_map.entities.get(session.entity_id)
	if entity == null:
		return _failure(&"session_entity_unavailable", "session entity is absent from its map")
	var joined := MapJoinedContract.new(
		String(session_map.definition.map_id),
		session_map.instance_id,
		session.entity_id,
		entity.position,
		session_map.definition.schema_version,
		server_tick,
	)
	return _success({
		"session": session.snapshot(),
		"resumed": resumed,
		"map_joined": joined.to_dictionary(),
		"snapshot": session_map.snapshot_for_actor(
			server_tick, float(server_tick) / float(config.simulation_hz), session.entity_id
		),
	})


## 执行 `wire_result` 对应的模块操作。
## [param result] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _wire_result(result: Dictionary) -> Dictionary:
	var wire := result.duplicate(true)
	wire["code"] = String(result.get("code", &"unknown"))
	# Internal RefCounted instances are never serialized over the wire.
	if wire.get("value") is RefCounted:
		wire.erase("value")
	return wire


## 执行 `finish_smoke_test` 对应的模块操作。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _finish_smoke_test() -> void:
	print("STARHOME_SERVER_SMOKE_OK")
	stop_network()
	get_tree().quit(0)


## 初始化可注入仓储，并建立配置化的权威自动存档服务。
## [param injected_repository] 测试或部署注入的仓储；为空时使用配置指定的文件替身。
## 返回该函数计算、查询或操作得到的结果。
## 设计：服务器应用层拥有定时和状态采集，仓储实现只承担事务化存储。
func _initialize_persistence(injected_repository: PlayerStateRepository) -> Dictionary:
	player_state_repository = null
	autosave_service = null
	if not config.persistence_enabled:
		return _success(false)
	player_state_repository = injected_repository
	if player_state_repository == null:
		player_state_repository = FilePlayerStateRepositoryScript.new(
			config.player_state_store_path
		)
	var repository_result = player_state_repository.initialize()
	if not repository_result.is_ok:
		return _failure(repository_result.error_code, repository_result.error_message)
	autosave_service = AutosaveServiceScript.new()
	var autosave_result = autosave_service.configure(
		player_state_repository,
		config.autosave_interval_seconds,
	)
	if not autosave_result.is_ok:
		return _failure(autosave_result.error_code, autosave_result.error_message)
	return _success(true)


## 为新权威实体构造首次聚合，或载入仓储中同角色的既有聚合。
## [param entity] 刚由服务器接纳的角色实体。
## [param instance] 当前拥有该实体的权威地图实例。
func _register_persistent_player(
	entity: AuthoritativeEntity,
	instance: AuthoritativeMapInstance,
):
	if autosave_service == null:
		return DomainResultScript.ok()
	var vehicle_state := instance.vehicle_combat_state_for(entity.entity_id)
	var state_result = PlayerStateRecordScript.from_dictionary({
		"schema_version": PlayerStateRecord.CURRENT_SCHEMA_VERSION,
		"account_id": "account.%s" % entity.entity_id,
		"account_name": entity.entity_id,
		"account_status": "active",
		"character_id": entity.entity_id,
		"display_name": entity.entity_id,
		"revision": 0,
		"inventory_revision": 0,
		"vehicle_loadout_revision": 0,
		"inventory_capacity": 40,
		"currency": 1000,
		"character_sex": "male",
		"character_level": 10,
		"character_profession": "新兵",
		"character_faction": "易安港",
		"character_residence": "易安港基地",
		"character_description": "正在探索蓝古星的年轻殖民者。",
		"inventory_stacks": [{
			"stack_id": "inventory.%s.spare_engine" % entity.entity_id,
			"item_definition_id": "beginner_engine",
			"quantity": 1,
			"slot_index": 0,
			"container_id": "main",
			"position_px": [0, 0],
			"footprint_px": [45, 45],
			"locked": false,
			"bound": false,
			"max_durability": 900,
			"durability": 900,
		}, {
			"stack_id": "inventory.%s.training_shirt" % entity.entity_id,
			"item_definition_id": "male_sleeveless_shirt",
			"quantity": 1,
			"slot_index": 1,
			"container_id": "main",
			"position_px": [60, 0],
			"footprint_px": [45, 45],
			"locked": false,
			"bound": true,
			"max_durability": 64,
			"durability": 64,
		}],
		"equipment_slots": [{
			"owner_kind": "vehicle",
			"slot_id": "chassis",
			"slot_location": 0,
			"equip_kind": 0,
			"item_instance_id": "equipment.%s.chassis" % entity.entity_id,
			"item_definition_id": "recruit_tank",
			"max_durability": 1020,
			"durability": 1020,
			"upgrade_level": 0,
		}, {
			"owner_kind": "vehicle",
			"slot_id": "primary_weapon",
			"slot_location": 1,
			"equip_kind": 1,
			"item_instance_id": "equipment.%s.primary_weapon" % entity.entity_id,
			"item_definition_id": "recruit_energy_cannon",
			"max_durability": 900,
			"durability": 900,
			"upgrade_level": 0,
		}, {
			"owner_kind": "vehicle",
			"slot_id": "propulsion",
			"slot_location": 3,
			"equip_kind": 3,
			"item_instance_id": "equipment.%s.propulsion" % entity.entity_id,
			"item_definition_id": "beginner_engine",
			"max_durability": 900,
			"durability": 900,
			"upgrade_level": 0,
		}],
		"character_max_health": 100,
		"character_health": 100,
		"character_experience": 0,
		"character_skills": _initial_skill_states(),
		"vehicle_id": "vehicle.%s" % entity.entity_id,
		"vehicle_definition_id": "recruit_tank",
		"vehicle_max_health": vehicle_state.max_health if vehicle_state != null else 70,
		"vehicle_health": vehicle_state.health if vehicle_state != null else 70,
		"reserve_energy_capacity": vehicle_state.reserve_energy_capacity if vehicle_state != null else 10000.0,
		"reserve_energy": vehicle_state.reserve_energy if vehicle_state != null else 10000.0,
		"working_energy_capacity": vehicle_state.working_energy_capacity if vehicle_state != null else 100.0,
		"working_energy": vehicle_state.working_energy if vehicle_state != null else 100.0,
		"output_power": vehicle_state.power_output if vehicle_state != null else 21.0,
		"map_id": String(instance.definition.map_id),
		"map_instance_id": instance.instance_id,
		"position": [entity.position.x, entity.position.y],
		"facing_direction": entity.facing_index,
		"checkpoint_id": "%s.autosave" % instance.definition.map_id,
	})
	if not state_result.is_ok:
		return state_result
	return autosave_service.register_player(state_result.value)


## 创建新角色的完整技能成长初始状态。
## 返回技能标识到等级、当前经验和小数余量的映射。
## 设计：新角色与迁移存档使用同一持久化形状，避免运行时继续传播旧整数格式。
func _initial_skill_states() -> Dictionary:
	var levels := {
		"energy_cannon": 10, "repair": 10, "driving": 10, "mining": 10,
		"cooking": 0, "tailoring": 0, "refining": 0, "manufacturing": 0,
		"processing": 0, "rocket_launcher": 0, "missile": 0, "stealth": 0,
		"radar": 0,
	}
	var states: Dictionary = {}
	for skill_id: String in levels:
		states[skill_id] = {
			"level": levels[skill_id], "current_exp": 0, "fractional_exp": 0.0,
		}
	return states


## 从会话所属地图采集最新位置、朝向和战车资源到候选聚合。
## [param state] 自动存档服务持有的隔离聚合副本。
func _capture_persistent_player_state(state: PlayerStateRecord):
	var session: ServerSession = sessions.session_for_entity(state.character_id)
	if session == null:
		return DomainResultScript.failure(
			&"persistence.autosave_session_missing",
			"registered autosave character has no authoritative session",
		)
	var instance := map_registry.instance_by_id(session.map_instance_id)
	var entity: AuthoritativeEntity = instance.entities.get(session.entity_id) if instance != null else null
	if entity == null:
		return DomainResultScript.failure(
			&"persistence.autosave_entity_missing",
			"registered autosave character has no authoritative entity",
		)
	state.map_id = String(instance.definition.map_id)
	state.map_instance_id = instance.instance_id
	state.position = entity.position
	state.facing_direction = entity.facing_index
	state.checkpoint_id = "%s.autosave" % instance.definition.map_id
	var vehicle_state := instance.vehicle_combat_state_for(entity.entity_id)
	if vehicle_state != null:
		state.vehicle_max_health = vehicle_state.max_health
		state.vehicle_health = vehicle_state.health
		state.reserve_energy_capacity = vehicle_state.reserve_energy_capacity
		state.reserve_energy = vehicle_state.reserve_energy
		state.working_energy_capacity = vehicle_state.working_energy_capacity
		state.working_energy = vehicle_state.working_energy
		state.output_power = vehicle_state.power_output
	var validation = state.validate()
	return DomainResultScript.ok(state) if validation.is_ok else validation


## 将已载入聚合恢复到会话拥有的权威实体和地图实例。
## [param session] 已建立但尚未向客户端发布的服务器会话。
## [param state] 仓储返回且已完成结构校验的玩家聚合。
## 返回该函数计算、查询或操作得到的结果。
## 设计：存档提供资源当前值和上次位置，地图定义仍决定可达性、容量与功率上限。
func _restore_persistent_player_state(
	session: ServerSession,
	state: PlayerStateRecord,
) -> bool:
	var source := map_registry.instance_by_id(session.map_instance_id)
	var target := map_registry.instance_by_id(state.map_instance_id)
	if target == null:
		target = map_registry.instance_by_map_id(state.map_id)
	if source == null or target == null:
		return false
	var source_entity: AuthoritativeEntity = source.entities.get(session.entity_id)
	if source_entity == null:
		return false
	var restored_position := target.admitted_spawn_position(
		state.position,
		StringName(session.entity_id) if target == source else &"",
	)
	if not restored_position.is_finite():
		return false
	var restored_entity := source_entity
	if target != source:
		var spawn_result := target.spawn_entity(
			session.entity_id,
			restored_position,
			source_entity.movement_speed,
		)
		if not spawn_result.ok:
			return false
		restored_entity = spawn_result.value
		if not source.remove_entity(session.entity_id):
			target.remove_entity(session.entity_id)
			return false
		session.map_instance_id = target.instance_id
	restored_entity.position = restored_position
	restored_entity.target_position = restored_position
	restored_entity.path = PackedVector2Array([restored_position])
	restored_entity.path_index = restored_entity.path.size()
	restored_entity.facing_index = state.facing_direction
	restored_entity.action = &"idle"
	if target.vehicle_combat_state_for(session.entity_id) != null:
		var combat_restore := target.restore_vehicle_combat_state(session.entity_id, state)
		if not combat_restore.ok:
			return false
	return true


## 立即提交全部已登记角色，未启用持久化时安全忽略。
func _save_all_persistent_players() -> void:
	if autosave_service == null:
		return
	var result := autosave_service.save_all(Callable(self, "_capture_persistent_player_state"))
	if not result.is_ok:
		push_error("Authoritative persistence flush failed [%s]: %s" % [
			result.error_code, result.error_message,
		])


## 在服务器节点退出场景树前执行最后一次权威存档。
func _exit_tree() -> void:
	_save_all_persistent_players()


## 加载并校验 `load_configured_map_instances` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _load_configured_map_instances() -> Dictionary:
	var definition_paths := PackedStringArray([config.map_config_path])
	if FileAccess.file_exists(config.map_catalog_path):
		var catalog_file := FileAccess.open(config.map_catalog_path, FileAccess.READ)
		if catalog_file == null:
			return _failure(&"invalid_map_catalog", "map catalog cannot be opened")
		var parsed: Variant = JSON.parse_string(catalog_file.get_as_text())
		if not parsed is Dictionary:
			return _failure(&"invalid_map_catalog", "map catalog must be a dictionary")
		var raw_paths: Array = []
		if parsed.get("definition_paths") is Array:
			raw_paths = parsed["definition_paths"]
		elif parsed.get("definitions") is Dictionary:
			var map_ids: Array = parsed["definitions"].keys()
			map_ids.sort()
			for map_id: Variant in map_ids:
				raw_paths.append(parsed["definitions"][map_id])
		else:
			return _failure(
				&"invalid_map_catalog", "catalog requires definition_paths or definitions"
			)
		definition_paths = PackedStringArray()
		for raw_path: Variant in raw_paths:
			if typeof(raw_path) != TYPE_STRING or not String(raw_path).begins_with("res://"):
				return _failure(&"invalid_map_catalog", "map definition paths must use res://")
			if String(raw_path) not in definition_paths:
				definition_paths.append(String(raw_path))
	if config.map_config_path not in definition_paths:
		definition_paths.insert(0, config.map_config_path)
	map_instance = null
	for definition_path: String in definition_paths:
		var loaded_instance: AuthoritativeMapInstance = MapInstanceScript.new()
		_configure_map_instance(loaded_instance)
		var map_result := loaded_instance.load_map(definition_path)
		if not map_result.ok:
			return _failure(
				&"map_catalog_load_failed",
				"%s: %s" % [definition_path, map_result.get("message", "unknown map error")],
			)
		var combat_result := loaded_instance.configure_combat(_combat_catalog, config.simulation_hz)
		if not combat_result.ok:
			return _failure(
				&"map_combat_load_failed",
				"%s: %s" % [definition_path, combat_result.get("message", "unknown combat error")],
			)
		var registration := map_registry.register_instance(loaded_instance)
		if not registration.ok:
			return registration
		if definition_path == config.map_config_path:
			map_instance = loaded_instance
	if map_instance == null:
		return _failure(&"primary_map_not_registered", "configured primary map was not loaded")
	return _success(map_instance)


## 执行 `configure_map_instance` 对应的模块操作。
## [param instance] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _configure_map_instance(instance: AuthoritativeMapInstance) -> void:
	instance.dynamic_blocking_enabled = config.dynamic_blocking_enabled
	instance.dynamic_blocking_radius = config.dynamic_blocking_radius


## 执行 `copy_transitioned_entity_state` 对应的模块操作。
## [param source] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param destination] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _copy_transitioned_entity_state(
	source: AuthoritativeEntity,
	destination: AuthoritativeEntity,
) -> void:
	destination.last_input_sequence = source.last_input_sequence
	destination.facing_index = source.facing_index
	destination.movement_speed = source.movement_speed
	destination.state_revision = source.state_revision + 1
	destination.action = &"idle"
	destination.path = PackedVector2Array([destination.position])
	destination.path_index = destination.path.size()
	destination.target_position = destination.position


## 跨地图复制服务器拥有的战车当前资源，避免回城后的 10% 生命在下一次切图时重置。
func _copy_transitioned_vehicle_state(
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


## 执行 `place_transitioned_entity` 对应的模块操作。
## [param entity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param destination_instance] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param spawn_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _place_transitioned_entity(
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


## 执行 `remove_entity_from_registered_map` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _remove_entity_from_registered_map(entity_id: String) -> bool:
	for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
		if registered_instance.remove_entity(entity_id):
			return true
	return false


## 执行 `success` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## 执行 `failure` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
