class_name AuthoritativeServer
extends Node

const ConfigScript := preload("res://scripts/server/server_config.gd")
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
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
const MiningCatalogScript := preload("res://scripts/domain/mining/mining_catalog.gd")
const MiningModuleScript := preload(
	"res://scripts/server/modules/mining/authoritative_mining_module.gd"
)
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const FilePlayerStateRepositoryScript := preload("res://scripts/server/persistence/file_player_state_repository.gd")
const AutosaveServiceScript := preload("res://scripts/server/persistence/authoritative_autosave_service.gd")
const PlayerPanelServiceScript := preload("res://scripts/server/player_panels/authoritative_player_panel_service.gd")
const CommerceServiceScript := preload(
	"res://scripts/server/commerce/authoritative_commerce_service.gd"
)
const ManufacturingServiceScript := preload(
	"res://scripts/server/manufacturing/authoritative_manufacturing_service.gd"
)
const DomainResultScript := preload("res://scripts/core/domain_result.gd")
const RuntimeContentBootstrapScript := preload(
	"res://scripts/content/runtime_content_bootstrap.gd"
)
const MapTransitionLandingResolverScript := preload(
	"res://scripts/maps/map_transition_landing_resolver.gd"
)

signal snapshot_generated(snapshot: Dictionary)
signal command_rejected(peer_id: int, code: StringName)
signal server_message_generated(peer_id: int, message: Dictionary)
signal peer_snapshot_generated(peer_id: int, snapshot: Dictionary)

const TRANSPORT_SESSION_REQUEST := &"session_request"
const TRANSPORT_PLAYER_PANEL_COMMAND := &"player_panel_command"
const BASE_HALL_MAP_ID := "yian_harbor_hall_floor_1"
const VEHICLE_RECOVERY_DELAY_SECONDS := 3.0
const VEHICLE_RECOVERY_HEALTH_RATIO := 0.10
const GLORY_RUNTIME_MAP_INDEX_PATH := "res://data/content/glory_map_runtime_index_v1.json"
const MAX_TRANSITION_LANDING_CORRECTION_DISTANCE := 192.0

var _food_runtime: AuthoritativeFoodRuntime
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
var _mining_catalog
var player_state_repository: PlayerStateRepository
var autosave_service: AuthoritativeAutosaveService
var player_panel_service: AuthoritativePlayerPanelService
var reward_service := AuthoritativeRewardService.new()
var commerce_service
var manufacturing_service
var warehouse_service: PersonalWarehouseService
var _pending_vehicle_recoveries: Dictionary = {}
var _runtime_definition_paths_by_map_id: Dictionary = {}
var _runtime_map_ids_by_legacy_world: Dictionary = {}
var _runtime_legacy_location_by_map_id: Dictionary = {}
var _default_map_id := ""


## 节点进入场景树后初始化运行依赖。
## 设计：独立服务器在此初始化；进程内传输可先显式初始化再挂为子节点，且不得重复构建权威状态。
func _ready() -> void:
	if map_registry != null:
		return
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
	var content_result: Dictionary = RuntimeContentBootstrapScript.mount_default()
	if not bool(content_result.get("ok", false)):
		return _failure(&"runtime_content_mount_failed", String(content_result.get("message", "")))
	var runtime_index_result := _load_runtime_map_index()
	if not runtime_index_result.ok:
		return runtime_index_result
	map_registry = MapRegistryScript.new()
	var combat_catalog_result = CombatCatalogScript.load_default()
	if not combat_catalog_result.is_ok:
		return _failure(combat_catalog_result.error_code, combat_catalog_result.error_message)
	_combat_catalog = combat_catalog_result.value
	var mining_catalog_result = MiningCatalogScript.load_default()
	if not mining_catalog_result.is_ok:
		return _failure(mining_catalog_result.error_code, mining_catalog_result.error_message)
	_mining_catalog = mining_catalog_result.value
	if injected_map_instances.is_empty():
		var load_result := _load_configured_map_instances()
		if not load_result.ok:
			return load_result
	else:
		for injected_instance: AuthoritativeMapInstance in injected_map_instances:
			_configure_map_instance(injected_instance)
			var mining_result := injected_instance.configure_mining(
				_mining_catalog, config.simulation_hz
			)
			if not mining_result.ok:
				return mining_result
			var registration := map_registry.register_instance(injected_instance)
			if not registration.ok:
				return registration
		map_instance = injected_map_instances[0]
		_default_map_id = String(map_instance.definition.map_id)
	sessions = SessionRegistryScript.new()
	sessions.configure(config.reconnect_grace_seconds)
	_pending_vehicle_recoveries.clear()
	var persistence_result := _initialize_persistence(injected_repository)
	if not persistence_result.ok:
		return persistence_result
	var reward_result := reward_service.initialize(autosave_service)
	if not reward_result.is_ok:
		return _failure(reward_result.error_code, reward_result.error_message)
	player_panel_service = PlayerPanelServiceScript.new()
	var panel_result = player_panel_service.initialize(reward_service.pipeline)
	if not panel_result.is_ok:
		return _failure(panel_result.error_code, panel_result.error_message)
	for instance: AuthoritativeMapInstance in map_registry.all_instances():
		if instance.combat_module != null:
			instance.combat_module.rewards = reward_service
	commerce_service = CommerceServiceScript.new()
	var commerce_result: DomainResult = commerce_service.initialize(reward_service.pipeline)
	if not commerce_result.is_ok:
		return _failure(commerce_result.error_code, commerce_result.error_message)
	manufacturing_service = ManufacturingServiceScript.new()
	var manufacturing_result: DomainResult = manufacturing_service.initialize(reward_service.pipeline)
	if not manufacturing_result.is_ok:
		return _failure(manufacturing_result.error_code, manufacturing_result.error_message)
	warehouse_service = PersonalWarehouseService.new()
	var warehouse_result := warehouse_service.initialize(reward_service.pipeline)
	if not warehouse_result.is_ok:
		return _failure(warehouse_result.error_code, warehouse_result.error_message)
	_ticks_per_snapshot = floori(float(config.simulation_hz) / float(config.snapshot_hz))
	return _success(_default_map_id)


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


## 推进世界与食品的权威时间。
## [param delta] 本帧经过的时间。
func _physics_process(delta: float) -> void:
	advance_simulation(delta, Time.get_ticks_msec())


## 推进并更新 `advance_simulation` 对应的模块状态。
## [param elapsed_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func advance_simulation(elapsed_seconds: float, now_msec := -1) -> void:
	if sessions == null or elapsed_seconds <= 0.0:
		return
	_advance_food_status()
	_simulation_accumulator += elapsed_seconds
	var fixed_delta := 1.0 / float(config.simulation_hz)
	while _simulation_accumulator + 0.000001 >= fixed_delta:
		_simulation_accumulator -= fixed_delta
		server_tick += 1
		map_registry.suspend_empty_instances(server_tick - 1)
		for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
			registered_instance.simulate(fixed_delta)
			_settle_mining_cycles(registered_instance)
			_settle_equipment_conditions(registered_instance)
			for progression_event: Dictionary in registered_instance.drain_skill_progression_events():
				_apply_skill_progression_event(progression_event)
			for quest_kill: Dictionary in registered_instance.drain_quest_kills():
				_apply_quest_kill(quest_kill)
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
	if sessions == null:
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
	var primary := ensure_runtime_map(_default_map_id)
	if not primary.ok:
		return primary
	map_instance = primary.value
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
		var authentication_failure := _failure(&"unauthenticated_peer", "open a session before using abilities")
		_trace_ability_command_result(peer_id, "", intent, authentication_failure)
		return authentication_failure
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		var map_failure := _failure(&"session_map_unavailable", "session map is not registered")
		_trace_ability_command_result(peer_id, session.entity_id, intent, map_failure)
		return map_failure
	var authoritative_context: Dictionary = {}
	var ability_id := String(intent.get("ability_id", ""))
	if ability_id in [AuthoritativeCombatModule.SELF_REPAIR_ABILITY_ID, MiningModuleScript.COLLECT_ABILITY_ID]:
		if autosave_service == null:
			return _failure(&"ability.persistence_required", "ability requires authoritative player state")
		var current := autosave_service.state_for(session.entity_id)
		if current == null:
			return _failure(&"ability.player_state_missing", "ability player state is unavailable")
		if ability_id == MiningModuleScript.COLLECT_ABILITY_ID:
			var allowed := _validate_mining_equipment(current)
			if not allowed.is_ok:
				var rejected := _failure(allowed.error_code, allowed.error_message)
				_trace_ability_command_result(peer_id, session.entity_id, intent, rejected)
				return rejected
			authoritative_context.merge(allowed.value)
		var skill_id := "repair" if ability_id == AuthoritativeCombatModule.SELF_REPAIR_ABILITY_ID \
			else "mining"
		var skill_state: Variant = current.character_skills.get(skill_id, {})
		if not skill_state is Dictionary:
			return _failure(&"ability.skill_missing", "%s skill state is invalid" % skill_id)
		authoritative_context["%s_skill_level" % skill_id] = maxi(
			0, int(skill_state.get("level", 0))
		)
	var result: Dictionary = current_instance.handle_use_ability(
		session.entity_id, intent, authoritative_context
	)
	_trace_ability_command_result(peer_id, session.entity_id, intent, result)
	if not result.ok:
		command_rejected.emit(peer_id, result.code)
	return result


## 记录能力命令跨过权威入口后的接受或拒绝结果。
## [param peer_id] 传输层认证的客户端连接标识。
## [param entity_id] 会话绑定的玩家实体；未认证时为空。
## [param intent] 客户端提交的原始能力意图。
## [param result] 权威地图实例返回的领域结果。
## 设计：此处统一覆盖冷却、地图、能量和协议拒绝，便于与客户端视觉弹体关联。
func _trace_ability_command_result(
	peer_id: int,
	entity_id: String,
	intent: Dictionary,
	result: Dictionary,
) -> void:
	CombatTraceLogger.record(&"server", &"ability_command_result", {
		"server_tick": server_tick,
		"peer_id": peer_id,
		"entity_id": entity_id,
		"map_instance_id": String(intent.get("map_instance_id", "")),
		"ability_id": String(intent.get("ability_id", "")),
		"input_sequence": int(intent.get("input_sequence", -1)),
		"aim_world_position": intent.get("aim_world_position", {}),
		"accepted": bool(result.get("ok", false)),
		"result_code": String(result.get("code", "")),
		"result_message": String(result.get("message", "")),
		"result_value": result.get("value"),
	})


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
	var destination_instance := _resolve_or_load_transition_target(
		transition, source_instance.definition.world_id
	)
	if destination_instance == null:
		return _failure(
			ErrorCodes.MAP_TRANSITION_TARGET_UNRESOLVED,
			"transition target is not registered on this server",
		)
	var destination_spawn := Vector2.INF
	if transition.kind == MapTransition.Kind.CLIENT_POINT and transition.has_destination_landing_point:
		destination_spawn = transition.destination_landing_point
	else:
		var landing: Dictionary = MapTransitionLandingResolverScript.resolve_landing(
			source_instance.definition,
			transition,
			destination_instance.definition,
		)
		if landing.is_empty():
			return _failure(
				ErrorCodes.MAP_TRANSITION_ENTRY_MISMATCH,
				"destination map does not admit the requested entry number",
			)
		destination_spawn = landing["position"]
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
		_place_transitioned_entity(committed_entity, destination_instance, destination_spawn)
	else:
		var transition_state := autosave_service.state_for(session.entity_id) \
			if autosave_service != null else null
		if transition_state != null:
			var captured_transition: DomainResult = _capture_persistent_player_state(transition_state)
			if not captured_transition.is_ok:
				return _failure(captured_transition.error_code, captured_transition.error_message)
			var stored_transition := autosave_service.commit_player_state(session.entity_id, transition_state)
			if not stored_transition.is_ok:
				return _failure(stored_transition.error_code, stored_transition.error_message)
			var prepared_loadout := _prepare_entity_combat_loadout(
				destination_instance, session.entity_id, transition_state
			)
			if not prepared_loadout.ok:
				return prepared_loadout
		var destination_speed := entity.movement_speed \
			if destination_instance.is_vehicle_combat_active() \
			else config.default_movement_speed
		var destination_spawn_result := destination_instance.spawn_entity(
			session.entity_id, destination_spawn, destination_speed
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
## [param peer_id] 调用方传入的 `peer_id` 参数。
## [param raw_intent] 调用方传入的 `raw_intent` 参数。
## 返回该函数计算、查询或操作得到的结果。
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
	if source == null:
		return _failure(&"vehicle_recovery.map_missing", "current map is unavailable")
	if String(source.definition.map_id) == BASE_HALL_MAP_ID:
		return _failure(&"vehicle_recovery.already_home", "已经在基地中心")
	var vehicle_state := source.vehicle_combat_state_for(session.entity_id) if source != null else null
	if vehicle_state == null:
		return _failure(&"vehicle_recovery.combat_state_missing", "vehicle state is unavailable")
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
## [param entity_id] 调用方传入的 `entity_id` 参数。
## [param pending] 调用方传入的 `pending` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _recover_destroyed_vehicle_to_base(entity_id: String, pending: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_entity(entity_id)
	if session == null or session.map_instance_id != String(pending["source_instance_id"]):
		return _failure(&"vehicle_recovery.session_changed", "session changed during rescue")
	var source := map_registry.instance_by_id(session.map_instance_id)
	var destination := map_registry.instance_by_map_id(BASE_HALL_MAP_ID)
	if destination == null:
		var ensured := ensure_runtime_map(BASE_HALL_MAP_ID)
		if ensured.ok:
			destination = ensured.value
	var source_entity: AuthoritativeEntity = source.entities.get(entity_id) if source != null else null
	var source_vehicle := source.vehicle_combat_state_for(entity_id) if source != null else null
	if source_entity == null or source_vehicle == null:
		return _failure(&"vehicle_recovery.combat_state_missing", "vehicle state is unavailable")
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
		var recovery_state := autosave_service.state_for(entity_id) \
			if autosave_service != null else null
		if recovery_state != null:
			var captured_recovery: DomainResult = _capture_persistent_player_state(recovery_state)
			if not captured_recovery.is_ok:
				return _failure(captured_recovery.error_code, captured_recovery.error_message)
			var stored_recovery := autosave_service.commit_player_state(entity_id, recovery_state)
			if not stored_recovery.is_ok:
				return _failure(stored_recovery.error_code, stored_recovery.error_message)
			var prepared_loadout := _prepare_entity_combat_loadout(
				destination, entity_id, recovery_state
			)
			if not prepared_loadout.ok:
				return prepared_loadout
		var destination_speed := source_entity.movement_speed \
			if destination.is_vehicle_combat_active() else config.default_movement_speed
		var spawned := destination.spawn_entity(entity_id, spawn_position, destination_speed)
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
	if recovered_vehicle.health <= 0:
		recovered_vehicle.health = maxi(1, ceili(float(recovered_vehicle.max_health) * VEHICLE_RECOVERY_HEALTH_RATIO))
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
	if autosave_service == null or player_panel_service == null or commerce_service == null \
			or manufacturing_service == null:
		return _failure(&"panels.persistence_required", "player panels require authoritative persistence")
	var current := autosave_service.state_for(session.entity_id)
	if current == null:
		return _failure(&"panels.state_missing", "authoritative player state is not registered")
	var command_type := String(command.get("type", ""))
	if command_type == "query_scene_players":
		return _success({"scene_players": ScenePlayerListProjector.build(
			session.map_instance_id, sessions, autosave_service
		)})
	var is_warehouse := command_type in PersonalWarehouseService.COMMANDS
	if is_warehouse and warehouse_service == null:
		return _failure(&"warehouse.unavailable", "个人仓库尚未初始化")
	var is_commerce: bool = commerce_service.handles(command_type)
	var is_manufacturing: bool = manufacturing_service.handles(command_type)
	var current_map := map_registry.instance_by_id(session.map_instance_id)
	var captured: DomainResult = _capture_persistent_player_state(current)
	if not captured.is_ok:
		return _failure(captured.error_code, captured.error_message)
	current = captured.value
	var trusted_command := command.duplicate(true)
	trusted_command["_authoritative_vehicle_combat_active"] = current_map != null \
		and current_map.is_vehicle_combat_active()
	var executed: DomainResult
	if is_commerce:
		executed = commerce_service.execute(current, trusted_command)
	elif is_manufacturing:
		executed = manufacturing_service.execute(current, trusted_command)
	elif is_warehouse:
		executed = warehouse_service.execute(current, trusted_command)
	else:
		executed = player_panel_service.execute(current, trusted_command)
	if not executed.is_ok:
		return _failure(executed.error_code, executed.error_message)
	var value: Dictionary = executed.value
	if not bool(value.get("changed", false)):
		return _success(value["panel_bundle"])
	var prepared_loadout: Dictionary = {}
	if current_map != null and current_map.is_vehicle_combat_active():
		var built_loadout := _build_entity_combat_loadout(current_map, value["candidate"])
		if not built_loadout.is_ok:
			return _failure(built_loadout.error_code, built_loadout.error_message)
		prepared_loadout = built_loadout.value
	var committed = autosave_service.commit_player_state(session.entity_id, value["candidate"])
	if not committed.is_ok:
		return _failure(committed.error_code, committed.error_message)
	if current_map != null and current_map.mining_module != null \
			and current.vehicle_loadout_revision != committed.value.vehicle_loadout_revision:
		current_map.mining_module.interrupt(session.entity_id, &"equipment_changed")
	if command_type == "use_inventory_item":
		_apply_food_runtime(session.entity_id, committed.value)
	elif (command_type in ClothingEnhancementService.COMMANDS or command_type in VehicleSocketService.COMMANDS \
		or command_type in EquipmentProcessingService.COMMANDS \
		or command_type in EquipmentMaintenanceService.COMMANDS \
		or command_type in ["equip_character_item", "unequip_character_item"]) \
		and current_map != null and current_map.is_vehicle_combat_active():
		var enhanced_loadout := current_map.refresh_achievement_loadout(session.entity_id, prepared_loadout)
		if not enhanced_loadout.is_ok:
			return _failure(enhanced_loadout.error_code, enhanced_loadout.error_message)
		if current_map.mining_module != null:
			current_map.mining_module.interrupt(session.entity_id, &"clothing_changed")
	elif command_type not in ["split_inventory_item", "merge_inventory_item"] \
		and current_map != null and current_map.is_vehicle_combat_active():
		var refreshed_loadout := current_map.set_vehicle_combat_loadout(
			session.entity_id, prepared_loadout
		)
		if not refreshed_loadout.ok:
			return refreshed_loadout
	if is_commerce:
		var operation: Dictionary = value.get("operation", {})
		if operation.get("skill_level_up") is Dictionary and session.has_active_peer():
			_send_reliable(session.peer_id, {"type": "skill_level_up",
				"result": _wire_result(_success(operation["skill_level_up"]))})
		return _success(commerce_service.build_bundle(committed.value, value.get("operation", {})))
	if is_manufacturing:
		return _success(manufacturing_service.build_bundle(
			committed.value, value.get("operation", {})
		))
	if is_warehouse:
		return _success(warehouse_service.build_bundle(committed.value, value.get("operation", {})))
	return _success(player_panel_service.build_bundle(committed.value))


## 消费仅来自战斗模块的死亡事件，进度进入同一玩家存档并推送任务日志。
## [param event] 权威战斗模块确认的击杀事件。
func _apply_quest_kill(event: Dictionary) -> void:
	if autosave_service == null or commerce_service == null:
		return
	var entity_id := String(event.get("killer_id", ""))
	var current := autosave_service.state_for(entity_id)
	if current == null:
		return
	var result: DomainResult = commerce_service.record_monster_kill(current, event)
	if not result.is_ok or not bool(result.value.get("changed", false)):
		return
	var stored := autosave_service.update_runtime_state(entity_id, result.value["candidate"])
	if not stored.is_ok:
		push_error("训练进度存档失败：" + stored.error_message)
		return
	if bool(result.value.get("title_changed", false)):
		_refresh_achievement_combat(entity_id, stored.value)
	var session: ServerSession = sessions.session_for_entity(entity_id)
	if session != null and session.has_active_peer():
		_send_reliable(session.peer_id, {"type": "player_panels",
			"result": _wire_result(_success(player_panel_service.build_bundle(stored.value)))})


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


## 将地图到期的采矿周期原子地写入背包，再扣除矿源储量并发放采矿经验。
## [param instance] 调用方传入的 `instance` 参数。
func _settle_mining_cycles(instance: AuthoritativeMapInstance) -> void:
	if instance == null or autosave_service == null or player_panel_service == null:
		return
	for cycle: Dictionary in instance.drain_mining_cycles():
		var token := String(cycle.get("token", ""))
		var entity_id := String(cycle.get("actor_id", ""))
		var current := autosave_service.state_for(entity_id)
		if token.is_empty() or current == null:
			instance.reject_mining_cycle(token)
			continue
		var allowed := _validate_mining_equipment(current)
		if not allowed.is_ok:
			instance.reject_mining_cycle(token)
			_send_mining_rejection(entity_id, allowed.error_code, allowed.error_message)
			continue
		var granted := player_panel_service.grant_loot(current, {
			"loot_id": token,
			"item_definition_id": String(cycle.get("item_definition_id", "")),
			"quantity": int(cycle.get("quantity", 0)),
		}, AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED,
			String(cycle.get("item_definition_id", "")), int(cycle.get("quantity", 0)), token))
		if not granted.is_ok:
			instance.reject_mining_cycle(token)
			_send_mining_rejection(entity_id, granted.error_code, granted.error_message)
			continue
		var grant_value: Dictionary = granted.value
		var stored := autosave_service.commit_player_state(entity_id, grant_value["candidate"])
		if not stored.is_ok:
			instance.reject_mining_cycle(token)
			_send_mining_rejection(entity_id, stored.error_code, stored.error_message)
			continue
		var committed = instance.commit_mining_cycle(token)
		if not committed.is_ok:
			push_error("Mining source commit failed after inventory commit: %s" % committed.error_message)
			continue
		var event: Dictionary = committed.value
		if instance.combat_module != null and instance.combat_module.actors.has(entity_id):
			(instance.combat_module.actors[entity_id].equipment_condition as EquipmentConditionLoadout).record_use("mining")
		if bool(grant_value.get("title_changed", false)):
			_refresh_achievement_combat(entity_id, stored.value)
		_apply_skill_progression_event({
			"entity_id": entity_id,
			"source": "mined_material",
			"skill_id": "mining",
			"quantity": int(event["quantity"]),
			"experience_coefficient": float(event["experience_coefficient"]),
		})
		var session := sessions.session_for_entity(entity_id)
		if session != null and session.has_active_peer():
			_send_reliable(session.peer_id, {
				"type": "mining_collected",
				"result": _wire_result(_success({
					"mining_event": event,
					"panel_bundle": player_panel_service.build_bundle(
						autosave_service.state_for(entity_id)
					),
				})),
			})


## 热更新成就及食品战斗增益，保留冷却、命令序号、维修周期和已发射弹体。
## [param entity_id] 已完成权威结算的玩家。
## [param state] 新增益所在的已提交状态。
func _refresh_achievement_combat(entity_id: String, state: PlayerStateRecord) -> void:
	if map_registry == null or _combat_catalog == null:
		return
	var target: AuthoritativeMapInstance = map_registry.instance_by_id(state.map_instance_id)
	if target == null:
		return
	if target.combat_module != null and target.combat_module.actors.has(entity_id):
		var condition: EquipmentConditionLoadout = target.combat_module.actors[entity_id].equipment_condition
		EquipmentConditionCapture.apply(state, condition.snapshot())
	var loadout := _build_entity_combat_loadout(target, state)
	if not loadout.is_ok:
		if not target.is_vehicle_combat_active() and loadout.error_code in [
			&"equipment.chassis_required_for_field", &"equipment.primary_weapon_required_for_field"]:
			return
		push_error("Achievement combat update failed: " + loadout.error_message)
		return
	var updated := target.refresh_achievement_loadout(entity_id, loadout.value)
	if not updated.is_ok:
		push_error("Achievement combat update failed: " + updated.error_message)


## 仅在装备刚损坏时重算装配，普通使用余量留在模拟对象中，避免逐帧重建聚合。
## [param instance] 已推进本刻战斗与采矿的地图。
func _settle_equipment_conditions(instance: AuthoritativeMapInstance) -> void:
	if autosave_service == null or player_panel_service == null or instance.combat_module == null:
		return
	for entity_id: String in instance.combat_module.actors:
		var condition: EquipmentConditionLoadout = instance.combat_module.actors[entity_id].equipment_condition
		if not condition.needs_recalculation: continue
		var current := autosave_service.state_for(entity_id)
		if current == null: continue
		var captured: DomainResult = _capture_persistent_player_state(current)
		if not captured.is_ok: continue
		var loadout := _build_entity_combat_loadout(instance, current)
		if not loadout.is_ok:
			push_error("Equipment wear refresh failed: " + loadout.error_message)
			continue
		var stored := autosave_service.commit_player_state(entity_id, current)
		if not stored.is_ok: continue
		instance.refresh_achievement_loadout(entity_id, loadout.value)
		if instance.mining_module != null: instance.mining_module.interrupt(entity_id, &"equipment_broken")
		var session := sessions.session_for_entity(entity_id)
		if session != null and session.has_active_peer():
			_send_reliable(session.peer_id, {"type": "player_panels", "result": _wire_result(_success(player_panel_service.build_bundle(current)))})


## 复用完整玩家聚合校验采矿装配，不信任客户端声明的武器类型。
## [param state] 服务器保存的最新角色状态。
## 返回开始和结算阶段共用的装备校验结果。
func _validate_mining_equipment(state: PlayerStateRecord) -> DomainResult:
	if player_panel_service == null:
		return DomainResult.failure(&"mining.state_unavailable", "mining player aggregate is unavailable")
	var restored := player_panel_service.restore_player(state)
	if not restored.is_ok:
		return restored
	var player: Player = restored.value
	var checked := player.vehicle.loadout.validate_mining(player.skills.base_level("mining"))
	if not checked.is_ok:
		return checked
	return DomainResult.ok({"mining_time_reduction_ms": player.vehicle.loadout.attachment_bonus("mining_time_ms"),
		"mining_power": player.vehicle.clothing_bonuses.apply_value("mining_power", 0),
		"prospecting_chance": player.vehicle.clothing_bonuses.trait_value("prospecting")})


## 向仍在线的采矿者报告异步背包/存档拒绝。
## [param entity_id] 调用方传入的 `entity_id` 参数。
## [param code] 调用方传入的 `code` 参数。
## [param message] 调用方传入的 `message` 参数。
func _send_mining_rejection(entity_id: String, code: StringName, message: String) -> void:
	var session := sessions.session_for_entity(entity_id)
	if session == null or not session.has_active_peer():
		return
	_send_reliable(session.peer_id, {
		"type": "command_rejected",
		"result": _wire_result(_failure(code, message)),
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
## [param peer_id] 调用方传入的 `peer_id` 参数。
## [param intent] 调用方传入的 `intent` 参数。
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
		"character_faction": "龙之城",
		"character_residence": "龙之城基地",
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
	if instance.combat_module != null and instance.combat_module.actors.has(entity.entity_id):
		var condition: EquipmentConditionLoadout = instance.combat_module.actors[entity.entity_id].equipment_condition
		EquipmentConditionCapture.apply(state, condition.snapshot())
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
	var resumed_food := FoodStatus.new(state.food_status)
	resumed_food.resume(int(Time.get_unix_time_from_system()))
	state.food_status = resumed_food.to_dictionary()
	var source := map_registry.instance_by_id(session.map_instance_id)
	var canonical_map_id := _canonical_persisted_map_id(state.map_id)
	var target: AuthoritativeMapInstance
	# 业务地图替换旧运行地图后，旧 instance_id 也属于旧定义，不能优先恢复它。
	if canonical_map_id == state.map_id:
		target = map_registry.instance_by_id(state.map_instance_id)
	if target == null:
		target = map_registry.instance_by_map_id(canonical_map_id)
	if target == null:
		var ensured := ensure_runtime_map(canonical_map_id)
		if ensured.ok:
			target = ensured.value
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
	var prepared_loadout := _prepare_entity_combat_loadout(
		target, session.entity_id, state
	)
	if not prepared_loadout.ok:
		return false
	if target != source:
		var restored_speed := source_entity.movement_speed \
			if target.is_vehicle_combat_active() else config.default_movement_speed
		var spawn_result := target.spawn_entity(
			session.entity_id,
			restored_position,
			restored_speed,
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
	autosave_service.update_runtime_state(session.entity_id, state)
	return true


## 从同一 Player 聚合为地图实例准备玩家专属权威战车装配。
## [param target] 即将拥有或已经拥有该玩家的地图实例。
## [param entity_id] 玩家权威实体标识。
## [param state] 自动存档服务中的完整玩家记录。
## 返回地图缓存或热更新结果。
## 设计：面板、存档与战斗都经 PlayerStateMapper 还原同一个 loadout，不允许地图回退到独立新兵配置。
func _prepare_entity_combat_loadout(
	target: AuthoritativeMapInstance,
	entity_id: String,
	state: PlayerStateRecord,
) -> Dictionary:
	if target == null or state == null or player_panel_service == null or _combat_catalog == null:
		return _failure(&"combat.player_loadout_unavailable", "player combat loadout dependencies are unavailable")
	var loadout := _build_entity_combat_loadout(target, state)
	if not loadout.is_ok:
		if not target.is_vehicle_combat_active() and loadout.error_code in [
			&"equipment.chassis_required_for_field",
			&"equipment.primary_weapon_required_for_field",
		]:
			return _success(true)
		return _failure(loadout.error_code, loadout.error_message)
	return target.set_vehicle_combat_loadout(entity_id, loadout.value)


## 仅构造并校验候选战斗装配，不写地图运行时；用于持久化提交前预检。
## [param target] 用于确定是否要求完整战车装配的权威地图实例。
## [param state] 即将提交的玩家候选持久化状态。
## 返回已校验的装配定义，或依赖、角色还原和装备规则错误。
func _build_entity_combat_loadout(
	target: AuthoritativeMapInstance,
	state: PlayerStateRecord,
) -> DomainResult:
	if target == null or state == null or player_panel_service == null or _combat_catalog == null:
		return DomainResult.failure(
			&"combat.player_loadout_unavailable",
			"player combat loadout dependencies are unavailable",
		)
	var restored := player_panel_service.restore_player(state)
	if not restored.is_ok:
		return restored
	var player: Player = restored.value
	var loadout: DomainResult = _combat_catalog.vehicle_combat_loadout(
		player,
		config.simulation_hz,
		{
			"base_speed_multiplier": 1500.0,
			"base_speed_cap": target.movement_speed_cap,
		},
	)
	if not loadout.is_ok:
		return loadout
	return DomainResult.ok(loadout.value)


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


## 读取全量荣耀地图索引，但不构建导航图；地图实例在首次进入时创建。
## 返回该函数计算、查询或操作得到的结果。
func _load_runtime_map_index() -> Dictionary:
	_runtime_definition_paths_by_map_id.clear()
	_runtime_map_ids_by_legacy_world.clear()
	_runtime_legacy_location_by_map_id.clear()
	if not FileAccess.file_exists(GLORY_RUNTIME_MAP_INDEX_PATH):
		return _failure(&"runtime_map_index_missing", "Glory runtime map index is missing")
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(GLORY_RUNTIME_MAP_INDEX_PATH)
	)
	if not parsed is Dictionary or not parsed.get("runtime_maps", []) is Array:
		return _failure(&"runtime_map_index_invalid", "Glory runtime map index is invalid")
	for row_value: Variant in parsed["runtime_maps"]:
		if not row_value is Dictionary:
			return _failure(&"runtime_map_index_invalid", "runtime map row must be a dictionary")
		var row: Dictionary = row_value
		var map_id := String(row.get("runtime_id", ""))
		var definition_path := String(row.get("definition_path", ""))
		var world_id := String(row.get("world_id", ""))
		var legacy_code := String(row.get("map_code", "")).strip_edges().to_lower()
		if map_id.is_empty() or world_id.is_empty() or legacy_code.is_empty() \
				or not definition_path.begins_with("res://") \
				or not FileAccess.file_exists(definition_path):
			return _failure(&"runtime_map_index_invalid", "runtime map row is incomplete")
		if _runtime_definition_paths_by_map_id.has(map_id):
			return _failure(&"runtime_map_index_duplicate", "runtime map ID is duplicated")
		_runtime_definition_paths_by_map_id[map_id] = definition_path
		_runtime_legacy_location_by_map_id[map_id] = {
			"world_id": world_id,
			"legacy_code": legacy_code,
		}
		if not _runtime_map_ids_by_legacy_world.has(world_id):
			_runtime_map_ids_by_legacy_world[world_id] = {}
		var world_index: Dictionary = _runtime_map_ids_by_legacy_world[world_id]
		if world_index.has(legacy_code):
			return _failure(&"runtime_map_index_duplicate", "runtime legacy map key is duplicated")
		world_index[legacy_code] = map_id
	return _success(_runtime_definition_paths_by_map_id.size())


## 将旧内容包运行地图 ID 解析为当前受控目录采用的业务地图 ID。
## [param persisted_map_id] 玩家存档中上次提交的地图标识。
## 返回当前目录对应的地图标识；没有替代项时保持原值。
## 设计：映射由荣耀运行索引的世界/旧代码与当前地图目录共同推导，避免为每次地图业务化手写迁移补丁。
func _canonical_persisted_map_id(persisted_map_id: String) -> String:
	var legacy_location: Variant = _runtime_legacy_location_by_map_id.get(persisted_map_id)
	if not legacy_location is Dictionary:
		return persisted_map_id
	var world_id := String(legacy_location.get("world_id", ""))
	var legacy_code := String(legacy_location.get("legacy_code", ""))
	var current_world_index: Dictionary = _runtime_map_ids_by_legacy_world.get(world_id, {})
	return String(current_world_index.get(legacy_code, persisted_map_id))


## 确保受控索引中的地图存在权威实例；未知客户端 ID 无法注入文件路径。
## [param map_id] 调用方传入的 `map_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func ensure_runtime_map(map_id: String) -> Dictionary:
	var existing := map_registry.instance_by_map_id(map_id) if map_registry != null else null
	if existing != null:
		return _success(existing)
	var dormant := map_registry.dormant_instance(map_id)
	if dormant != null:
		var resumed := dormant.resume_runtime(server_tick)
		if not resumed.ok:
			return resumed
		return map_registry.register_instance(dormant)
	var definition_path := String(_runtime_definition_paths_by_map_id.get(map_id, ""))
	if definition_path.is_empty():
		return _failure(&"runtime_map_unknown", "runtime map is absent from the controlled index")
	var loaded_instance: AuthoritativeMapInstance = MapInstanceScript.new()
	_configure_map_instance(loaded_instance)
	var map_result := loaded_instance.load_map(definition_path)
	if not map_result.ok:
		return _failure(
			&"runtime_map_load_failed",
			"%s: %s" % [definition_path, map_result.get("message", "unknown map error")],
		)
	var combat_result := loaded_instance.configure_combat(_combat_catalog, config.simulation_hz)
	if not combat_result.ok:
		return _failure(
			&"runtime_map_combat_failed",
			"%s: %s" % [definition_path, combat_result.get("message", "unknown combat error")],
		)
	loaded_instance.combat_module.rewards = reward_service
	var mining_result := loaded_instance.configure_mining(_mining_catalog, config.simulation_hz)
	if not mining_result.ok:
		return _failure(
			&"runtime_map_mining_failed",
			"%s: %s" % [definition_path, mining_result.get("message", "unknown mining error")],
		)
	var registration := map_registry.register_instance(loaded_instance)
	return _success(loaded_instance) if registration.ok else registration


## 先查已加载实例，再按 map_id 或当前世界旧代码惰性创建目标实例。
## [param transition] 调用方传入的 `transition` 参数。
## [param source_world_id] 调用方传入的 `source_world_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _resolve_or_load_transition_target(
	transition: MapTransition,
	source_world_id: StringName,
) -> AuthoritativeMapInstance:
	var existing := map_registry.resolve_transition_target(transition, source_world_id)
	if existing != null:
		return existing
	var target_map_id := String(transition.destination_map_id)
	if target_map_id.is_empty() and not transition.destination_legacy_code.is_empty():
		var target_world := transition.destination_world_id
		if target_world.is_empty():
			target_world = source_world_id
		var world_index: Dictionary = _runtime_map_ids_by_legacy_world.get(String(target_world), {})
		target_map_id = String(
			world_index.get(transition.destination_legacy_code.strip_edges().to_lower(), "")
		)
	if target_map_id.is_empty():
		return null
	var ensured := ensure_runtime_map(target_map_id)
	return ensured.value if ensured.ok else null


## 只索引开发目录的地图定义；没有玩家连接时不创建导航、怪物或矿源实例。
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
	_default_map_id = ""
	for definition_path: String in definition_paths:
		var loader := MapDefinitionLoaderScript.new()
		var definition := loader.load_file(definition_path)
		if definition == null:
			return _failure(&"map_catalog_load_failed", "; ".join(loader.errors))
		_runtime_definition_paths_by_map_id[String(definition.map_id)] = definition_path
		var world_index: Dictionary = _runtime_map_ids_by_legacy_world.get(String(definition.world_id), {})
		for legacy_code: String in definition.legacy_codes:
			world_index[legacy_code.strip_edges().to_lower()] = String(definition.map_id)
		_runtime_map_ids_by_legacy_world[String(definition.world_id)] = world_index
		if definition_path == config.map_config_path:
			_default_map_id = String(definition.map_id)
	if _default_map_id.is_empty():
		return _failure(&"primary_map_not_registered", "configured primary map was not indexed")
	return _success(_default_map_id)


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
	destination.state_revision = source.state_revision + 1
	destination.action = &"idle"
	destination.path = PackedVector2Array([destination.position])
	destination.path_index = destination.path.size()
	destination.target_position = destination.position


## 跨地图复制服务器拥有的战车当前资源，避免回城后的 10% 生命在下一次切图时重置。
## [param source_instance] 调用方传入的 `source_instance` 参数。
## [param destination_instance] 调用方传入的 `destination_instance` 参数。
## [param entity_id] 调用方传入的 `entity_id` 参数。
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


## 将食品时钟交给独立协调器，资源捕获与地图刷新复用现有端口。
func _advance_food_status() -> void:
	if autosave_service == null or player_panel_service == null:
		return
	if _food_runtime == null:
		_food_runtime = AuthoritativeFoodRuntime.new(autosave_service, player_panel_service,
			_capture_persistent_player_state, _apply_food_runtime, _publish_food_status)
	_food_runtime.advance(sessions.all_sessions(), int(Time.get_unix_time_from_system()))


## 向在线角色发布已提交的食品和玩家投影。
## [param peer_id] 当前连接。
## [param state] 同一事务玩家状态。
func _publish_food_status(peer_id: int, state: PlayerStateRecord) -> void:
	_send_reliable(peer_id, {"type": "player_panels",
		"result": _wire_result(_success(player_panel_service.build_bundle(state)))})


## 将食品事务资源同步回当前地图，热更新武器时保留射击冷却和维修状态。
## [param entity_id] 会话拥有的角色。
## [param state] 已提交的权威状态。
func _apply_food_runtime(entity_id: String, state: PlayerStateRecord) -> void:
	_refresh_achievement_combat(entity_id, state)
	var target := map_registry.instance_by_id(state.map_instance_id)
	if target == null:
		return
	var combat_state := target.vehicle_combat_state_for(entity_id)
	if combat_state != null:
		combat_state.health = clampi(state.vehicle_health, 0, combat_state.max_health)
		combat_state.reserve_energy = clampf(state.reserve_energy, 0.0, combat_state.reserve_energy_capacity)
		combat_state.working_energy = clampf(state.working_energy, 0.0, combat_state.working_energy_capacity)
