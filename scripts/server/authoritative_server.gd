class_name AuthoritativeServer
extends Node

const ConfigScript := preload("res://scripts/server/server_config.gd")
const MapInstanceScript := preload("res://scripts/server/authoritative_map_instance.gd")
const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const MapRegistryScript := preload("res://scripts/server/authoritative_map_registry.gd")
const SessionServiceScript := preload("res://scripts/server/session_service.gd")
const CommandRouterScript := preload("res://scripts/server/command_router.gd")
const SnapshotPublisherScript := preload("res://scripts/server/snapshot_publisher.gd")
const SimulationSchedulerScript := preload("res://scripts/server/simulation_scheduler.gd")
const MapTransitionCoordinatorScript := preload(
	"res://scripts/server/map_transition_coordinator.gd"
)
const ActorControllerRegistryScript := preload(
	"res://scripts/server/llm/actor_controller_registry.gd"
)
const LlmEventBusScript := preload("res://scripts/server/llm/llm_event_bus.gd")
const LlmWakeSchedulerScript := preload("res://scripts/server/llm/llm_wake_scheduler.gd")
const OpenAIResponsesLlmProviderScript := preload("res://scripts/server/llm/openai_responses_llm_provider.gd")
const LlmTraceLoggerScript := preload("res://scripts/server/llm/llm_trace_logger.gd")
const PlayerPanelCoordinatorScript := preload(
	"res://scripts/server/player_panels/player_panel_coordinator.gd"
)
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")
const MapJoinedContract := preload("res://scripts/network/contracts/map_joined.gd")
const MoveIntentContractScript := preload("res://scripts/network/contracts/move_intent.gd")
const MapTransitionIntentContractScript := preload(
	"res://scripts/network/contracts/map_transition_intent.gd"
)
const VehicleRecoveryIntentContract := preload(
	"res://scripts/network/contracts/vehicle_recovery_intent.gd"
)
const UseAbilityIntentContractScript := preload("res://scripts/network/contracts/use_ability_intent.gd")
const TransportEndpointScript := preload("res://scripts/network/transport/network_transport_endpoint.gd")
const CombatCatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const MiningCatalogScript := preload("res://scripts/domain/mining/mining_catalog.gd")
const MiningModuleScript := preload(
	"res://scripts/server/modules/mining/authoritative_mining_module.gd"
)
const PlayerStateRecordScript := preload("res://scripts/server/persistence/player_state_record.gd")
const InventoryStackRecordScript := preload(
	"res://scripts/server/persistence/inventory_stack_record.gd"
)
const EquipmentSlotRecordScript := preload(
	"res://scripts/server/persistence/equipment_slot_record.gd"
)
const FilePlayerStateRepositoryScript := preload("res://scripts/server/persistence/file_player_state_repository.gd")
const AutosaveServiceScript := preload("res://scripts/server/persistence/authoritative_autosave_service.gd")
const PersistenceCoordinatorScript := preload(
	"res://scripts/server/persistence/persistence_coordinator.gd"
)
const PlayerPanelServiceScript := preload("res://scripts/server/player_panels/authoritative_player_panel_service.gd")
const CommerceServiceScript := preload(
	"res://scripts/server/commerce/authoritative_commerce_service.gd"
)
const ManufacturingServiceScript := preload(
	"res://scripts/server/manufacturing/authoritative_manufacturing_service.gd"
)
const SlotMachineServiceScript := preload(
	"res://scripts/server/entertainment/authoritative_slot_machine_service.gd"
)
const GardenServiceScript := preload("res://scripts/server/garden/authoritative_garden_service.gd")
const PartyServiceScript := preload("res://scripts/server/social/authoritative_party_service.gd")
const ChatServiceScript := preload("res://scripts/server/social/authoritative_chat_service.gd")
const TradeServiceScript := preload("res://scripts/server/social/authoritative_trade_service.gd")
const FriendServiceScript := preload("res://scripts/server/social/authoritative_friend_service.gd")
const MailServiceScript := preload("res://scripts/server/social/authoritative_mail_service.gd")
const DomainResultScript := preload("res://scripts/core/domain_result.gd")
const RuntimeContentBootstrapScript := preload(
	"res://scripts/content/runtime_content_bootstrap.gd"
)
const PerformanceTelemetryScript := preload("res://scripts/core/performance_telemetry.gd")

signal command_rejected(peer_id: int, code: StringName)
signal server_message_generated(peer_id: int, message: Dictionary)
signal peer_world_snapshot_generated(peer_id: int, snapshot: Dictionary)
signal peer_local_snapshot_generated(peer_id: int, snapshot: Dictionary)

const TRANSPORT_SESSION_REQUEST := &"session_request"
const TRANSPORT_PLAYER_PANEL_COMMAND := &"player_panel_command"
const BASE_HALL_MAP_ID := "yian_harbor_hall_floor_1"
const VEHICLE_RECOVERY_DELAY_SECONDS := 3.0
const LLM_LOW_FREQUENCY_WAKE_SECONDS := 15.0
const LLM_DAMAGE_MERGE_SECONDS := 0.6
const LLM_DAMAGE_COOLDOWN_SECONDS := 5.0
const VEHICLE_RECOVERY_HEALTH_RATIO := 0.10
const LLM_OBSERVATION_INTERVAL_SECONDS := 1.0
const GLORY_RUNTIME_MAP_INDEX_PATH := "res://data/content/glory_map_runtime_index_v1.json"
const LLM_NPC_CATALOG_PATH := "res://data/npcs/yian_harbor_hall_floor_1.json"

var _food_runtime: AuthoritativeFoodRuntime
var _production_runtime: AuthoritativeProductionRuntime
var _exit_service: AuthoritativeExitService
var config: DedicatedServerConfig
var map_instance: AuthoritativeMapInstance
var map_registry: AuthoritativeMapRegistry
var sessions: SessionService
var server_tick := 0
var emitted_snapshot_count := 0
var _simulation_scheduler: SimulationScheduler
var _next_entity_number := 1
var _network_started := false
var _transport_endpoint: NetworkTransportEndpoint
var _combat_catalog
var _mining_catalog
var player_state_repository: PlayerStateRepository
var autosave_service: AuthoritativeAutosaveService
var _ground_cleanup_at := (floori(Time.get_unix_time_from_system() / PlayerStateRepository.GROUND_CLEAR_INTERVAL) + 1) * PlayerStateRepository.GROUND_CLEAR_INTERVAL
var player_panel_service: AuthoritativePlayerPanelService
var reward_service := AuthoritativeRewardService.new()
var commerce_service
var manufacturing_service
var warehouse_service: PersonalWarehouseService
var slot_machine_service: AuthoritativeSlotMachineService
var garden_service: AuthoritativeGardenService
var party_service: AuthoritativePartyService
var chat_service: AuthoritativeChatService
var trade_service: AuthoritativeTradeService
var friend_service: AuthoritativeFriendService
var mail_service: AuthoritativeMailService
var _kill_progression: AuthoritativeKillProgression
var _pending_player_changes: Dictionary[String, PlayerChange] = {}
var _pending_level_ups: Array[Dictionary] = []
var _published_player_revisions: Dictionary[String, int] = {}
var _pending_vehicle_recoveries: Dictionary = {}
var _llm_damage_episodes: Dictionary = {}
var _llm_death_notified: Dictionary = {}
var _llm_social_origin_actor := ""
var _llm_combat_event_cursors: Dictionary = {}
var _llm_hunt_behaviors: Dictionary = {}
var _llm_pending_intents: Dictionary = {}
var _pending_runtime_maps: Dictionary[String, Dictionary] = {}
var _llm_observation_accumulator := 0.0
var _runtime_definition_paths_by_map_id: Dictionary = {}
var _llm_npc_catalog: Dictionary = {}
var _llm_event_bus: LlmEventBus
var _llm_wake_scheduler: LlmWakeScheduler
var _runtime_map_ids_by_legacy_world: Dictionary = {}
var _default_map_id := ""
var _actor_controller_registry: ActorControllerRegistry
var _command_router: CommandRouter
var _snapshot_publisher: SnapshotPublisher
var _persistence_coordinator: PersistenceCoordinator
var _map_transition_coordinator: MapTransitionCoordinator
var _player_panel_coordinator: PlayerPanelCoordinator


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
	var npc_catalog_result := JsonConfigLoader.load_dictionary(LLM_NPC_CATALOG_PATH)
	if not npc_catalog_result.is_ok:
		return _failure(npc_catalog_result.error_code, npc_catalog_result.error_message)
	_llm_npc_catalog = npc_catalog_result.value
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
	sessions = SessionServiceScript.new()
	sessions.configure(config.reconnect_grace_seconds)
	_pending_vehicle_recoveries.clear()
	_published_player_revisions.clear()
	_pending_player_changes.clear()
	_pending_level_ups.clear()
	_llm_combat_event_cursors.clear()
	_llm_hunt_behaviors.clear()
	_llm_observation_accumulator = 0.0
	_actor_controller_registry = ActorControllerRegistryScript.new()
	var actor_controller_result := _actor_controller_registry.configure()
	if not actor_controller_result.is_ok:
		return _failure(actor_controller_result.error_code, actor_controller_result.error_message)
	_llm_event_bus = LlmEventBusScript.new()
	var event_bus_result := _llm_event_bus.configure(Callable(self, "_deliver_llm_event"))
	if not event_bus_result.is_ok:
		return _failure(event_bus_result.error_code, event_bus_result.error_message)
	_llm_wake_scheduler = LlmWakeSchedulerScript.new()
	var wake_scheduler_result := _llm_wake_scheduler.configure(Callable(self, "_wake_llm_for_low_frequency_review"))
	if not wake_scheduler_result.is_ok:
		return _failure(wake_scheduler_result.error_code, wake_scheduler_result.error_message)
	var persistence_result := _initialize_persistence(injected_repository)
	if not persistence_result.ok:
		return persistence_result
	var reward_result := reward_service.initialize(autosave_service)
	if not reward_result.is_ok:
		return _failure(reward_result.error_code, reward_result.error_message)
	player_panel_service = PlayerPanelServiceScript.new()
	var panel_result = player_panel_service.initialize(reward_service.pipeline)
	if autosave_service != null: autosave_service.mapper = PlayerStateMapper.new(player_panel_service.catalog, reward_service.pipeline)
	if not panel_result.is_ok:
		return _failure(panel_result.error_code, panel_result.error_message)
	if player_state_repository != null: _ground_cleanup_at = player_state_repository.ground_cleanup_at
	for instance: AuthoritativeMapInstance in map_registry.all_instances():
		var restored := _restore_ground_items(instance)
		if not restored.is_ok: return _failure(restored.error_code, restored.error_message)
	_persistence_coordinator = PersistenceCoordinatorScript.new()
	var persistence_coordinator_result := _persistence_coordinator.configure(
		autosave_service,
		player_state_repository,
		Callable(self, "_capture_player_runtime"),
	)
	if not persistence_coordinator_result.is_ok:
		return _failure(
			persistence_coordinator_result.error_code,
			persistence_coordinator_result.error_message,
		)
	slot_machine_service = SlotMachineServiceScript.new(player_panel_service.catalog)
	var garden_catalog := BotanicalGardenCatalog.load_default()
	if not garden_catalog.is_ok:
		return _failure(garden_catalog.error_code, garden_catalog.error_message)
	garden_service = GardenServiceScript.new(garden_catalog.value)
	party_service = PartyServiceScript.new()
	var party_result := party_service.configure(
		Callable(sessions, "session_for_entity"),
		Callable(self, "_party_map_for_entity"),
		Callable(self, "_party_display_name_for_entity"),
		Callable(self, "_party_entity_is_active"),
		Callable(self, "_send_party_message"),
	)
	if not party_result.is_ok:
		return _failure(party_result.error_code, party_result.error_message)
	chat_service = ChatServiceScript.new()
	var chat_result := chat_service.configure(
		Callable(sessions, "session_for_entity"),
		Callable(self, "_party_map_for_entity"),
		Callable(self, "_party_display_name_for_entity"),
		Callable(self, "_chat_entities_in_map"),
		Callable(self, "_party_entity_is_active"),
		Callable(self, "_send_party_message"),
		Callable(party_service, "active_members_for"),
		config.player_state_store_path + ".chat" if config.persistence_enabled else "",
	)
	if not chat_result.is_ok:
		return _failure(chat_result.error_code, chat_result.error_message)
	trade_service = TradeServiceScript.new()
	var trade_result := trade_service.configure(
		Callable(sessions, "session_for_entity"),
		Callable(self, "_party_map_for_entity"),
		Callable(self, "_party_display_name_for_entity"),
		Callable(self, "_party_entity_is_active"),
		Callable(self, "_validate_trade_item"),
		Callable(self, "_validate_trade_currency"),
		Callable(self, "_trade_inventory_revision"),
		Callable(self, "_commit_trade"),
		Callable(self, "_send_party_message"),
	)
	if not trade_result.is_ok:
		return _failure(trade_result.error_code, trade_result.error_message)
	friend_service = FriendServiceScript.new()
	var friend_result := friend_service.configure(
		Callable(self, "_friend_player_for_entity"),
		Callable(self, "_party_map_for_entity"),
		Callable(self, "_party_display_name_for_entity"),
		Callable(self, "_party_entity_is_active"),
		Callable(self, "_commit_friend_relation"),
		Callable(self, "_send_party_message"),
		Callable(self, "_find_active_entities_by_display_name"),
	)
	if not friend_result.is_ok:
		return _failure(friend_result.error_code, friend_result.error_message)
	mail_service = MailServiceScript.new()
	var mail_result := mail_service.configure(
		Callable(self, "_friend_player_for_entity"),
		Callable(self, "_mailbox_for_entity"),
		Callable(self, "_party_display_name_for_entity"),
		Callable(self, "_party_entity_is_active"),
		Callable(self, "_commit_mailbox"),
		Callable(self, "_send_party_message"),
		Callable(self, "_find_entities_by_display_name"),
	)
	if not mail_result.is_ok:
		return _failure(mail_result.error_code, mail_result.error_message)
	for instance: AuthoritativeMapInstance in map_registry.all_instances():
		instance.set_loot_recipient_resolver(Callable(party_service, "loot_recipients_for"))
		if instance.combat_module != null:
			instance.combat_module.rewards = reward_service
	commerce_service = CommerceServiceScript.new()
	var commerce_result: DomainResult = commerce_service.initialize(reward_service.pipeline)
	if not commerce_result.is_ok:
		return _failure(commerce_result.error_code, commerce_result.error_message)
	manufacturing_service = ManufacturingServiceScript.new()
	_kill_progression = AuthoritativeKillProgression.new(commerce_service.quests, commerce_service.daily)
	var manufacturing_result: DomainResult = manufacturing_service.initialize(reward_service.pipeline)
	if not manufacturing_result.is_ok:
		return _failure(manufacturing_result.error_code, manufacturing_result.error_message)
	warehouse_service = PersonalWarehouseService.new()
	var warehouse_result := warehouse_service.initialize(reward_service.pipeline)
	if not warehouse_result.is_ok:
		return _failure(warehouse_result.error_code, warehouse_result.error_message)
	if autosave_service != null:
		_production_runtime = AuthoritativeProductionRuntime.new(autosave_service, sessions, manufacturing_service,
			_capture_player_runtime, _publish_production)
		_production_runtime.failed.connect(_publish_production_failure)
	_exit_service = AuthoritativeExitService.new(autosave_service, _capture_player_runtime, _release_exited_player)
	_command_router = CommandRouterScript.new()
	var command_router_result := _command_router.configure(
		Callable(self, "open_session"),
		Callable(self, "handle_peer_move"),
		Callable(self, "handle_peer_use_ability"),
		Callable(self, "handle_peer_loot_pickup"),
		Callable(self, "handle_peer_vehicle_recovery"),
		Callable(self, "handle_peer_player_panel_command"),
		Callable(self, "handle_peer_map_transition"),
		Callable(self, "_send_reliable"),
		Callable(self, "_wire_result"),
		Callable(self, "handle_peer_social_command"),
	)
	if not command_router_result.is_ok:
		return _failure(command_router_result.error_code, command_router_result.error_message)
	_snapshot_publisher = SnapshotPublisherScript.new()
	_snapshot_publisher.peer_world_snapshot_generated.connect(_forward_peer_world_snapshot_generated)
	_snapshot_publisher.peer_local_snapshot_generated.connect(_forward_peer_local_snapshot_generated)
	var snapshot_publisher_result := _snapshot_publisher.configure(
		Callable(map_registry, "all_instances"),
		Callable(sessions, "active_sessions"),
		Callable(self, "_build_shared_snapshot"),
		Callable(self, "_build_local_snapshot"),
		Callable(self, "_send_peer_world_snapshot"),
		Callable(self, "_send_peer_local_snapshot"),
	)
	if not snapshot_publisher_result.is_ok:
		return _failure(snapshot_publisher_result.error_code, snapshot_publisher_result.error_message)
	_map_transition_coordinator = MapTransitionCoordinatorScript.new()
	var map_transition_result := _map_transition_coordinator.configure(
		Callable(sessions, "session_for_peer"),
		Callable(map_registry, "instance_by_id"),
		Callable(self, "_resolve_or_load_transition_target"),
		Callable(self, "_player_for_transition"),
		Callable(self, "_capture_player_runtime"),
		Callable(self, "_commit_transition_player"),
		Callable(self, "_prepare_entity_combat_loadout"),
	)
	if not map_transition_result.is_ok:
		return _failure(map_transition_result.error_code, map_transition_result.error_message)
	_player_panel_coordinator = PlayerPanelCoordinatorScript.new()
	var player_panel_result := _player_panel_coordinator.configure(
		Callable(sessions, "session_for_peer"),
		Callable(self, "_player_for_panel"),
		Callable(self, "_panel_persistence_available"),
		Callable(map_registry, "instance_by_id"),
		Callable(_exit_service, "execute"),
		Callable(self, "_capture_player_runtime"),
		Callable(self, "_commit_panel_player"),
		Callable(self, "_update_panel_runtime"),
		Callable(self, "_scene_players_for_panel"),
		Callable(self, "_build_entity_combat_loadout"),
		Callable(self, "_apply_food_runtime"),
		Callable(self, "_send_reliable"),
		Callable(self, "_wire_result"),
		Callable(self, "_queue_player_change"),
		Callable(self, "_flush_player_changes"),
		player_panel_service,
		commerce_service,
		manufacturing_service,
		warehouse_service,
		slot_machine_service,
		garden_service,
	)
	if not player_panel_result.is_ok:
		return _failure(player_panel_result.error_code, player_panel_result.error_message)
	_simulation_scheduler = SimulationSchedulerScript.new()
	var simulation_scheduler_result := _simulation_scheduler.configure(
		config.simulation_hz,
		config.snapshot_hz,
		Callable(self, "_advance_simulation_frame"),
		Callable(self, "_simulate_scheduled_tick"),
		Callable(self, "_publish_scheduled_snapshot"),
		Callable(self, "_capture_persistence"),
		Callable(self, "_cleanup_expired_sessions"),
		Callable(self, "_diagnostic_entity_counts"),
	)
	if not simulation_scheduler_result.is_ok:
		return _failure(simulation_scheduler_result.error_code, simulation_scheduler_result.error_message)
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
	_transport_endpoint.social_command_received.connect(_on_transport_social_command)
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
	if sessions == null or _simulation_scheduler == null:
		return
	var result := _simulation_scheduler.advance(elapsed_seconds, now_msec)
	if not result.is_ok:
		push_error("Authoritative simulation scheduler failed [%s]: %s" % [
			result.error_code, result.error_message,
		])


func _clear_due_ground_items(now_unix: int = -1) -> void:
	var now := int(Time.get_unix_time_from_system()) if now_unix < 0 else now_unix
	if now < _ground_cleanup_at: return
	_ground_cleanup_at = (floori(float(now) / PlayerStateRepository.GROUND_CLEAR_INTERVAL) + 1) * PlayerStateRepository.GROUND_CLEAR_INTERVAL
	if player_state_repository != null:
		player_state_repository.ground_items = {}
		player_state_repository.ground_cleanup_at = _ground_cleanup_at
		player_state_repository.ground_dirty = true
	if map_registry != null:
		for instance: AuthoritativeMapInstance in map_registry.all_instances() + map_registry._dormant_by_map_id.values():
			if instance.combat_module != null: instance.combat_module.clear_ground_items()


func _restore_ground_items(instance: AuthoritativeMapInstance) -> DomainResult:
	if player_state_repository == null or instance.combat_module == null: return DomainResult.ok()
	var entries: Dictionary = player_state_repository.ground_items.get(String(instance.definition.map_id), {})
	for loot_id: String in entries:
		var entry: Dictionary = entries[loot_id]
		var record := InventoryStackRecord.from_dictionary(entry.item)
		if not record.is_ok: return record
		var created := player_panel_service.catalog.create(record.value.item_definition_id, record.value.item_state())
		if not created.is_ok: return created
		instance.combat_module.drop_item(loot_id, instance.instance_id, created.value, Vector2(entry.position[0], entry.position[1]))
	return DomainResult.ok()


func _advance_simulation_frame(elapsed_seconds: float) -> void:
	_clear_due_ground_items()
	_advance_food_status()
	if _llm_wake_scheduler != null:
		var wake_result := _llm_wake_scheduler.advance(elapsed_seconds)
		if not wake_result.is_ok:
			push_error("LLM wake scheduler failed [%s]: %s" % [wake_result.error_code, wake_result.error_message])
	_advance_llm_observations(elapsed_seconds)
	if _production_runtime != null: _production_runtime.advance(elapsed_seconds)


func _advance_llm_observations(elapsed_seconds: float) -> void:
	if _actor_controller_registry == null or elapsed_seconds <= 0.0:
		return
	_llm_observation_accumulator += elapsed_seconds
	if _llm_observation_accumulator < LLM_OBSERVATION_INTERVAL_SECONDS:
		return
	_llm_observation_accumulator = fmod(
		_llm_observation_accumulator, LLM_OBSERVATION_INTERVAL_SECONDS
	)
	for actor_id: String in _actor_controller_registry.actor_ids():
		var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
		if controller == null or controller.active_turn() != null:
			continue
		var session := sessions.session_for_entity(actor_id)
		if session == null or session.has_active_peer():
			continue
		var observed := observe_llm_player(actor_id)
		if not observed.is_ok:
			push_error("LLM observation refresh failed [%s]: %s" % [
				observed.error_code, observed.error_message,
			])


func _wake_llm_for_low_frequency_review(actor_id: String) -> DomainResult:
	if _actor_controller_registry == null or not _actor_controller_registry.has_controller(actor_id):
		return DomainResultScript.ok({"skipped": true})
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	var session := sessions.session_for_entity(actor_id) if sessions != null else null
	if controller == null or session == null or session.has_active_peer() \
			or controller.active_turn() != null or not controller.safe_idle:
		return DomainResultScript.ok({"skipped": true})
	return _queue_llm_runtime_event(actor_id, &"periodic_review", {"reason": "low_frequency"})


func _simulate_scheduled_tick(tick: int, fixed_delta: float) -> bool:
	server_tick = tick
	_simulate_world(fixed_delta)
	return _settle_domain_events()


func _simulate_world(fixed_delta: float) -> void:
	var simulation_started_at := PerformanceTelemetryScript.begin(&"server_simulate_world")
	map_registry.suspend_empty_instances(server_tick - 1)
	var llm_actor_ids_by_map: Dictionary = {}
	if _actor_controller_registry != null:
		for actor_id: String in _actor_controller_registry.actor_ids():
			var session: ServerSession = sessions.session_for_entity(actor_id)
			if session == null or session.has_active_peer():
				continue
			var actor_ids: Array = llm_actor_ids_by_map.get(session.map_instance_id, [])
			actor_ids.append(actor_id)
			llm_actor_ids_by_map[session.map_instance_id] = actor_ids
	for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
		var arrival_targets: Dictionary = {}
		for actor_id: String in llm_actor_ids_by_map.get(registered_instance.instance_id, []):
			var entity: AuthoritativeEntity = registered_instance.entities.get(actor_id)
			if _llm_pending_intents.has(actor_id):
				var pending: Dictionary = _llm_pending_intents[actor_id]
				if pending.map_instance_id != registered_instance.instance_id:
					_queue_llm_runtime_event(actor_id, &"action_invalidated", {"reason": "map_changed"})
					continue
				arrival_targets[actor_id] = pending.target_position
			elif entity != null and entity.action == &"walking":
				arrival_targets[actor_id] = entity.target_position
		registered_instance.simulate(fixed_delta)
		_publish_llm_arrivals(registered_instance, arrival_targets)
		_publish_llm_vital_events(
			registered_instance,
			llm_actor_ids_by_map.get(registered_instance.instance_id, []),
		)
		_advance_llm_hunt_behaviors(
			registered_instance,
			llm_actor_ids_by_map.get(registered_instance.instance_id, []),
		)
	PerformanceTelemetryScript.end(&"server_simulate_world", simulation_started_at)


func _publish_llm_arrivals(instance: AuthoritativeMapInstance, targets: Dictionary) -> void:
	for raw_actor_id: Variant in targets:
		var actor_id := String(raw_actor_id)
		var entity: AuthoritativeEntity = instance.entities.get(actor_id)
		var target: Vector2 = targets[raw_actor_id]
		var vehicle := instance.vehicle_combat_state_for(actor_id)
		if entity == null or entity.action == &"walking" or (instance.is_vehicle_combat_active() and vehicle != null and vehicle.health <= 0):
			continue
		if _llm_pending_intents.has(actor_id) and entity.position.distance_squared_to(target) <= 0.0001:
			var pending: Dictionary = _llm_pending_intents[actor_id]
			var loading: Thread = _pending_runtime_maps.get(String(pending.intent.payload.get("destination_map_instance_id", "")).trim_suffix(".instance.1"), {}).get("thread")
			if loading != null and loading.is_alive(): continue
			_llm_pending_intents.erase(actor_id)
			var executed: DomainResult = (DomainResultScript.ok() if pending.intent.intent_kind == &"move" else handle_llm_player_intent(pending.intent)) if pending.map_instance_id == instance.instance_id else DomainResultScript.failure(&"llm.map_changed", "交互期间所在地图已变化")
			if not executed.is_ok or pending.intent.intent_kind in [&"loot", &"move"]:
				_queue_llm_runtime_event(actor_id, &"action_result" if executed.is_ok else &"action_invalidated", {
					"action": String(pending.intent.intent_kind), "ok": executed.is_ok,
					"error_code": String(executed.error_code), "message": executed.error_message,
				})
			continue
		if _llm_hunt_behaviors.has(actor_id) and entity.position.distance_squared_to(target) <= 0.0001:
			continue
		queue_llm_event(actor_id, {
			"event_id": "%s.arrived.%d.%d" % [actor_id, server_tick, entity.last_input_sequence],
			"event_kind": "destination_reached" if entity.position.distance_squared_to(target) <= 0.0001 else "action_invalidated",
			"payload": {
				"map_id": String(instance.definition.map_id),
				"position": [entity.position.x, entity.position.y],
			},
		})


func _queue_llm_runtime_event(
	actor_id: String,
	event_kind: StringName,
	payload: Dictionary = {},
) -> DomainResult:
	if _actor_controller_registry == null or not _actor_controller_registry.has_controller(actor_id):
		return DomainResultScript.ok()
	return queue_llm_event(actor_id, {
		"event_id": "%s.%s.%d.%d" % [actor_id, String(event_kind), server_tick, Time.get_ticks_usec()],
		"event_kind": event_kind,
		"payload": payload,
	})


func _publish_llm_vital_events(instance: AuthoritativeMapInstance, actor_ids: Array) -> void:
	if not instance.is_vehicle_combat_active(): return
	for actor_id: String in actor_ids:
		var vehicle: VehicleCombatState = instance.vehicle_combat_state_for(actor_id)
		if vehicle == null or vehicle.max_health <= 0:
			continue
		if vehicle.health <= 0:
			_llm_damage_episodes.erase(actor_id)
			if not _llm_death_notified.has(actor_id):
				_llm_death_notified[actor_id] = true
				var player := autosave_service.player_for(actor_id) if autosave_service != null else null
				if player != null: _capture_player_runtime(player, ["vehicle"])
				_queue_llm_runtime_event(actor_id, &"death", {"health": vehicle.health, "max_health": vehicle.max_health})
			continue
		_llm_death_notified.erase(actor_id)


func _publish_llm_combat_events(instance: AuthoritativeMapInstance) -> void:
	if instance == null or instance.combat_module == null or _actor_controller_registry == null:
		return
	var module = instance.combat_module
	if not _llm_combat_event_cursors.has(instance.instance_id):
		_llm_combat_event_cursors[instance.instance_id] = module.event_sequence
		return
	var cursor := int(_llm_combat_event_cursors[instance.instance_id])
	var pending_by_actor: Dictionary = {}
	var pending_repairs: Array[Dictionary] = []
	for event: Dictionary in module.combat_events:
		var event_id := int(event.get("event_id", 0))
		if event_id <= cursor:
			continue
		cursor = maxi(cursor, event_id)
		var event_type := String(event.get("event_type", ""))
		if event_type == "self_repair_stopped" \
				and String(event.get("reason", "")) in ["full_health", "insufficient_working_energy"]:
			var repair_actor_id := String(event.get("actor_id", ""))
			if _actor_controller_registry.has_controller(repair_actor_id):
				pending_repairs.append({"actor_id": repair_actor_id, "reason": String(event.reason)})
		if event_type == "monster_attack_resolved" and int(event.get("damage", 0)) > 0:
			_record_llm_damage(instance, event)
		if not (event_type.ends_with("_hit") or event_type.ends_with("_projectile_expired") \
				or event_type in ["monster_attack_resolved", "monster_attack_expired"]):
			continue
		var summary := {
			"combat_event_id": event_id,
			"event_type": event_type,
			"attacker_id": String(event.get("attacker_id", "")),
			"target_entity_id": String(event.get("target_entity_id", "")),
			"damage": int(event.get("damage", 0)),
			"target_health": int(event.get("target_health", -1)),
			"target_destroyed": bool(event.get("target_destroyed", false)) or event.has("death"),
		}
		if not bool(summary["target_destroyed"]):
			continue
		if event.has("death"):
			summary["death"] = event["death"].duplicate(true)
			var monster: MonsterLifecycle = module.monster_for(String(summary.target_entity_id))
			if monster != null: summary.merge({"species_id": monster.species_id, "display_name": monster.display_name})
		var actor_id := String(summary["attacker_id"])
		if actor_id.is_empty() or not _actor_controller_registry.has_controller(actor_id) \
				or _llm_hunt_behaviors.has(actor_id):
			continue
		var session := sessions.session_for_entity(actor_id)
		if session == null or session.map_instance_id != instance.instance_id:
			continue
		var events: Array = pending_by_actor.get(actor_id, [])
		events.append(summary.duplicate(true))
		pending_by_actor[actor_id] = events
	_llm_combat_event_cursors[instance.instance_id] = cursor
	for repair: Dictionary in pending_repairs:
		_queue_llm_runtime_event(String(repair.actor_id), &"self_repair_stopped", {
			"reason": repair.reason,
		})
	for actor_id: String in pending_by_actor:
		queue_llm_event(actor_id, {
			"event_id": "%s.combat.%d" % [actor_id, cursor],
			"event_kind": "combat_result",
			"payload": {"events": pending_by_actor[actor_id]},
		})


func _record_llm_damage(instance: AuthoritativeMapInstance, event: Dictionary) -> void:
	var actor_id := String(event.get("target_entity_id", ""))
	if not _actor_controller_registry.has_controller(actor_id) or _llm_death_notified.has(actor_id):
		return
	var session := sessions.session_for_entity(actor_id)
	if session == null or session.has_active_peer() or session.map_instance_id != instance.instance_id:
		return
	var species_id := String(event.get("species_id", ""))
	if species_id.is_empty(): return
	var episode: Dictionary = _llm_damage_episodes.get(actor_id, {})
	if episode.is_empty():
		episode = {"next_notify_tick": server_tick, "hit_count": 0, "total_damage": 0, "species": {}}
	if int(episode.hit_count) == 0: episode["first_tick"] = server_tick
	episode["hit_count"] = int(episode.hit_count) + 1
	episode["total_damage"] = int(episode.total_damage) + int(event.damage)
	var species: Dictionary = episode.species
	species[species_id] = int(species.get(species_id, 0)) + 1
	_llm_damage_episodes[actor_id] = episode


func _flush_llm_damage_episodes() -> void:
	for actor_id: String in _llm_damage_episodes.keys():
		var episode: Dictionary = _llm_damage_episodes[actor_id]
		if server_tick < int(episode.next_notify_tick): continue
		if int(episode.hit_count) == 0:
			_llm_damage_episodes.erase(actor_id)
			continue
		if server_tick - int(episode.first_tick) < roundi(LLM_DAMAGE_MERGE_SECONDS * config.simulation_hz): continue
		var session := sessions.session_for_entity(actor_id)
		var instance: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id) if session != null else null
		var vehicle: VehicleCombatState = instance.vehicle_combat_state_for(actor_id) if instance != null else null
		if vehicle == null or vehicle.health <= 0:
			_llm_damage_episodes.erase(actor_id)
			continue
		var attackers: Array[Dictionary] = []
		var species_ids: Array = episode.species.keys()
		species_ids.sort()
		for species_id: String in species_ids:
			attackers.append({"species_id": species_id, "hit_count": episode.species[species_id]})
		var queued := _queue_llm_runtime_event(actor_id, &"under_attack", {
			"hit_count": episode.hit_count, "total_damage": episode.total_damage,
			"health": vehicle.health, "max_health": vehicle.max_health, "attackers": attackers,
		})
		if queued.is_ok:
			_llm_damage_episodes[actor_id] = {"next_notify_tick": server_tick + roundi(LLM_DAMAGE_COOLDOWN_SECONDS * config.simulation_hz),
				"hit_count": 0, "total_damage": 0, "species": {}}


func _settle_domain_events() -> bool:
	var settle_started_at := PerformanceTelemetryScript.begin(&"server_settle_domain_events")
	var population_refresh_happened := false
	for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
		var refreshed := registered_instance.consume_population_refresh_flag()
		population_refresh_happened = refreshed or population_refresh_happened
		_settle_mining_cycles(registered_instance)
		_settle_equipment_conditions(registered_instance)
		_publish_llm_combat_events(registered_instance)
		for progression_event: Dictionary in registered_instance.drain_skill_progression_events():
			_apply_skill_progression_event(progression_event)
		for quest_kill: Dictionary in registered_instance.drain_quest_kills():
			_apply_quest_kill(quest_kill)
	_flush_llm_damage_episodes()
	_flush_player_changes()
	_complete_due_vehicle_recoveries()
	PerformanceTelemetryScript.end(&"server_settle_domain_events", settle_started_at)
	return population_refresh_happened


func _publish_scheduled_snapshot(_tick: int) -> void:
	_emit_snapshot()


func _capture_persistence(elapsed_seconds: float, population_refresh_happened: bool) -> void:
	if _persistence_coordinator == null:
		push_error("Authoritative persistence coordinator is unavailable")
		return
	var autosave_result := _persistence_coordinator.advance(
		elapsed_seconds, population_refresh_happened,
	)
	if not autosave_result.is_ok:
		push_error("Authoritative autosave failed [%s]: %s" % [
			autosave_result.error_code, autosave_result.error_message,
		])


func _cleanup_expired_sessions(cleanup_time: int) -> void:
	if _persistence_coordinator != null:
		for expiring_session: ServerSession in sessions.all_sessions():
			if (
				not expiring_session.has_active_peer()
				and expiring_session.expires_at_msec >= 0
				and cleanup_time > expiring_session.expires_at_msec
			):
				var save_result := _persistence_coordinator.save_expired_player(expiring_session.entity_id)
				if not save_result.is_ok:
					push_error("Expired player persistence failed [%s]: %s" % [
						save_result.error_code, save_result.error_message,
					])
	for entity_id in sessions.cleanup_expired(cleanup_time):
		if party_service != null:
			party_service.remove_expired_entity(entity_id)
		if trade_service != null:
			trade_service.remove_expired_entity(entity_id)
		if friend_service != null:
			friend_service.remove_expired_entity(entity_id)
		if chat_service != null:
			chat_service.remove_expired_entity(entity_id)
		if mail_service != null:
			mail_service.remove_expired_entity(entity_id)
		if autosave_service != null:
			autosave_service.unregister_player(entity_id)
		_remove_entity_from_registered_map(entity_id)


func _diagnostic_entity_counts() -> Dictionary:
	var monster_count := 0
	for instance: AuthoritativeMapInstance in map_registry.all_instances():
		if instance.combat_module != null:
			monster_count += instance.combat_module.monsters.size()
	return {
		"player_count": sessions.active_sessions().size(),
		"monster_count": monster_count,
	}


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
	var requested_display_name := String(request.get("display_name", "")).strip_edges()
	if requested_display_name.length() > 64 or "\n" in requested_display_name or "\r" in requested_display_name:
		return _failure(&"invalid_display_name", "display name is invalid")
	var reconnect_token := String(request.get("reconnect_token", ""))
	if not reconnect_token.is_empty():
		var reconnecting_session := sessions.session_for_reconnect_token(reconnect_token)
		if reconnecting_session != null and _actor_controller_registry != null \
				and _actor_controller_registry.has_controller(reconnecting_session.entity_id):
			return _failure(&"llm.actor_controlled", "LLM-controlled actor cannot be reclaimed by a Human session")
		var reconnect_result := sessions.reconnect(peer_id, reconnect_token, current_time)
		if not reconnect_result.ok:
			return reconnect_result
		if _exit_service != null: _exit_service.forget(peer_id)
		if party_service != null: party_service.refresh_presence(reconnect_result.value.entity_id)
		if friend_service != null: friend_service.refresh_presence(reconnect_result.value.entity_id)
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
		requested_display_name,
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
	if persistence_state_result.value is Player:
		_restore_persistent_player_state(session_result.value, persistence_state_result.value)
	if _exit_service != null: _exit_service.forget(peer_id)
	return _session_response(session_result.value, false)


## 执行 `disconnect_session` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param now_msec] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func disconnect_session(peer_id: int, now_msec := -1) -> Dictionary:
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	var session := sessions.session_for_peer(peer_id)
	if _production_runtime != null and session != null:
		_production_runtime.interrupt(session.entity_id, "断线后生产已暂停")
	if party_service != null and session != null:
		party_service.cancel_invites_for_entity(session.entity_id, "session_disconnected")
	if friend_service != null and session != null:
		friend_service.cancel_invites_for_entity(session.entity_id, "session_disconnected")
	if trade_service != null and session != null:
		trade_service.cancel_for_entity(session.entity_id, "session_disconnected")
	var disconnected := sessions.mark_disconnected(peer_id, current_time)
	if disconnected.ok and session != null:
		if party_service != null: party_service.refresh_presence(session.entity_id)
		if friend_service != null: friend_service.refresh_presence(session.entity_id)
	return disconnected


## 校验并处理 `handle_peer_move` 对应的模块状态。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func handle_peer_move(peer_id: int, intent: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"unauthenticated_peer", "open a session before sending movement")
	return _handle_entity_move(session.entity_id, intent, peer_id)


func _handle_entity_move(actor_id: String, intent: Dictionary, peer_id := -1) -> Dictionary:
	var session: ServerSession = sessions.session_for_entity(actor_id)
	if session == null:
		return _failure(&"unauthenticated_actor", "actor has no authoritative session")
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		return _failure(&"session_map_unavailable", "session map is not registered")
	if peer_id <= 0 and current_instance.entities.has(actor_id):
		intent = intent.duplicate(true)
		intent["input_sequence"] = maxi(int(intent.get("input_sequence", 0)), current_instance.entities[actor_id].last_input_sequence + 1)
	var result := current_instance.handle_move_intent(actor_id, intent)
	if not result.ok and peer_id > 0:
		command_rejected.emit(peer_id, result.code)
	return result


## 从服务器配置加载一个 OpenAI Responses provider；密钥只读取用户文件。
func create_openai_llm_provider(config_path := "") -> DomainResult:
	var path := config_path.strip_edges()
	if path.is_empty():
		path = config.llm_config_path if config != null else ""
	return OpenAIResponsesLlmProviderScript.from_file(path)


## 从 LLM 自己的权威地图实例解析观察到的出口，不依赖人类客户端正在显示的地图。
func resolve_llm_area(area_id: String, frame: Dictionary) -> DomainResult:
	var actor_id := String(frame.get("actor_id", ""))
	var session: ServerSession = sessions.session_for_entity(actor_id) if sessions != null else null
	if session == null or not session.is_llm:
		return DomainResultScript.failure(&"llm.actor_missing", "LLM actor has no authoritative session")
	var source: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id)
	if source == null or String(frame.get("map_instance_id", "")) != source.instance_id \
			or String(frame.get("map_id", "")) != String(source.definition.map_id):
		return DomainResultScript.failure(&"llm.travel_stale", "area observation is no longer current")
	var normalized := area_id.strip_edges().to_lower()
	if normalized in ["current", "stay", String(source.definition.map_id).to_lower()]:
		var entity: AuthoritativeEntity = source.entities.get(actor_id)
		if entity == null:
			return DomainResultScript.failure(&"llm.entity_missing", "actor is not in its current map")
		return DomainResultScript.ok({
			"map_instance_id": source.instance_id,
			"target_position": entity.position,
		})
	var visible_ids: Array[String] = []
	for raw_transition: Variant in frame.get("available_transitions", []):
		if raw_transition is Dictionary:
			visible_ids.append(String(raw_transition.get("transition_id", "")))
	for transition: MapTransition in source.definition.enabled_transitions():
		if String(transition.transition_id) not in visible_ids:
			continue
		if normalized in [
			String(transition.transition_id).to_lower(),
			transition.destination_key().to_lower(),
			transition.label.strip_edges().to_lower(),
		]:
			var target_map_id := _target_map_id_for_transition(transition, source.definition.world_id)
			if target_map_id.is_empty() or not _runtime_definition_paths_by_map_id.has(target_map_id):
				return DomainResultScript.failure(&"llm.area_unknown", "出口目标不在受控地图目录中")
			var approach_point := transition.approach_point
			if approach_point.is_zero_approx():
				approach_point = transition.source_anchor
			if not approach_point.is_finite():
				return DomainResultScript.failure(&"llm.transition_unavailable", "出口没有有效的接近位置")
			return DomainResultScript.ok({
				"map_instance_id": "%s.instance.1" % target_map_id,
				"target_position": approach_point,
				"transition_id": String(transition.transition_id),
				"destination_entry_number": transition.destination_entry_number,
			})
	return DomainResultScript.failure(&"llm.area_unknown", "当前场景没有匹配的可用出口")


## 创建并上线一个独立的 LLM 玩家；角色身份、存档和会话不依赖模型 provider。
## [param actor_id] 稳定的 `llm.*` 角色标识。
## [param controller] 该角色的 Agent Runtime 控制器。
## [param area_resolver] 服务端确定性区域解析器。
## [param decision_provider] 本地 Callable 或可替换的 LlmProvider；不包含网络实现。
## [param display_name] 游戏内显示名；为空时使用角色标识。
## [param requested_map_id] 首次进入地图；为空时使用默认地图。
## [param requested_position] 首次出生位置；非有限值时使用默认出生点。
func spawn_llm_player(
	actor_id: String,
	controller: LlmPlayerController,
	area_resolver: Callable,
	decision_provider: Variant,
	display_name := "",
	requested_map_id := "",
	requested_position := Vector2.INF,
	decision_delay_seconds := 0.0,
	decision_timeout_seconds := 180.0,
) -> DomainResult:
	if sessions == null or map_registry == null:
		return DomainResultScript.failure(&"llm.server_unavailable", "LLM player runtime is not initialized")
	if not _valid_llm_player_id(actor_id):
		return DomainResultScript.failure(&"llm.invalid_identity", "LLM player IDs must use the llm.* namespace")
	if sessions.session_for_entity(actor_id) != null:
		return DomainResultScript.failure(&"llm.actor_already_exists", "LLM player already has an active session")
	var effective_name := String(display_name).strip_edges()
	if effective_name.is_empty(): effective_name = actor_id
	if effective_name.length() > 64 or "\n" in effective_name or "\r" in effective_name:
		return DomainResultScript.failure(&"llm.invalid_display_name", "LLM display name is invalid")
	var map_id := String(requested_map_id).strip_edges()
	if map_id.is_empty(): map_id = _default_map_id
	var ensured := ensure_runtime_map(map_id)
	if not ensured.ok:
		return DomainResultScript.failure(
			StringName(ensured.get("code", "llm.map_unavailable")),
			String(ensured.get("message", "requested map is unavailable")),
		)
	var instance: AuthoritativeMapInstance = ensured.value
	var position := requested_position if requested_position.is_finite() else config.default_spawn
	var spawned := instance.spawn_entity(actor_id, position, config.default_movement_speed)
	if not spawned.ok:
		return DomainResultScript.failure(
			StringName(spawned.get("code", "llm.spawn_failed")),
			String(spawned.get("message", "LLM player could not be spawned")),
		)
	var persistent := _register_persistent_player(spawned.value, instance, effective_name)
	if not persistent.is_ok:
		instance.remove_entity(actor_id)
		return persistent
	var session_result := sessions.create_llm(actor_id, Time.get_ticks_msec())
	if not session_result.ok:
		instance.remove_entity(actor_id)
		if autosave_service != null: autosave_service.unregister_player(actor_id)
		return DomainResultScript.failure(
			StringName(session_result.get("code", "llm.session_failed")),
			String(session_result.get("message", "LLM session could not be created")),
		)
	var session: ServerSession = session_result.value
	session.map_instance_id = instance.instance_id
	if persistent.value is Player:
		_restore_persistent_player_state(session, persistent.value)
	var registered := register_llm_player(
		actor_id,
		controller,
		area_resolver,
		decision_provider,
		decision_delay_seconds,
		decision_timeout_seconds,
	)
	if not registered.is_ok:
		sessions.close_entity(actor_id)
		_remove_entity_from_registered_map(actor_id)
		if autosave_service != null: autosave_service.unregister_player(actor_id)
		return registered
	var actual_session := sessions.session_for_entity(actor_id)
	var actual_instance := instance
	if actual_session != null:
		var restored_instance := map_registry.instance_by_id(actual_session.map_instance_id)
		if restored_instance != null:
			actual_instance = restored_instance
	var started := queue_llm_event(actor_id, {
		"event_id": "%s.spawn.%d" % [actor_id, Time.get_ticks_usec()],
		"event_kind": "player_spawned",
		"payload": {"map_id": String(actual_instance.definition.map_id)},
	})
	if not started.is_ok:
		despawn_llm_player(actor_id)
		return started
	return DomainResultScript.ok({"entity_id": actor_id, "session": session, "display_name": effective_name})


func register_llm_player(
	actor_id: String,
	controller: LlmPlayerController,
	area_resolver: Callable,
	decision_provider: Variant,
	decision_delay_seconds := 0.0,
	decision_timeout_seconds := 180.0,
) -> DomainResult:
	if sessions == null or sessions.session_for_entity(actor_id) == null:
		return DomainResultScript.failure(&"llm.actor_missing", "actor has no authoritative session")
	var session := sessions.session_for_entity(actor_id)
	if session.has_active_peer():
		return DomainResultScript.failure(
			&"llm.actor_controlled", "an active Human session already controls this actor"
		)
	if _actor_controller_registry == null:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	if _llm_wake_scheduler == null:
		return DomainResultScript.failure(&"llm.wake_scheduler_unavailable", "LLM wake scheduler is not configured")
	var configured := _actor_controller_registry.register(
		actor_id,
		controller,
		area_resolver,
		Callable(self, "handle_llm_player_intent"),
		decision_provider,
		decision_delay_seconds,
		decision_timeout_seconds,
	)
	if not configured.is_ok:
		return configured
	var memory_directory := config.player_state_store_path + ".llm/" + actor_id.sha256_text() if config.persistence_enabled else ""
	var memory_configured := controller.configure_memory(memory_directory)
	if not memory_configured.is_ok:
		_actor_controller_registry.unregister(actor_id)
		return memory_configured
	for tool: LlmAgentTool in [
		LlmAgentTool.new("inspect_manufacturing", "查看生产设施。station_id 使用查看区域返回的设施类型，空字符串查询已有订单及其设施。recipe_ids 填 [] 查看全部配方概要（编号、名称、要求等级、能否制造）；填一个或多个概要中的编号，批量查看完整材料、产量、品质和成功率。设施、当前技能和订单统一返回，查询读取最新状态。", {"type": "object", "properties": {
			"station_id": {"type": "string"},
			"recipe_ids": {"type": "array", "items": {"type": "string"}},
		}}),
		LlmAgentTool.new("inspect_mail", "查看自己的邮件和留言，包括发件人、正文、已读状态；section 选 all 查看全部。", {"type": "object", "properties": {
			"section": {"type": "string", "enum": ["all", "mail", "leaveword"]},
		}}),
		LlmAgentTool.new("inspect_private_chat", "查看私聊记录。player_name 和 cursor 均填 null 查看自己的会话列表；指定列表中的玩家名称查看最近50条，使用返回的 next_cursor 查看更早消息。每个会话保留最近500条，对方离线也可查看。", {"type": "object", "properties": {
			"player_name": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"cursor": {"anyOf": [{"type": "string"}, {"type": "null"}]},
		}}),
		LlmAgentTool.new("manage_production", "开始、暂停、继续或取消生产。start 必须指定设施、配方、生产轮数 quantity 和每轮速度 speed；其他操作四个字段填 null。生产按普通玩家规则异步执行，接受订单不等于完成。", {"type": "object", "properties": {
			"operation": {"type": "string", "enum": ["start", "pause", "resume", "cancel"]},
			"station_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"recipe_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"quantity": {"anyOf": [{"type": "integer"}, {"type": "null"}]},
			"speed": {"anyOf": [{"type": "integer"}, {"type": "null"}]},
		}}, "action"),
		LlmAgentTool.new("manage_mail", "发送邮件/留言，或标记已读、删除自己的邮件。send 填收件人名称或标识 recipient、subject、body 和 section(mail/leaveword)，mail_id 填 null；read/delete 仅填 mail_id，其他字段填 null。", {"type": "object", "properties": {
			"operation": {"type": "string", "enum": ["send", "read", "delete"]},
			"recipient": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"subject": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"body": {"anyOf": [{"type": "string"}, {"type": "null"}]},
			"section": {"anyOf": [{"type": "string", "enum": ["mail", "leaveword"]}, {"type": "null"}]},
			"mail_id": {"anyOf": [{"type": "string"}, {"type": "null"}]},
		}}, "action"),
	]:
		var handler := Callable(self, "_inspect_llm_service").bind(tool.tool_id) if tool.tool_kind == "query" else Callable()
		var registered := controller.register_tool(tool, handler)
		if not registered.is_ok:
			controller.close_memory()
			_actor_controller_registry.unregister(actor_id)
			return registered
	var scheduled := _llm_wake_scheduler.register(actor_id, LLM_LOW_FREQUENCY_WAKE_SECONDS)
	if not scheduled.is_ok:
		controller.close_memory()
		_actor_controller_registry.unregister(actor_id)
		return scheduled
	LlmTraceLoggerScript.enable()
	LlmTraceLoggerScript.record(actor_id, &"player_registered", {
		"decision_timeout_seconds": decision_timeout_seconds,
		"decision_delay_seconds": decision_delay_seconds,
	})
	var actor_instance: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id)
	if actor_instance != null and actor_instance.combat_module != null \
			and not _llm_combat_event_cursors.has(actor_instance.instance_id):
		_llm_combat_event_cursors[actor_instance.instance_id] = actor_instance.combat_module.event_sequence
	_llm_damage_episodes.erase(actor_id)
	_llm_death_notified.erase(actor_id)
	if not controller.intent_submitted.is_connected(_on_llm_intent_submitted):
		controller.intent_submitted.connect(_on_llm_intent_submitted)
	if not controller.observation_requested.is_connected(observe_llm_player):
		controller.observation_requested.connect(observe_llm_player)
	if controller.get_parent() == null:
		add_child(controller)
	return DomainResultScript.ok(controller)


func unregister_llm_player(actor_id: String) -> DomainResult:
	if _actor_controller_registry == null:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	if controller == null:
		return DomainResultScript.failure(&"llm.not_registered", "actor has no LLM controller")
	var server_owned := controller.get_parent() == self
	controller.interrupt(&"player_offline")
	_cancel_llm_behavior(actor_id, &"llm_unregistered")
	var memory_closed := controller.close_memory()
	if not memory_closed.is_ok: return memory_closed
	var result := _actor_controller_registry.unregister(actor_id)
	if result.is_ok:
		_llm_hunt_behaviors.erase(actor_id)
		_llm_damage_episodes.erase(actor_id)
		if _llm_wake_scheduler != null: _llm_wake_scheduler.unregister(actor_id)
		if _llm_event_bus != null: _llm_event_bus.clear_actor(actor_id)
		if _actor_controller_registry.actor_ids().is_empty():
			LlmTraceLoggerScript.shutdown()
	if result.is_ok and server_owned and is_instance_valid(controller): controller.queue_free()
	return result


## 保存并下线独立 LLM 玩家；不会删除其持久化角色身份。
func despawn_llm_player(actor_id: String) -> DomainResult:
	var session: ServerSession = sessions.session_for_entity(actor_id) if sessions != null else null
	if session == null or not session.is_llm:
		return DomainResultScript.failure(&"llm.actor_missing", "actor is not an independent LLM player")
	if _persistence_coordinator != null:
		var saved := _persistence_coordinator.save_expired_player(actor_id)
		if not saved.is_ok: return saved
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id) \
		if _actor_controller_registry != null else null
	if controller != null:
		controller.interrupt(&"player_offline")
		var unregistered := unregister_llm_player(actor_id)
		if not unregistered.is_ok: return unregistered
	_pending_vehicle_recoveries.erase(actor_id)
	_pending_player_changes.erase(actor_id)
	_remove_entity_from_registered_map(actor_id)
	if party_service != null: party_service.remove_expired_entity(actor_id)
	if trade_service != null: trade_service.remove_expired_entity(actor_id)
	if friend_service != null: friend_service.remove_expired_entity(actor_id)
	if chat_service != null: chat_service.remove_expired_entity(actor_id)
	if mail_service != null: mail_service.remove_expired_entity(actor_id)
	var closed := sessions.close_entity(actor_id)
	if not closed.ok:
		return DomainResultScript.failure(
			StringName(closed.get("code", "llm.session_close_failed")),
			String(closed.get("message", "LLM session could not be closed")),
		)
	_published_player_revisions.erase(session.sync_id)
	if autosave_service != null: autosave_service.unregister_player(actor_id)
	return DomainResultScript.ok({"entity_id": actor_id, "saved": true})


func observe_llm_player(actor_id: String) -> DomainResult:
	if _actor_controller_registry == null:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	if controller == null:
		return DomainResultScript.failure(&"llm.not_registered", "actor has no LLM controller")
	var session := sessions.session_for_entity(actor_id)
	if session == null:
		return DomainResultScript.failure(&"llm.actor_missing", "actor has no authoritative session")
	if session.has_active_peer():
		return DomainResultScript.failure(&"llm.actor_controlled", "Human session currently controls this actor")
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		return DomainResultScript.failure(&"llm.map_unavailable", "actor map is not registered")
	var entity: AuthoritativeEntity = current_instance.entities.get(actor_id)
	if entity == null:
		return DomainResultScript.failure(&"llm.entity_missing", "actor entity is not present in its map")
	var shared_snapshot := current_instance.world_snapshot(
		server_tick, float(server_tick) / float(config.simulation_hz)
	)
	var combat_world: Dictionary = shared_snapshot.get("combat_world", {})
	var nearby_entities: Array = shared_snapshot.get("entities", []).duplicate(true)
	for raw_monster: Variant in combat_world.get("monsters", []):
		if not raw_monster is Dictionary:
			continue
		var monster: Dictionary = raw_monster.duplicate(true)
		monster["entity_kind"] = "monster"
		monster["action_id"] = String(monster.get("action", "idle"))
		nearby_entities.append(monster)
	for raw_source: Variant in combat_world.get("mine_sources", []):
		if not raw_source is Dictionary:
			continue
		var source: Dictionary = raw_source.duplicate(true)
		source["entity_id"] = String(source.get("source_id", ""))
		source["entity_kind"] = "mine_source"
		source["action_id"] = "available" if int(source.get("remaining", 0)) > 0 else "depleted"
		source["alive"] = int(source.get("remaining", 0)) > 0
		nearby_entities.append(source)
	var recent_events: Array = []
	for raw_event: Variant in combat_world.get("recent_events", []):
		if not raw_event is Dictionary:
			continue
		if String(raw_event.get("event_type", "")).begins_with("monster_attack_"):
			continue
		var event: Dictionary = raw_event.duplicate(true)
		event["kind"] = String(event.get("event_type", event.get("kind", "")))
		event["message"] = String(event.get("message", event.get("kind", "")))
		recent_events.append(event)
	var ground_items: Array[Dictionary] = []
	for raw_item: Variant in combat_world.get("ground_loot", []):
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item.duplicate(true)
		var definition_id := String(item.get("item_definition_id", ""))
		if player_panel_service != null and not definition_id.is_empty():
			item["display_name"] = player_panel_service.catalog.display_name(definition_id)
		ground_items.append(item)
	var self_state: Dictionary = entity.snapshot(server_tick)
	var local_snapshot := current_instance.local_snapshot_for_actor(server_tick, actor_id)
	var local_vehicle: Dictionary = local_snapshot.get("local_vehicle", {})
	for field: String in [
		"health", "max_health", "reserve_energy", "reserve_energy_capacity",
		"working_energy", "working_energy_capacity", "self_repair_active",
	]:
		if local_vehicle.has(field):
			self_state[field] = local_vehicle[field]
	var player := autosave_service.player_for(actor_id) if autosave_service != null else null
	if player != null:
		self_state["display_name"] = player.display_name
		self_state["comprehensive_level"] = player.level
		self_state["residence"] = player.residence
		self_state["inventory_used"] = player.inventory.items().size()
		self_state["inventory_capacity"] = player.inventory.capacity
		self_state["currency"] = player.inventory.currency
		var tradable_items: Array[Dictionary] = []
		for item: GameItem in player.inventory.items():
			if item.locked or item.bound:
				continue
			tradable_items.append({
				"instance_id": item.instance_id,
				"definition_id": item.definition_id,
				"display_name": item.display_name,
				"quantity": item.quantity,
			})
		self_state["tradable_items"] = tradable_items
	var available_objectives: Array = []
	if player != null and commerce_service != null:
		var quest_service = commerce_service.quests
		var current_map_id := String(current_instance.definition.map_id)
		for provider_id: String in quest_service.catalog.providers:
			var provider: Dictionary = quest_service.catalog.providers[provider_id]
			if current_map_id not in provider.get("map_ids", []):
				continue
			for task: Dictionary in quest_service.snapshots(player, provider_id):
				var objective := task.duplicate(true)
				objective["objective_id"] = String(task.get("task_id", ""))
				if not objective.has("kind"):
					objective["kind"] = "collection"
				objective["status"] = "exhausted" if bool(task.get("exhausted", false)) \
						else "ready_to_turn_in" if bool(task.get("ready_to_turn_in", false)) \
						else "active" if bool(task.get("accepted", false)) else "available"
				available_objectives.append(objective)
	var available_transitions: Array[Dictionary] = []
	for transition: MapTransition in current_instance.definition.enabled_transitions():
		var target_map_id := _target_map_id_for_transition(transition, current_instance.definition.world_id)
		if target_map_id.is_empty() or not _runtime_definition_paths_by_map_id.has(target_map_id):
			continue
		var approach_point := transition.approach_point
		if approach_point.is_zero_approx():
			approach_point = transition.source_anchor
		available_transitions.append({
			"transition_id": String(transition.transition_id),
			"label": transition.label,
			"destination_key": transition.destination_key(),
			"destination_entry_number": transition.destination_entry_number,
			"approach_point": [approach_point.x, approach_point.y],
		})
	var map_id := String(current_instance.definition.map_id)
	var npc_definitions := _llm_npc_definitions_for_map(map_id)
	var npcs: Array[Dictionary] = []
	var npc_shops: Array[Dictionary] = []
	for npc_value: Variant in npc_definitions:
		if not npc_value is Dictionary:
			continue
		var npc: Dictionary = npc_value
		var spawn: Variant = npc.get("spawn", [])
		if not spawn is Array or (spawn as Array).size() != 2:
			continue
		npcs.append({
			"npc_id": String(npc.get("id", "")),
			"display_name": String(npc.get("name", npc.get("id", "NPC"))),
			"npc_kind": String(npc.get("kind", "ambient")),
			"position": [float(spawn[0]), float(spawn[1])],
		})
		if String(npc.get("kind", "")) == "shop" and player != null and commerce_service != null:
			var merchant_id := String(npc.get("id", ""))
			var shop_result: DomainResult = commerce_service.llm_shop_snapshot(
				player, merchant_id, String(npc.get("name", merchant_id))
			)
			if shop_result.is_ok:
				npc_shops.append(shop_result.value)
	var facilities: Array[Dictionary] = manufacturing_service.facilities_for_map(map_id) \
		if manufacturing_service != null else []
	if garden_service != null and garden_service.catalog != null and garden_service.catalog.supports_map(map_id):
		var now := int(Time.get_unix_time_from_system())
		var remaining_by_plant: Dictionary = {}
		if player != null:
			var garden_state := garden_service.query(player, map_id, now)
			if garden_state.is_ok:
				for row: Dictionary in garden_state.value.get("plants", []):
					remaining_by_plant[String(row.get("plant_id", ""))] = int(row.get("remaining_seconds", 0))
		for plant_id: String in garden_service.catalog.plants:
			var plant: Dictionary = garden_service.catalog.plants[plant_id]
			var remaining := maxi(0, int(remaining_by_plant.get(plant_id, 0)))
			var item_name := String(plant.item_definition_id)
			if player_panel_service != null:
				item_name = player_panel_service.catalog.display_name(item_name)
			facilities.append({
				"entity_id": plant_id,
				"facility_kind": "garden_plant",
				"display_name": "果实：%s" % item_name,
				"position": [plant.position.x, plant.position.y],
				"interaction_radius": garden_service.catalog.interaction_radius,
				"item_definition_id": plant.item_definition_id,
				"available": remaining <= 0,
				"remaining_seconds": remaining,
			})
	var panel_bundle := player_panel_service.build_llm_panels(player) \
		if player != null and player_panel_service != null else {}
	var raw_snapshot := {
		"actor_id": actor_id,
		"observation_revision": server_tick,
		"map_instance_id": current_instance.instance_id,
		"map_id": String(current_instance.definition.map_id),
		"self": self_state,
		"panel_bundle": panel_bundle,
		"nearby_entities": nearby_entities,
		"ground_items": ground_items,
		"npcs": npcs,
		"npc_shops": npc_shops,
		"facilities": facilities,
		"available_objectives": available_objectives,
		"available_transitions": available_transitions,
		"party_state": party_service.snapshot_for(actor_id) if party_service != null else {},
		"friend_state": friend_service.snapshot_for(actor_id) if friend_service != null else {},
		"trade_state": trade_service.execute(actor_id, {"type": "query_trade"}).value if trade_service != null else {},
		"recent_events": recent_events,
		"captured_at_msec": Time.get_ticks_msec(),
	}
	var observation_result := _actor_controller_registry.observation_policy().build(raw_snapshot)
	if not observation_result.is_ok:
		return observation_result
	var submitted := controller.submit_observation(observation_result.value)
	return submitted if not submitted.is_ok else observation_result


func request_llm_decision(actor_id: String) -> DomainResult:
	if _actor_controller_registry == null:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	if controller == null:
		return DomainResultScript.failure(&"llm.not_registered", "actor has no LLM controller")
	var session := sessions.session_for_entity(actor_id)
	if session == null or session.has_active_peer():
		return DomainResultScript.failure(&"llm.actor_controlled", "Human session currently controls this actor")
	return controller.request_decision()


func _on_llm_intent_submitted(intent: PlayerIntent, result: DomainResult) -> void:
	if intent == null or result == null or result.is_ok:
		return
	if _actor_controller_registry == null or not _actor_controller_registry.has_controller(intent.actor_id):
		return
	var event_kind: StringName = &"combat_failed" if intent.intent_kind == &"hunt" else &"action_failed"
	var queued := queue_llm_event(intent.actor_id, {
		"event_id": "%s.%s.%d" % [intent.actor_id, String(event_kind), Time.get_ticks_usec()],
		"event_kind": event_kind,
		"payload": {
			"intent_kind": String(intent.intent_kind),
			"sequence": intent.sequence,
			"error_code": String(result.error_code),
			"error_message": result.error_message,
			"payload": intent.payload.duplicate(true),
		},
	})
	if not queued.is_ok:
		push_error("LLM action failure event failed: " + queued.error_message)


## 向 LLM 玩家投递语义事件；观察刷新后由控制器决定是否开始下一轮。
## [param actor_id] 已注册的 LLM 玩家身份。
## [param raw_event] `LlmAgentEvent` 或其字典表示，不携带权威对象引用。
func queue_llm_event(actor_id: String, raw_event: Variant) -> DomainResult:
	if _llm_event_bus == null:
		return _deliver_llm_event(actor_id, raw_event)
	return _llm_event_bus.publish(actor_id, raw_event)


func _deliver_llm_event(actor_id: String, raw_event: Variant) -> DomainResult:
	if _actor_controller_registry == null:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	if controller == null:
		return DomainResultScript.failure(&"llm.not_registered", "actor has no LLM controller")
	var session := sessions.session_for_entity(actor_id)
	if session == null or session.has_active_peer():
		return DomainResultScript.failure(&"llm.actor_controlled", "Human session currently controls this actor")
	var queued := controller.enqueue_event(raw_event, false)
	if not queued.is_ok:
		return queued
	if not queued.value.interrupts_current_turn and queued.value.event_kind in [&"destination_reached", &"map_transition_result", &"combat_result", &"self_repair_stopped", &"gather_result", &"action_result"]:
		_wait_llm_after_action(actor_id)
	if queued.value.interrupts_current_turn or queued.value.event_kind == &"death" or (queued.value.event_kind == &"under_attack" and not controller.is_reviewing_damage()):
		_cancel_llm_behavior(actor_id, queued.value.event_kind)
	var observed := observe_llm_player(actor_id)
	return queued if observed.is_ok else observed


func _wait_llm_after_action(actor_id: String) -> void:
	var session := sessions.session_for_entity(actor_id)
	var instance := map_registry.instance_by_id(session.map_instance_id) if session != null else null
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	if instance != null and controller != null:
		_cancel_llm_behavior(actor_id, &"wait")
		controller.wait(Time.get_ticks_msec() + (1500 if instance.is_vehicle_combat_active() else 3000))


func _cancel_llm_behavior(actor_id: String, reason: StringName) -> void:
	_llm_hunt_behaviors.erase(actor_id)
	_llm_pending_intents.erase(actor_id)
	var session := sessions.session_for_entity(actor_id)
	if session == null:
		return
	var instance: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id)
	if instance == null:
		return
	var entity: AuthoritativeEntity = instance.entities.get(actor_id)
	if entity != null:
		entity.stop_moving()
	if instance.mining_module != null:
		instance.mining_module.interrupt(actor_id, reason)
	if instance.combat_module != null and reason != &"self_repair":
		instance.combat_module.interrupt_self_repair(actor_id, &"movement")


## 中断当前 LLM 决策；确定性行为的取消仍由对应玩家能力控制器处理。
func interrupt_llm_player(actor_id: String, reason: StringName = &"external_interrupt") -> DomainResult:
	if _actor_controller_registry == null:
		return DomainResultScript.failure(&"llm.registry_unavailable", "actor controller registry is not configured")
	var controller: LlmPlayerController = _actor_controller_registry.controller_for(actor_id)
	if controller == null:
		return DomainResultScript.failure(&"llm.not_registered", "actor has no LLM controller")
	_cancel_llm_behavior(actor_id, reason)
	return controller.interrupt(reason)


func handle_llm_player_intent(intent: PlayerIntent) -> DomainResult:
	if _actor_controller_registry == null or intent == null \
			or not _actor_controller_registry.has_controller(intent.actor_id):
		return DomainResultScript.failure(&"llm.intent_forbidden", "actor is not registered as an LLM player")
	var session := sessions.session_for_entity(intent.actor_id)
	if session == null or session.has_active_peer():
		return DomainResultScript.failure(&"llm.actor_controlled", "Human session currently controls this actor")
	_cancel_llm_behavior(intent.actor_id, intent.intent_kind)
	var executed := _execute_llm_player_intent(intent)
	if executed.is_ok and intent.intent_kind not in [&"wait", &"move", &"hunt", &"gather", &"harvest", &"self_repair", &"recovery"] and not (executed.value is Dictionary and executed.value.get("action") == "approaching"):
		_wait_llm_after_action(intent.actor_id)
	var refreshed := observe_llm_player(intent.actor_id)
	if not refreshed.is_ok: push_error("LLM action observation refresh failed: " + refreshed.error_message)
	return executed


func _execute_llm_player_intent(intent: PlayerIntent) -> DomainResult:
	if intent.intent_kind == &"wait":
		return DomainResultScript.ok({"action": "safe_idle"})
	if intent.intent_kind == &"recovery":
		var session := sessions.session_for_entity(intent.actor_id)
		var recovery := VehicleRecoveryIntentContract.new(session.map_instance_id, VehicleRecoveryIntentContract.RETURN_TO_BASE, maxi(intent.sequence, session.last_recovery_sequence + 1))
		var recovered := _handle_vehicle_recovery(session, recovery.to_dictionary())
		return DomainResultScript.ok(recovered.value) if recovered.ok else DomainResultScript.failure(recovered.code, recovered.message)
	if intent.intent_kind == &"loot":
		var pickup_result := _handle_actor_loot_pickup(intent.actor_id, intent.payload)
		if not pickup_result.ok and pickup_result.code == &"loot.out_of_range":
			var instance := map_registry.instance_by_id(sessions.session_for_entity(intent.actor_id).map_instance_id)
			var position: Array = instance.combat_module.ground_loot[String(intent.payload.loot_id)].position
			return _start_llm_approach(intent, Vector2(position[0], position[1]), 0.0, AuthoritativeCombatModule.LOOT_PICKUP_RADIUS)
		return DomainResultScript.ok(pickup_result.get("value", {})) if pickup_result.ok else \
			DomainResultScript.failure(
				StringName(pickup_result.get("code", "loot.pickup_failed")),
				String(pickup_result.get("message", "loot pickup failed")),
			)
	if intent.intent_kind == &"panel_command":
		return _handle_llm_item_command(intent.actor_id, intent.payload)
	if intent.intent_kind == &"hunt":
		return _handle_llm_hunt(intent)
	if intent.intent_kind == &"gather":
		return _handle_llm_gather(intent)
	if intent.intent_kind == &"harvest":
		return _handle_llm_harvest(intent)
	if intent.intent_kind == &"self_repair":
		return _handle_llm_self_repair(intent)
	if intent.intent_kind == &"chat":
		return _handle_llm_chat(intent)
	if intent.intent_kind in [&"party", &"friend", &"trade", &"mail"]:
		return _handle_llm_social(intent)
	if intent.intent_kind == &"production":
		return _handle_llm_production(intent)
	if intent.intent_kind == &"npc_trade":
		return _handle_llm_npc_trade(intent)
	if intent.intent_kind == &"objective":
		return _handle_llm_objective(intent)
	if intent.intent_kind == &"travel":
		return _handle_llm_travel(intent)
	if intent.intent_kind != &"move":
		return DomainResultScript.failure(&"llm.intent_unsupported", "intent kind is not supported")
	var result := _handle_entity_move(intent.actor_id, intent.payload)
	if result.ok:
		var session := sessions.session_for_entity(intent.actor_id)
		_llm_pending_intents[intent.actor_id] = {"intent": intent, "map_instance_id": session.map_instance_id, "target_position": map_registry.instance_by_id(session.map_instance_id).entities[intent.actor_id].target_position}
	return DomainResultScript.ok(result.value) if result.ok else DomainResultScript.failure(
		result.code, String(result.get("message", "LLM intent was rejected"))
	)


func _start_llm_approach(intent: PlayerIntent, position: Vector2, minimum_distance: float, maximum_distance: float) -> DomainResult:
	var session := sessions.session_for_entity(intent.actor_id)
	var instance := map_registry.instance_by_id(session.map_instance_id)
	var entity: AuthoritativeEntity = instance.entities.get(intent.actor_id)
	var direction := position.direction_to(entity.position)
	if direction.is_zero_approx(): direction = Vector2.RIGHT
	var target := position + direction * ((minimum_distance + maximum_distance) * 0.5)
	var move := MoveIntentContractScript.new(instance.instance_id, target, intent.sequence)
	var moved := _handle_entity_move(intent.actor_id, move.to_dictionary())
	if not moved.ok: return DomainResultScript.failure(moved.code, moved.message)
	var distance := entity.target_position.distance_to(position)
	if distance < minimum_distance or distance > maximum_distance:
		entity.stop_moving()
		return DomainResultScript.failure(&"llm.approach_unreachable", "没有可到达且满足交互距离的位置")
	_llm_pending_intents[intent.actor_id] = {"intent": intent, "map_instance_id": instance.instance_id, "target_position": entity.target_position}
	return DomainResultScript.ok({"action": "approaching", "next_action": String(intent.intent_kind)})


func _handle_llm_item_command(actor_id: String, command: Dictionary) -> DomainResult:
	if autosave_service == null or _player_panel_coordinator == null:
		return DomainResultScript.failure(&"panels.persistence_required", "player panels require authoritative persistence")
	var current: Player = autosave_service.player_for(actor_id)
	if current == null:
		return DomainResultScript.failure(&"panels.state_missing", "authoritative player state is not registered")
	var command_type := String(command.get("type", ""))
	if command_type not in ["use_inventory_item", "split_inventory_item", "merge_inventory_item", "equip_item"]:
		return DomainResultScript.failure(&"panels.command_unsupported", "LLM item command is unsupported")
	var trusted := command.duplicate(true)
	if command_type == "merge_inventory_item" and String(trusted.get("target_instance_id", "")).is_empty():
		return DomainResultScript.failure(&"inventory.invalid_merge", "merge requires a target instance")
	trusted["inventory_revision"] = current.inventory.revision
	if command_type == "equip_item":
		var item := current.inventory.find(String(trusted.get("instance_id", "")))
		if item is Clothing:
			trusted["type"] = "equip_character_item"
			trusted["character_slot"] = (item as Clothing).character_slot
			trusted["state_revision"] = current.revision
		elif item is VehicleEquipment:
			trusted["type"] = "equip_vehicle_item"
			trusted["location"] = (item as VehicleEquipment).equipment_location
			trusted["loadout_revision"] = current.vehicle.loadout.revision
		else:
			return DomainResultScript.failure(&"equipment.location_rejected", "item cannot be equipped")
	var executed := _player_panel_coordinator.execute_session(sessions.session_for_entity(actor_id), trusted)
	if not executed.ok:
		return DomainResultScript.failure(executed.code, String(executed.get("message", "item action failed")))
	_flush_player_changes()
	return DomainResultScript.ok({"action": command_type, "changed": true, "result": executed.value.get("operation")})


func _handle_llm_travel(intent: PlayerIntent) -> DomainResult:
	if intent.payload.size() != 5:
		return DomainResultScript.failure(&"llm.travel_invalid", "travel intent has an invalid payload")
	var source_instance_id := String(intent.payload.get("map_instance_id", ""))
	var transition_id := String(intent.payload.get("transition_id", ""))
	var destination_instance_id := String(intent.payload.get("destination_map_instance_id", ""))
	var entry_number := int(intent.payload.get("destination_entry_number", -1))
	if source_instance_id.is_empty() or transition_id.is_empty() \
			or destination_instance_id.is_empty() or entry_number < 0:
		return DomainResultScript.failure(&"llm.travel_invalid", "travel source, exit and destination are required")
	var movement_result: DomainResult = MoveIntentContractScript.from_dictionary({
		"map_instance_id": source_instance_id,
		"requested_world_point": intent.payload.get("requested_world_point"),
		"input_sequence": intent.sequence,
	})
	if not movement_result.is_ok:
		return DomainResultScript.failure(movement_result.error_code, movement_result.error_message)
	var session: ServerSession = sessions.session_for_entity(intent.actor_id)
	if session == null:
		return DomainResultScript.failure(&"llm.actor_missing", "actor has no authoritative session")
	if source_instance_id != session.map_instance_id:
		return DomainResultScript.failure(&"llm.travel_stale", "travel source is not the actor's current map")
	var source_instance: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id)
	if source_instance == null:
		return DomainResultScript.failure(&"llm.map_unavailable", "actor map is not registered")
	var transition: MapTransition = source_instance.definition.transition_by_id(StringName(transition_id))
	if transition == null or not transition.enabled:
		return DomainResultScript.failure(&"llm.transition_unavailable", "transition is not enabled on the current map")
	if entry_number != transition.destination_entry_number:
		return DomainResultScript.failure(&"llm.transition_stale", "destination entry no longer matches the current map")
	var destination_instance := map_registry.resolve_transition_target(transition, source_instance.definition.world_id)
	var target_map_id := String(destination_instance.definition.map_id) if destination_instance != null else _target_map_id_for_transition(transition, source_instance.definition.world_id)
	if (destination_instance != null and destination_instance.instance_id != destination_instance_id) or (destination_instance == null and ("%s.instance.1" % target_map_id != destination_instance_id or not _runtime_definition_paths_by_map_id.has(target_map_id))):
		return DomainResultScript.failure(&"llm.transition_stale", "destination map no longer matches the current transition")
	var entity: AuthoritativeEntity = source_instance.entities.get(intent.actor_id)
	if entity == null:
		return DomainResultScript.failure(&"llm.entity_missing", "actor entity is not present in its map")
	var exit_point := transition.approach_point
	if exit_point.is_zero_approx():
		exit_point = transition.source_anchor
	if not exit_point.is_finite():
		return DomainResultScript.failure(&"llm.transition_unavailable", "transition has no finite approach point")
	if map_registry.instance_by_id(destination_instance_id) == null and not _pending_runtime_maps.has(target_map_id):
		for abandoned_id: String in _pending_runtime_maps.keys():
			if not _pending_runtime_maps[abandoned_id].thread.is_alive() and not _llm_pending_intents.values().any(func(pending: Dictionary) -> bool: return pending.intent.payload.get("destination_map_instance_id") == "%s.instance.1" % abandoned_id):
				_pending_runtime_maps[abandoned_id].thread.wait_to_finish()
				_pending_runtime_maps.erase(abandoned_id)
		if _pending_runtime_maps.size() >= 2:
			return DomainResultScript.failure(&"llm.map_loading_busy", "地图后台准备繁忙，请稍后重试")
		var prepared := MapInstanceScript.new()
		prepared.dynamic_blocking_enabled = config.dynamic_blocking_enabled
		prepared.dynamic_blocking_radius = config.dynamic_blocking_radius
		var loading := Thread.new()
		if loading.start(Callable(prepared, "load_runtime").bind(_runtime_definition_paths_by_map_id[target_map_id], _combat_catalog, _mining_catalog, config.simulation_hz, map_registry.dormant_instance(target_map_id) != null), Thread.PRIORITY_LOW) != OK:
			return DomainResultScript.failure(&"llm.map_loading_failed", "无法启动地图后台准备")
		_pending_runtime_maps[target_map_id] = {"thread": loading, "instance": prepared}
	if entity.position.distance_to(exit_point) > config.map_transition_radius:
		return _start_llm_approach(intent, exit_point, 0.0, config.map_transition_radius)
	if _pending_runtime_maps.has(target_map_id) and _pending_runtime_maps[target_map_id].thread.is_alive():
		_llm_pending_intents[intent.actor_id] = {"intent": intent, "map_instance_id": source_instance_id, "target_position": entity.position}
		return DomainResultScript.ok({"action": "approaching", "next_action": "travel"})
	destination_instance = _resolve_or_load_transition_target(transition, source_instance.definition.world_id)
	if destination_instance == null:
		return DomainResultScript.failure(&"llm.map_loading_failed", "目标地图准备失败")
	var transition_intent := MapTransitionIntentContractScript.new(
		source_instance.instance_id,
		transition_id,
		entry_number,
		maxi(intent.sequence, session.last_transition_sequence + 1),
	)
	var result := _map_transition_coordinator.execute_for_session(
		session,
		transition_intent.to_dictionary(),
		server_tick,
		float(server_tick) / float(config.simulation_hz),
		config.map_transition_radius,
		config.default_movement_speed,
	)
	if not result.get("ok", false):
		return DomainResultScript.failure(
			StringName(result.get("code", "llm.transition_rejected")),
			String(result.get("message", "map transition was rejected")),
		)
	if trade_service != null:
		trade_service.cancel_for_entity(intent.actor_id)
	if party_service != null:
		party_service.cancel_invites_for_entity(intent.actor_id)
	var joined: Dictionary = result.get("value", {}).get("map_joined", {})
	var queued := queue_llm_event(intent.actor_id, {
		"event_id": "%s.map_transition.%d.%d" % [intent.actor_id, server_tick, intent.sequence],
		"event_kind": "map_transition_result",
		"payload": {
			"map_id": String(joined.get("map_id", destination_instance.definition.map_id)),
			"map_instance_id": String(joined.get("map_instance_id", destination_instance.instance_id)),
		},
	})
	if not queued.is_ok:
		push_error("LLM map transition event failed: " + queued.error_message)
	return DomainResultScript.ok({"action": "arrived", "map_id": String(destination_instance.definition.map_id), "display_name": destination_instance.definition.display_name})


func _handle_llm_hunt(intent: PlayerIntent) -> DomainResult:
	if intent.payload.size() != 2 or intent.payload.get("combat_mode") not in HighLevelPlayerAction.COMBAT_MODES:
		return DomainResultScript.failure(&"llm.hunt_invalid", "hunt intent requires species_id and a valid combat_mode")
	var species_id := String(intent.payload.get("species_id", ""))
	if species_id.is_empty():
		return DomainResultScript.failure(&"llm.hunt_invalid", "hunt species is required")
	var session := sessions.session_for_entity(intent.actor_id)
	if session == null:
		return DomainResultScript.failure(&"llm.actor_missing", "actor has no authoritative session")
	var instance := map_registry.instance_by_id(session.map_instance_id)
	if instance == null or instance.combat_module == null:
		return DomainResultScript.failure(&"combat.not_available", "this map has no configured combat encounter")
	var actor_entity: AuthoritativeEntity = instance.entities.get(intent.actor_id)
	if actor_entity == null or not instance.combat_module.actors.has(intent.actor_id):
		return DomainResultScript.failure(&"llm.actor_missing", "combat actor is not registered on this map")
	var monster := _nearest_llm_hunt_monster(instance, actor_entity.position, species_id)
	if monster == null:
		return DomainResultScript.failure(&"llm.target_unavailable", "no living monster of this species is available")
	var weapons: Dictionary = instance.combat_module.actors[intent.actor_id].get("weapons", {})
	if weapons.is_empty():
		return DomainResultScript.failure(&"combat.weapon_not_equipped", "no weapon is equipped")
	_llm_hunt_behaviors[intent.actor_id] = {
		"map_instance_id": instance.instance_id,
		"species_id": species_id,
		"target_id": monster.monster_id,
		"combat_mode": intent.payload.combat_mode,
	}
	LlmTraceLoggerScript.record(intent.actor_id, &"hunt_behavior_started", {
		"map_instance_id": instance.instance_id,
		"species_id": species_id,
		"target_id": monster.monster_id,
		"target_position": monster.position,
		"distance": actor_entity.position.distance_to(monster.position),
		"combat_mode": intent.payload.combat_mode,
	})
	var started := _advance_llm_hunt_behavior(instance, intent.actor_id, true)
	return DomainResultScript.ok({"behavior": "hunting", "species_id": species_id, "combat_mode": intent.payload.combat_mode}) if started.is_ok else started


func _advance_llm_hunt_behaviors(instance: AuthoritativeMapInstance, actor_ids: Array) -> void:
	if instance.combat_module == null:
		return
	for actor_id: String in actor_ids:
		if _llm_hunt_behaviors.has(actor_id):
			_advance_llm_hunt_behavior(instance, actor_id)


func _advance_llm_hunt_behavior(instance: AuthoritativeMapInstance, actor_id: String, starting := false) -> DomainResult:
	if not _llm_hunt_behaviors.has(actor_id) or instance.combat_module == null:
		return DomainResultScript.ok()
	var session := sessions.session_for_entity(actor_id)
	var entity: AuthoritativeEntity = instance.entities.get(actor_id)
	var behavior: Dictionary = _llm_hunt_behaviors[actor_id]
	if session == null or session.map_instance_id != instance.instance_id or entity == null or String(behavior.get("map_instance_id", instance.instance_id)) != instance.instance_id:
		_llm_hunt_behaviors.erase(actor_id)
		_queue_llm_runtime_event(actor_id, &"action_invalidated", {"reason": "map_changed"})
		return DomainResultScript.failure(&"llm.map_changed", "狩猎期间所在地图已变化")
	var species_id := String(behavior.get("species_id", ""))
	var combat_mode := String(behavior.combat_mode)
	var monster: MonsterLifecycle = instance.combat_module.monster_for(
		String(behavior.get("target_id", ""))
	)
	var was_own_kill := monster != null and not monster.is_alive() and monster.last_killer_id == actor_id
	if monster == null or monster.map_instance_id != instance.instance_id \
			or monster.species_id != species_id or not monster.is_alive():
		entity.stop_moving()
		_llm_hunt_behaviors.erase(actor_id)
		LlmTraceLoggerScript.record(actor_id, &"hunt_behavior_finished", {
			"reason": "killed" if was_own_kill else "target_unavailable",
			"species_id": species_id,
			"target_id": behavior.get("target_id", ""),
			"own_kill": was_own_kill,
		})
		if not was_own_kill:
			_queue_llm_runtime_event(actor_id, &"action_invalidated", {"reason": "hunt_target_unavailable", "species_id": species_id})
		return DomainResultScript.ok()
	var combat_actor: Dictionary = instance.combat_module.actors.get(actor_id, {})
	var weapons: Dictionary = combat_actor.get("weapons", {})
	var weapon_ids := weapons.keys()
	weapon_ids.sort_custom(func(a: String, b: String) -> bool:
		var weapon_a: Dictionary = weapons[a]
		var weapon_b: Dictionary = weapons[b]
		var range_a := float(weapon_a.get("range", 0.0))
		var range_b := float(weapon_b.get("range", 0.0))
		return range_a > range_b if not is_equal_approx(range_a, range_b) else a < b
	)
	var distance := entity.position.distance_to(monster.position)
	var selected_for_approach := ""
	var has_in_range_weapon := false
	var has_usable_weapon := false
	var vehicle: VehicleCombatState = combat_actor.get("vehicle_state")
	var equipment: EquipmentConditionLoadout = combat_actor.get("equipment_condition")
	for ability_id: String in weapon_ids:
		var weapon: Dictionary = weapons[ability_id]
		var instance_id := String(weapon.get("instance_id", ""))
		var ammo := equipment.ammunition_for(instance_id) if equipment != null else {}
		if not ammo.is_empty() and int(ammo.get("remaining", 0)) <= 0:
			continue
		if equipment != null and not equipment.validate_shot(instance_id).is_ok:
			continue
		if weapon.get("activation_power") != null and vehicle != null \
				and not vehicle.supports_activation_power(float(weapon["activation_power"])):
			continue
		has_usable_weapon = true
		if vehicle != null and vehicle.working_energy < float(weapon.get("working_energy_per_shot", 0.0)):
			continue
		if selected_for_approach.is_empty():
			selected_for_approach = ability_id
		var attack_range := float(weapon.get("range", 0.0))
		var minimum_range := float(weapon.get("minimum_range", 0.0))
		if distance < minimum_range or distance > attack_range:
			continue
		if not has_in_range_weapon: selected_for_approach = ability_id
		has_in_range_weapon = true
		if combat_mode == "stationary" and entity.action == &"walking": entity.stop_moving()
		if instance.combat_module.current_tick < int(
			combat_actor.get("cooldown_ready_ticks", {}).get(ability_id, 0)
		):
			continue
		var command_sequence := int(combat_actor.get("last_command_sequence", -1)) + 1
		var attack := UseAbilityIntentContractScript.new(
			instance.instance_id, ability_id, monster.position + monster.attack_mode.projectile_hitbox_offset, command_sequence
		)
		var attack_result: Dictionary = instance.handle_use_ability(actor_id, attack.to_dictionary())
		LlmTraceLoggerScript.record(actor_id, &"hunt_attack", {
			"map_instance_id": instance.instance_id,
			"species_id": species_id,
			"target_id": monster.monster_id,
			"ability_id": ability_id,
			"distance": distance,
			"ok": bool(attack_result.get("ok", false)),
			"code": String(attack_result.get("code", "")),
			"message": String(attack_result.get("message", "")),
		})
		if not attack_result.ok:
			return _fail_llm_hunt(entity, starting, attack_result.code, attack_result.message)
		break
	if selected_for_approach.is_empty() and not has_usable_weapon:
		return _fail_llm_hunt(entity, starting, &"combat.no_usable_weapon", "no usable weapon or ammunition is available")
	if selected_for_approach.is_empty() or (has_in_range_weapon and combat_mode == "stationary"):
		return DomainResultScript.ok()
	var approach_weapon: Dictionary = weapons[selected_for_approach]
	var attack_range := float(approach_weapon.get("range", 0.0))
	var minimum_range := float(approach_weapon.get("minimum_range", 0.0))
	var reached_waypoint := entity.action != &"walking" and entity.position.is_equal_approx(entity.target_position)
	if entity.action == &"walking":
		if not behavior.has("center") or (_llm_hunt_path_in_range(entity, monster.position, minimum_range, attack_range) \
				and monster.position.distance_squared_to(behavior.center) <= 256.0 \
				and (not instance.dynamic_blocking_enabled or not instance._movement_intersects_dynamic_blocker(actor_id, entity.position, entity.target_position))):
			return DomainResultScript.ok()
		entity.stop_moving()
	var desired_distance := minimum_range + (attack_range - minimum_range) * 0.7
	var direction := monster.position.direction_to(entity.position)
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	var approach_point := monster.position + direction * desired_distance
	var patrolling := has_in_range_weapon and combat_mode != "stationary"
	if patrolling:
		var count := 2 if combat_mode == "shuttle" else 6
		var angle_step := PI / 6.0 if count == 2 else TAU / 6.0
		var minimum_radius := (minimum_range + 1.0) / cos(angle_step * 0.5)
		var maximum_radius := attack_range - 1.0
		if minimum_radius >= maximum_radius:
			return _fail_llm_hunt(entity, starting, &"combat.maneuver_unavailable", "武器有效射程不足以容纳所选走位")
		var angle := float(behavior.angle) if behavior.has("center") else direction.angle()
		var waypoint := (int(behavior.waypoint) + int(reached_waypoint)) % count if behavior.has("center") else 0
		desired_distance = clampf(float(behavior.get("radius", desired_distance)), minimum_radius, maximum_radius)
		var found := false
		for radius: float in [desired_distance, lerpf(desired_distance, minimum_radius, 0.5), minimum_radius, maximum_radius]:
			for rotation in 24:
				var candidate_angle := angle + TAU * rotation / 24.0
				var points := PackedVector2Array()
				for index in count:
					points.append(monster.position + Vector2.from_angle(candidate_angle + angle_step * index) * radius)
				var previous := entity.position
				var valid := true
				for index in range(count + 1):
					var point := points[(waypoint + index) % count]
					if not instance.navigation.segment_is_walkable(previous, point) \
							or Geometry2D.get_closest_point_to_segment(monster.position, previous, point).distance_to(monster.position) < minimum_range \
							or (instance.dynamic_blocking_enabled and (instance._movement_intersects_dynamic_blocker(actor_id, previous, point) \
								or not instance._position_has_dynamic_clearance(point, actor_id, true))):
						valid = false
						break
					previous = point
				if not valid: continue
				approach_point = points[waypoint]
				behavior.merge({"center": monster.position, "angle": candidate_angle, "radius": radius, "waypoint": waypoint}, true)
				found = true
				break
			if found: break
		if not found:
			return _fail_llm_hunt(entity, starting, &"combat.maneuver_unavailable", "找不到满足障碍和射程规则的所选走位")
	else:
		behavior.erase("center")
	var move_sequence := entity.last_input_sequence + 1
	var move_intent := MoveIntentContractScript.new(instance.instance_id, approach_point, move_sequence)
	var move_result := _handle_entity_move(actor_id, move_intent.to_dictionary())
	LlmTraceLoggerScript.record(actor_id, &"hunt_approach", {
		"species_id": species_id,
		"target_id": monster.monster_id,
		"ability_id": selected_for_approach,
		"approach_point": approach_point,
		"distance": distance,
		"ok": bool(move_result.get("ok", false)),
		"code": String(move_result.get("code", "")),
		"message": String(move_result.get("message", "")),
		"combat_mode": combat_mode,
	})
	if not move_result.get("ok", false):
		return _fail_llm_hunt(entity, starting, move_result.code, move_result.message)
	if patrolling:
		entity.set_path(PackedVector2Array([entity.position, approach_point]), approach_point, entity.last_input_sequence)
		if move_result.value.adjusted or not _llm_hunt_path_in_range(entity, monster.position, minimum_range, attack_range):
			return _fail_llm_hunt(entity, starting, &"combat.maneuver_unavailable", "所选走位无法保持在武器有效射程内")
	return DomainResultScript.ok()


func _llm_hunt_path_in_range(entity: AuthoritativeEntity, center: Vector2, minimum_range: float, maximum_range: float) -> bool:
	var previous := entity.position
	if previous.distance_to(center) > maximum_range: return false
	for index in range(entity.path_index, entity.path.size()):
		var point := entity.path[index]
		if point.distance_to(center) > maximum_range \
				or Geometry2D.get_closest_point_to_segment(center, previous, point).distance_to(center) < minimum_range:
			return false
		previous = point
	return entity.position.distance_to(center) >= minimum_range


func _fail_llm_hunt(entity: AuthoritativeEntity, starting: bool, code: StringName, message: String) -> DomainResult:
	entity.stop_moving()
	_llm_hunt_behaviors.erase(entity.entity_id)
	LlmTraceLoggerScript.record(entity.entity_id, &"hunt_behavior_finished", {"error_code": String(code), "message": message})
	_queue_llm_runtime_event(entity.entity_id, &"combat_failed" if starting else &"action_invalidated", {"error_code": String(code), "error_message": message})
	return DomainResultScript.failure(code, message)


func _nearest_llm_hunt_monster(
	instance: AuthoritativeMapInstance,
	actor_position: Vector2,
	species_id: String,
) -> MonsterLifecycle:
	var nearest: MonsterLifecycle
	var nearest_distance := INF
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		if monster.map_instance_id != instance.instance_id or monster.species_id != species_id \
				or not monster.is_alive():
			continue
		var distance := actor_position.distance_squared_to(monster.position)
		if distance < nearest_distance or (is_equal_approx(distance, nearest_distance) \
				and (nearest == null or monster.monster_id < nearest.monster_id)):
			nearest = monster
			nearest_distance = distance
	return nearest


func _handle_llm_gather(intent: PlayerIntent) -> DomainResult:
	if intent.payload.size() != 1:
		return DomainResultScript.failure(&"llm.gather_invalid", "gather intent requires a source")
	var source_id := String(intent.payload.get("source_entity_id", ""))
	if source_id.is_empty():
		return DomainResultScript.failure(&"llm.gather_invalid", "gather source is required")
	var session := sessions.session_for_entity(intent.actor_id)
	if session == null:
		return DomainResultScript.failure(&"llm.actor_missing", "actor has no authoritative session")
	var instance := map_registry.instance_by_id(session.map_instance_id)
	if instance == null or instance.mining_module == null:
		return DomainResultScript.failure(&"mining.not_available", "this map has no configured mining module")
	var source = instance.mining_module.sources.get(source_id)
	if source == null or source.map_instance_id != instance.instance_id or source.remaining <= 0:
		return DomainResultScript.failure(&"llm.source_unavailable", "gather source is no longer available in this map")
	if autosave_service == null:
		return DomainResultScript.failure(&"ability.persistence_required", "gather requires authoritative player state")
	var current := autosave_service.player_for(intent.actor_id)
	if current == null:
		return DomainResultScript.failure(&"ability.player_state_missing", "gather player state is unavailable")
	var allowed := _validate_mining_equipment(current)
	if not allowed.is_ok:
		return allowed
	var skill_state: Variant = current.skills.to_dictionary().get("mining", {})
	if not skill_state is Dictionary:
		return DomainResultScript.failure(&"ability.skill_missing", "mining skill state is invalid")
	var context: Dictionary = allowed.value.duplicate(true)
	context["mining_skill_level"] = maxi(0, int((skill_state as Dictionary).get("level", 0)))
	if context.mining_skill_level < source.required_mining_level:
		return DomainResultScript.failure(&"mining.skill_too_low", "当前采矿技能等级不满足矿源要求")
	var entity: AuthoritativeEntity = instance.entities.get(intent.actor_id)
	var policy: Dictionary = instance.mining_module._policy
	var distance := entity.position.distance_to(source.position)
	if distance < float(policy.minimum_collection_distance) or distance > float(policy.maximum_collection_distance):
		return _start_llm_approach(intent, source.position, float(policy.minimum_collection_distance), float(policy.maximum_collection_distance))
	var mining_intent := UseAbilityIntentContractScript.new(
		instance.instance_id, MiningModuleScript.COLLECT_ABILITY_ID, source.position,
		maxi(intent.sequence, int(instance.mining_module._last_command_sequences.get(intent.actor_id, 0)) + 1),
	)
	var result: Dictionary = instance.handle_use_ability(
		intent.actor_id, mining_intent.to_dictionary(), context
	)
	return DomainResultScript.ok(result.value) if result.ok else DomainResultScript.failure(
		result.code, String(result.get("message", "gather request was rejected"))
	)


func _handle_llm_harvest(intent: PlayerIntent) -> DomainResult:
	if intent.payload.size() != 1:
		return DomainResultScript.failure(&"garden.harvest_invalid", "harvest intent requires a plant_id")
	var plant_id := String(intent.payload.get("plant_id", ""))
	if plant_id.is_empty():
		return DomainResultScript.failure(&"garden.harvest_invalid", "plant_id is required")
	var session := sessions.session_for_entity(intent.actor_id)
	if session == null:
		return DomainResultScript.failure(&"llm.actor_missing", "actor has no authoritative session")
	var instance := map_registry.instance_by_id(session.map_instance_id)
	if instance == null:
		return DomainResultScript.failure(&"garden.map_unavailable", "map instance is unavailable")
	if garden_service == null or not garden_service.catalog.supports_map(String(instance.definition.map_id)):
		return DomainResultScript.failure(&"garden.unavailable", "当前地图不能采摘")
	var plant: Dictionary = garden_service.catalog.plants.get(plant_id, {})
	if plant.is_empty():
		return DomainResultScript.failure(&"garden.plant_missing", "果实不存在")
	if autosave_service == null:
		return DomainResultScript.failure(&"ability.persistence_required", "harvest requires authoritative player state")
	var entity: AuthoritativeEntity = instance.entities.get(intent.actor_id)
	if entity == null:
		return DomainResultScript.failure(&"llm.entity_missing", "actor entity is unavailable")
	var distance := entity.position.distance_to(plant.position)
	if distance > garden_service.catalog.interaction_radius:
		return _start_llm_approach(intent, plant.position, 0.0, garden_service.catalog.interaction_radius)
	if _player_panel_coordinator == null:
		return DomainResultScript.failure(&"panels.unavailable", "player panel coordinator is unavailable")
	var executed: Dictionary = _player_panel_coordinator.execute_session(session, {
		"type": "harvest_garden", "plant_id": plant_id,
	})
	if not bool(executed.get("ok", false)):
		return DomainResultScript.failure(
			StringName(executed.get("code", "garden.harvest_failed")),
			String(executed.get("message", "果实采摘失败")),
		)
	_flush_player_changes()
	return DomainResultScript.ok(executed.get("value", {}))


func _handle_llm_self_repair(intent: PlayerIntent) -> DomainResult:
	var session: ServerSession = sessions.session_for_entity(intent.actor_id)
	var instance: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id) if session != null else null
	if instance == null or instance.combat_module == null:
		return DomainResultScript.failure(&"combat.not_available", "self-repair requires an active combat map")
	var player := autosave_service.player_for(intent.actor_id) if autosave_service != null else null
	if player == null:
		return DomainResultScript.failure(&"ability.player_state_missing", "self-repair requires authoritative player state")
	var skill_state: Variant = player.skills.to_dictionary().get("repair", {})
	if not skill_state is Dictionary:
		return DomainResultScript.failure(&"ability.skill_missing", "repair skill state is invalid")
	var combat_actor: Dictionary = instance.combat_module.actors.get(intent.actor_id, {})
	if combat_actor.is_empty():
		return DomainResultScript.failure(&"combat.unknown_actor", "actor is not registered in this combat map")
	var entity: AuthoritativeEntity = instance.entities.get(intent.actor_id)
	if entity == null:
		return DomainResultScript.failure(&"llm.entity_missing", "actor entity is absent from its map")
	var repair := UseAbilityIntentContractScript.new(
		instance.instance_id, AuthoritativeCombatModule.SELF_REPAIR_ABILITY_ID,
		entity.position, int(combat_actor.get("last_command_sequence", -1)) + 1,
	)
	var result: Dictionary = instance.handle_use_ability(intent.actor_id, repair.to_dictionary(), {
		"repair_skill_level": maxi(0, int((skill_state as Dictionary).get("level", 0))),
	})
	return DomainResultScript.ok(result.value) if result.ok else DomainResultScript.failure(
		result.code, String(result.get("message", "self-repair was rejected"))
	)


func _handle_llm_chat(intent: PlayerIntent) -> DomainResult:
	var channel := String(intent.payload.get("channel", ""))
	var message := String(intent.payload.get("message", ""))
	if channel not in ["area", "party", "private"] or message.strip_edges().is_empty():
		return DomainResultScript.failure(&"llm.chat_invalid", "chat channel and message are required")
	if chat_service == null:
		return DomainResultScript.failure(&"chat.unavailable", "chat service is not initialized")
	var command := {"type": "chat_send", "channel": channel, "message": message}
	if channel == "private":
		var target_entity_id := String(intent.payload.get("target_entity_id", ""))
		if target_entity_id.is_empty():
			return DomainResultScript.failure(&"llm.chat_invalid", "private chat target is required")
		command["target_entity_id"] = target_entity_id
	var executed: DomainResult = chat_service.execute(intent.actor_id, command)
	if not executed.is_ok:
		return executed
	return DomainResultScript.ok({"action": "chat", "channel": channel})


func _inspect_llm_service(actor_id: String, arguments: Dictionary, tool_id: String) -> DomainResult:
	if tool_id == "inspect_private_chat":
		return chat_service.inspect_private_chat(actor_id, arguments.player_name, arguments.cursor)
	if tool_id == "inspect_mail":
		var command := {"type": "query_mailbox"}
		if arguments.section != "all": command["section"] = arguments.section
		return mail_service.execute(actor_id, command)
	var queried := _player_panel_coordinator.execute_session(sessions.session_for_entity(actor_id), {
		"type": "query_production" if arguments.station_id.is_empty() else "query_manufacturing", "station_id": arguments.station_id,
	})
	if not queried.ok: return DomainResultScript.failure(queried.code, queried.message)
	var manufacturing: Dictionary = queried.value.manufacturing.duplicate(true)
	var requested := {}
	for recipe_id: String in arguments.recipe_ids: requested[recipe_id] = true
	var details: bool = not requested.is_empty()
	var recipes: Array[Dictionary] = []
	var skill_levels := {}
	for recipe: Dictionary in manufacturing.recipes:
		skill_levels[recipe.skill_id] = recipe.effective_skill_level
		if details:
			if not requested.has(recipe.recipe_id): continue
			requested.erase(recipe.recipe_id)
			for field: String in ["station_id", "effective_skill_level"]: recipe.erase(field)
			recipes.append(recipe)
		else:
			recipes.append({"recipe_id": recipe.recipe_id, "display_name": recipe.display_name,
				"required_skill_level": recipe.required_skill_level, "can_craft": recipe.can_craft})
	if not requested.is_empty():
		return DomainResultScript.failure(&"manufacturing.recipe_missing", "当前设施没有这些配方：%s；请先查询概要" % str(requested.keys()))
	manufacturing["recipes"] = recipes
	manufacturing["skill_levels"] = skill_levels
	return DomainResultScript.ok({"manufacturing": manufacturing})


func _handle_llm_production(intent: PlayerIntent) -> DomainResult:
	var current: Player = autosave_service.player_for(intent.actor_id) if autosave_service != null else null
	if current == null or _player_panel_coordinator == null:
		return DomainResultScript.failure(&"production.unavailable", "权威生产服务不可用")
	var operation := String(intent.payload.get("operation", ""))
	if operation not in ["start", "pause", "resume", "cancel"]:
		return DomainResultScript.failure(&"production.command", "生产操作无效")
	var command := intent.payload.duplicate(true)
	command.erase("operation")
	command["type"] = operation + "_production"
	command["production_revision"] = current.production.revision
	if operation == "start":
		command["cycles"] = command.get("quantity")
		command.erase("quantity")
		command["inventory_revision"] = current.inventory.revision
	elif operation == "cancel": command["confirm_cancel"] = true
	var executed := _player_panel_coordinator.execute_session(sessions.session_for_entity(intent.actor_id), command)
	return DomainResultScript.ok({"action": command.type, "operation": executed.value.manufacturing.operation,
		"production": executed.value.manufacturing.production}) if executed.ok else DomainResultScript.failure(executed.code, executed.message)


func _handle_llm_social(intent: PlayerIntent) -> DomainResult:
	var service: Variant = {&"friend": friend_service, &"party": party_service, &"trade": trade_service, &"mail": mail_service}.get(intent.intent_kind)
	var operation := String(intent.payload.get("operation", ""))
	var operations: Dictionary = HighLevelPlayerAction.OPERATION_FIELDS.get(StringName("manage_" + intent.intent_kind), {})
	if service == null or not operations.has(operation):
		return DomainResultScript.failure(&"llm.social_invalid", "社交服务或操作无效")
	var command := intent.payload.duplicate(true)
	command.erase("operation")
	command["type"] = String(intent.intent_kind) + "_" + operation
	if intent.intent_kind == &"mail":
		command["type"] = {"send": "send_mail", "read": "mark_mail_read", "delete": "delete_mail"}[operation]
		if operation == "send":
			command["target_entity_id"] = command.get("recipient")
			command.erase("recipient")
	var previous_origin := _llm_social_origin_actor
	_llm_social_origin_actor = intent.actor_id
	var executed: DomainResult = service.execute(intent.actor_id, command)
	_llm_social_origin_actor = previous_origin
	if not executed.is_ok: return executed
	if intent.intent_kind in [&"party", &"trade"]:
		_queue_llm_runtime_event(intent.actor_id, StringName(intent.intent_kind + "_result"), {"operation": operation})
	return DomainResultScript.ok({"action": operation, "result": executed.value})


func _handle_llm_npc_trade(intent: PlayerIntent) -> DomainResult:
	if autosave_service == null or commerce_service == null:
		return DomainResultScript.failure(&"commerce.persistence_required", "NPC trading requires authoritative persistence")
	var operation := String(intent.payload.get("operation", ""))
	var merchant_id := String(intent.payload.get("merchant_id", ""))
	if merchant_id.is_empty() or operation not in ["buy", "sell"]:
		return DomainResultScript.failure(&"commerce.invalid_command", "NPC trade operation or merchant is invalid")
	var session: ServerSession = sessions.session_for_entity(intent.actor_id)
	if session == null or session.has_active_peer():
		return DomainResultScript.failure(&"llm.actor_controlled", "LLM actor has no available session")
	var current_instance: AuthoritativeMapInstance = map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null or _llm_shop_definition(
		String(current_instance.definition.map_id), merchant_id
	).is_empty():
		return DomainResultScript.failure(&"commerce.merchant_not_here", "NPC merchant is not in the current area")
	var current := autosave_service.player_for(intent.actor_id)
	if current == null:
		return DomainResultScript.failure(&"commerce.player_missing", "authoritative player state is unavailable")
	var command := {
		"type": "buy_from_weapon_merchant" if operation == "buy" else "sell_to_weapon_merchant",
		"merchant_id": merchant_id,
		"inventory_revision": current.inventory.revision,
	}
	if operation == "buy":
		if intent.payload.size() != 3:
			return DomainResultScript.failure(&"commerce.invalid_command", "NPC purchase payload is invalid")
		command["definition_id"] = String(intent.payload.get("definition_id", ""))
	else:
		if intent.payload.size() != 4 or typeof(intent.payload.get("quantity")) != TYPE_INT:
			return DomainResultScript.failure(&"commerce.invalid_command", "NPC sale payload is invalid")
		var instance_id := String(intent.payload.get("instance_id", ""))
		var item: GameItem = current.inventory.find(instance_id)
		if item == null or item.locked:
			return DomainResultScript.failure(&"commerce.item_not_sellable", "item is missing or locked")
		command["instance_id"] = instance_id
		command["quantity"] = int(intent.payload.get("quantity", 0))
	var executed: DomainResult = commerce_service.execute(current, command)
	if not executed.is_ok:
		return executed
	var value: Dictionary = executed.value
	var candidate: Player = value.get("candidate")
	if candidate == null or not bool(value.get("changed", false)):
		return DomainResultScript.failure(&"commerce.transaction_invalid", "NPC trade did not produce a player transaction")
	var committed := autosave_service.commit_player(
		intent.actor_id, candidate, false, {}, ["inventory"] as Array[String]
	)
	if not committed.is_ok:
		return committed
	var operation_result: Dictionary = value.get("operation", {}).duplicate(true)
	operation_result["merchant_id"] = merchant_id
	operation_result["currency"] = committed.value.inventory.currency
	return DomainResultScript.ok(operation_result)


func _llm_npc_definitions_for_map(map_id: String) -> Array:
	var definitions: Variant = _llm_npc_catalog.get("npcs", []) if map_id == BASE_HALL_MAP_ID \
			else _llm_npc_catalog.get("maps", {}).get(map_id, [])
	return definitions if definitions is Array else []


func _llm_shop_definition(map_id: String, merchant_id: String) -> Dictionary:
	for raw_npc: Variant in _llm_npc_definitions_for_map(map_id):
		if raw_npc is Dictionary and String(raw_npc.get("id", "")) == merchant_id \
				and String(raw_npc.get("kind", "")) == "shop" \
				and String(raw_npc.get("interaction_service", "")) == "commerce":
			return raw_npc
	return {}


func _handle_llm_objective(intent: PlayerIntent) -> DomainResult:
	if intent.payload.size() != 3:
		return DomainResultScript.failure(&"llm.objective_invalid", "objective intent requires target, provider and operation")
	var objective_id := String(intent.payload.get("objective_id", ""))
	var provider_id := String(intent.payload.get("provider_id", ""))
	var operation := String(intent.payload.get("operation", ""))
	if objective_id.is_empty() or provider_id.is_empty() or operation not in ["accept", "turn_in", "abandon"]:
		return DomainResultScript.failure(&"llm.objective_invalid", "objective target or operation is invalid")
	if autosave_service == null or commerce_service == null:
		return DomainResultScript.failure(&"commerce.persistence_required", "objective actions require authoritative persistence")
	var current := autosave_service.player_for(intent.actor_id)
	if current == null:
		return DomainResultScript.failure(&"ability.player_state_missing", "objective player state is unavailable")
	var command_type: String = {
		"accept": "accept_weapon_merchant_task",
		"turn_in": "turn_in_weapon_merchant_task",
		"abandon": "abandon_weapon_merchant_task",
	}[operation]
	var command := {"type": command_type, "merchant_id": provider_id, "task_id": objective_id}
	if operation == "turn_in":
		command["inventory_revision"] = current.inventory.revision
	var executed: DomainResult = commerce_service.execute(current, command)
	if not executed.is_ok:
		return executed
	var value: Dictionary = executed.value
	var candidate: Player = value.get("candidate")
	if candidate == null or not bool(value.get("changed", false)):
		return DomainResultScript.failure(&"llm.objective_invalid", "objective operation produced no player transaction")
	var committed := autosave_service.commit_player(
		intent.actor_id, candidate, false, {},
		["achievements", "character", "daily", "inventory", "quests", "skills", "vehicle"] as Array[String],
	)
	if not committed.is_ok:
		return committed
	if _actor_controller_registry.has_controller(intent.actor_id):
		queue_llm_event(intent.actor_id, {
			"event_id": "%s.objective.%s.%d" % [intent.actor_id, objective_id, committed.value.revision],
			"event_kind": "objective_result",
			"payload": {"objective_id": objective_id, "provider_id": provider_id, "operation": operation},
		})
	return DomainResultScript.ok({"action": operation, "objective_id": objective_id, "provider_id": provider_id})


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
		var current := autosave_service.player_for(session.entity_id)
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
		var skill_state: Variant = current.skills.to_dictionary().get(skill_id, {})
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
	if _map_transition_coordinator == null:
		return _failure(
			&"map_transition.coordinator_unavailable",
			"map transition coordinator is not initialized",
		)
	var result := _map_transition_coordinator.execute(
		peer_id,
		raw_intent,
		server_tick,
		float(server_tick) / float(config.simulation_hz),
		config.map_transition_radius,
		config.default_movement_speed,
	)
	if result.get("ok", false):
		var session: ServerSession = sessions.session_for_peer(peer_id)
		if session != null:
			if trade_service != null:
				trade_service.cancel_for_entity(session.entity_id)
			if party_service != null:
				party_service.cancel_invites_for_entity(session.entity_id)
	return result


## 校验战车确已击毁，并由权威时钟预约三秒后的基地救援。
## [param peer_id] 调用方传入的 `peer_id` 参数。
## [param raw_intent] 调用方传入的 `raw_intent` 参数。
## 返回该函数计算、查询或操作得到的结果。
func handle_peer_vehicle_recovery(peer_id: int, raw_intent: Variant) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"vehicle_recovery.session_missing", "peer has no active session")
	return _handle_vehicle_recovery(session, raw_intent)


func _handle_vehicle_recovery(session: ServerSession, raw_intent: Variant) -> Dictionary:
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
		"peer_id": session.peer_id,
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
		if int(pending.peer_id) <= 0:
			if not result.ok: _queue_llm_runtime_event(entity_id, &"action_invalidated", {"action": "return_to_base", "message": result.message})
			continue
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
		_map_transition_coordinator.place_transitioned_entity(recovered_entity, destination, spawn_position)
	else:
		var recovery_state := autosave_service.player_for(entity_id) \
			if autosave_service != null else null
		if recovery_state != null:
			var captured_recovery: DomainResult = _capture_player_runtime(recovery_state)
			if not captured_recovery.is_ok:
				return _failure(captured_recovery.error_code, captured_recovery.error_message)
			var stored_recovery := autosave_service.commit_player(entity_id, recovery_state)
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
		_map_transition_coordinator.copy_transitioned_entity_state(source_entity, recovered_entity)
		_map_transition_coordinator.copy_transitioned_vehicle_state(source, destination, entity_id)
		if not source.remove_entity(entity_id):
			destination.remove_entity(entity_id)
			return _failure(&"vehicle_recovery.atomic_commit_failed", "source entity disappeared")
		session.map_instance_id = destination.instance_id
	var recovered_vehicle := destination.vehicle_combat_state_for(entity_id)
	if recovered_vehicle == null:
		return _failure(&"vehicle_recovery.combat_state_missing", "base vehicle state is missing")
	if recovered_vehicle.health <= 0:
		recovered_vehicle.health = maxi(1, ceili(float(recovered_vehicle.max_health) * VEHICLE_RECOVERY_HEALTH_RATIO))
	if autosave_service != null:
		var player := autosave_service.player_for(entity_id)
		if player != null: _capture_player_runtime(player)
	_queue_llm_runtime_event(entity_id, &"forced_transfer", {"map_id": String(destination.definition.map_id), "reason": "vehicle_recovery"})
	var joined := MapJoinedContract.new(
		String(destination.definition.map_id), destination.instance_id, entity_id,
		recovered_entity.position, destination.definition.schema_version, server_tick,
	)
	return _success({
		"map_joined": joined.to_dictionary(),
		"world_snapshot": destination.world_snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		),
		"local_snapshot": destination.local_snapshot_for_actor(server_tick, entity_id),
		"recovered_health": recovered_vehicle.health,
		"input_sequence": int(pending["input_sequence"]),
	})


## 构建指定会话的共享/私有初始快照。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot_bundle_for_peer(peer_id: int) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return {}
	var session_map := map_registry.instance_by_id(session.map_instance_id)
	if session_map == null:
		return {}
	return {
		"world_snapshot": session_map.world_snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		),
		"local_snapshot": session_map.local_snapshot_for_actor(server_tick, session.entity_id),
	}


## 处理绑定到 peer 会话的人物、背包与战车面板命令。
## [param peer_id] 由传输层提供的不可伪造 peer 标识。
## [param command] 客户端面板操作意图。
## 返回包含同一事务 revision 的三面板权威快照或拒绝原因。
## 设计：角色身份只取自会话；变更由领域服务校验后一次性提交完整玩家聚合。
func handle_peer_player_panel_command(peer_id: int, command: Dictionary) -> Dictionary:
	_clear_due_ground_items()
	if _player_panel_coordinator == null:
		return _failure(
			&"panel_coordinator.unavailable",
			"player panel coordinator is not initialized",
		)
	return _player_panel_coordinator.execute(peer_id, command)


## 处理绑定到 peer 会话的社交命令；角色身份始终来自服务端会话。
func handle_peer_social_command(peer_id: int, command: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"social.unauthenticated_peer", "open a session before sending social commands")
	if party_service == null or chat_service == null or trade_service == null \
		or friend_service == null or mail_service == null:
		return _failure(&"social.unavailable", "social services are not initialized")
	var command_type := String(command.get("type", ""))
	if not PartyServiceScript.handles(command_type) and not ChatServiceScript.handles(command_type) \
			and not TradeServiceScript.handles(command_type) and not FriendServiceScript.handles(command_type) \
			and not MailServiceScript.handles(command_type):
		return _failure(&"social.unsupported_command", "social command is not implemented")
	var executed: DomainResult
	if PartyServiceScript.handles(command_type):
		executed = party_service.execute(session.entity_id, command)
	elif ChatServiceScript.handles(command_type):
		executed = chat_service.execute(session.entity_id, command)
	elif TradeServiceScript.handles(command_type):
		executed = trade_service.execute(session.entity_id, command)
	elif FriendServiceScript.handles(command_type):
		executed = friend_service.execute(session.entity_id, command)
	else:
		executed = mail_service.execute(session.entity_id, command)
	return _success(executed.value) if executed.is_ok else _failure(
		executed.error_code, executed.error_message
	)


func _party_map_for_entity(entity_id: String) -> String:
	var session: ServerSession = sessions.session_for_entity(entity_id)
	return session.map_instance_id if session != null else ""


func _party_display_name_for_entity(entity_id: String) -> String:
	var player: Player = autosave_service.player_for(entity_id) if autosave_service != null else null
	if player != null:
		return player.display_name
	if player_state_repository != null:
		var loaded := player_state_repository.load_player(entity_id)
		if loaded.is_ok:
			var record: PlayerStateRecord = loaded.value
			return record.display_name
	return entity_id


func _party_entity_is_active(entity_id: String) -> bool:
	var session: ServerSession = sessions.session_for_entity(entity_id)
	return session != null and session.is_online()


func _friend_player_for_entity(entity_id: String) -> Player:
	return autosave_service.player_for(entity_id) if autosave_service != null else null


## 返回昵称完全匹配的在线角色，避免向客户端暴露目录或内部角色标识。
## [param display_name] 待精确匹配的玩家昵称。
func _find_active_entities_by_display_name(display_name: String) -> Array[String]:
	var matches: Array[String] = []
	for session: ServerSession in sessions.online_sessions():
		if _party_display_name_for_entity(session.entity_id) == display_name:
			matches.append(session.entity_id)
	return matches


## 返回在线或已持久化的精确昵称匹配，供好友与信件服务解析。
func _find_entities_by_display_name(display_name: String) -> Array[String]:
	var matches := _find_active_entities_by_display_name(display_name)
	if player_state_repository == null:
		return matches
	for entity_id: String in player_state_repository.find_player_ids_by_display_name(display_name):
		if entity_id not in matches:
			matches.append(entity_id)
	return matches


func _chat_entities_in_map(map_instance_id: String) -> Array[String]:
	var entities: Array[String] = []
	for session: ServerSession in sessions.online_sessions():
		if session.map_instance_id == map_instance_id:
			entities.append(session.entity_id)
	return entities


func _send_party_message(entity_id: String, message: Dictionary) -> void:
	var session := sessions.session_for_entity(entity_id)
	if session == null:
		return
	if session.has_active_peer():
		_send_reliable(session.peer_id, message)
	elif session.is_llm:
		var message_type := String(message.get("type", "social_event"))
		if entity_id == _llm_social_origin_actor:
			return
		var chat_event: Dictionary = message.get("result", {}).get("value", {}).get("event", {})
		if message_type == "chat_event" and String(chat_event.get("sender_entity_id", "")) == entity_id:
			return
		queue_llm_event(entity_id, {
			"event_id": "social.%s.%d" % [message_type, Time.get_ticks_usec()],
			"event_kind": message_type,
			"payload": {"message": message.duplicate(true)},
		})


func _commit_friend_relation(actor_id: String, target_id: String, relation: String, add: bool) -> DomainResult:
	if autosave_service == null or player_panel_service == null:
		return DomainResultScript.failure(&"friend.persistence_required", "friend persistence is unavailable")
	var actor := autosave_service.player_for(actor_id)
	var target := autosave_service.player_for(target_id)
	if actor == null or actor_id == target_id:
		return DomainResultScript.failure(&"friend.target_missing", "friend target state is unavailable")
	if relation == "friend" and add and target == null:
		return DomainResultScript.failure(&"friend.target_missing", "friend target state is unavailable")
	if relation == "friend" and (add and (actor.enemy_ids.has(target_id) or target.enemy_ids.has(actor_id))):
		return DomainResultScript.failure(&"friend.relation_conflict", "a friend cannot also be an enemy")
	var actor_candidate_result := PlayerTransaction.prepare(actor, ["social"], player_panel_service.catalog)
	if not actor_candidate_result.is_ok: return actor_candidate_result
	var actor_candidate: Player = actor_candidate_result.value
	var candidates: Dictionary = {actor_id: actor_candidate}
	var additional_records: Dictionary = {}
	var additional_revisions: Dictionary = {}
	if relation == "friend":
		if target == null:
			if player_state_repository == null:
				return DomainResultScript.failure(&"friend.persistence_required", "friend persistence is unavailable")
			var offline_target_result := player_state_repository.load_player(target_id)
			if offline_target_result.is_ok:
				var offline_target: PlayerStateRecord = offline_target_result.value
				offline_target.friend_ids.erase(actor_id)
				additional_records[target_id] = offline_target
				additional_revisions[target_id] = offline_target.revision
			elif offline_target_result.error_code != &"persistence.character_not_found":
				return offline_target_result
		else:
			var target_candidate_result := PlayerTransaction.prepare(target, ["social"], player_panel_service.catalog)
			if not target_candidate_result.is_ok: return target_candidate_result
			var target_candidate: Player = target_candidate_result.value
			target_candidate.friend_ids = _replace_relation(target.friend_ids, actor_id, add)
			candidates[target_id] = target_candidate
		actor_candidate.friend_ids = _replace_relation(actor.friend_ids, target_id, add)
	elif relation == "enemy":
		if add and actor.friend_ids.has(target_id):
			return DomainResultScript.failure(&"friend.relation_conflict", "a friend cannot also be an enemy")
		actor_candidate.enemy_ids = _replace_relation(actor.enemy_ids, target_id, add)
	else:
		return DomainResultScript.failure(&"friend.invalid_relation", "unsupported friend relation")
	if relation == "friend":
		var committed: DomainResult = autosave_service.commit_players_atomic(
			candidates, ["social"] as Array[String], additional_records, additional_revisions
		)
		if not committed.is_ok: return committed
	else:
		var committed: DomainResult = autosave_service.commit_players_atomic(
			candidates, ["social"] as Array[String]
		)
		if not committed.is_ok: return committed
	return DomainResultScript.ok({"relation": relation, "added": add})


func _commit_mailbox(entity_id: String, mailbox: Array) -> DomainResult:
	if autosave_service == null or player_panel_service == null:
		return DomainResultScript.failure(&"mail.persistence_required", "mail persistence is unavailable")
	var player := autosave_service.player_for(entity_id)
	if player == null:
		if player_state_repository == null:
			return DomainResultScript.failure(&"mail.persistence_required", "mail persistence is unavailable")
		return player_state_repository.transact_player(entity_id, func(record: PlayerStateRecord) -> DomainResult:
			record.mailbox = mailbox.duplicate(true)
			return record.validate()
		)
	var candidate_result := PlayerTransaction.prepare(player, ["social"], player_panel_service.catalog)
	if not candidate_result.is_ok: return candidate_result
	var candidate: Player = candidate_result.value
	candidate.mailbox = mailbox.duplicate(true)
	var candidates: Dictionary = {}
	candidates[entity_id] = candidate
	var committed: DomainResult = autosave_service.commit_players_atomic(
		candidates, ["social"] as Array[String]
	)
	if not committed.is_ok: return committed
	return DomainResultScript.ok({"mailbox": candidate.mailbox.duplicate(true)})


func _mailbox_for_entity(entity_id: String) -> DomainResult:
	var player := autosave_service.player_for(entity_id) if autosave_service != null else null
	if player != null:
		return DomainResultScript.ok(player.mailbox.duplicate(true))
	if player_state_repository == null:
		return DomainResultScript.failure(&"mail.target_unavailable", "mail target state is unavailable")
	var loaded := player_state_repository.load_player(entity_id)
	if not loaded.is_ok:
		return DomainResultScript.failure(&"mail.target_unavailable", "mail target state is unavailable")
	var record: PlayerStateRecord = loaded.value
	return DomainResultScript.ok(record.mailbox.duplicate(true))


func _replace_relation(current: Array[String], target_id: String, add: bool) -> Array[String]:
	var result := current.duplicate()
	if add and target_id not in result:
		result.append(target_id)
	elif not add:
		result.erase(target_id)
	return result


func _validate_trade_item(entity_id: String, instance_id: String, quantity: int) -> DomainResult:
	var player := autosave_service.player_for(entity_id) if autosave_service != null else null
	if player == null:
		return DomainResultScript.failure(&"trade.actor_missing", "authoritative player state is unavailable")
	var item := player.inventory.find(instance_id)
	if item == null:
		return DomainResultScript.failure(&"trade.item_missing", "trade item is not in the actor inventory")
	if item.locked or item.bound:
		return DomainResultScript.failure(&"trade.item_not_tradeable", "locked or bound items cannot be traded")
	if quantity <= 0 or quantity > item.quantity:
		return DomainResultScript.failure(&"trade.invalid_quantity", "trade quantity exceeds the available item quantity")
	return DomainResultScript.ok({
		"definition_id": item.definition_id,
		"display_name": item.display_name,
		"quantity": quantity,
		"max_stack": item.max_stack,
	})


func _validate_trade_currency(entity_id: String, currency: int) -> DomainResult:
	var player := autosave_service.player_for(entity_id) if autosave_service != null else null
	if player == null:
		return DomainResultScript.failure(&"trade.actor_missing", "authoritative player state is unavailable")
	if currency < 0 or currency > player.inventory.currency:
		return DomainResultScript.failure(&"trade.invalid_currency", "trade currency exceeds the actor balance")
	return DomainResultScript.ok({"inventory_revision": player.inventory.revision})


func _trade_inventory_revision(entity_id: String) -> DomainResult:
	var player := autosave_service.player_for(entity_id) if autosave_service != null else null
	if player == null:
		return DomainResultScript.failure(&"trade.actor_missing", "authoritative player state is unavailable")
	return DomainResultScript.ok(player.inventory.revision)


func _commit_trade(trade: Dictionary) -> DomainResult:
	if autosave_service == null or player_panel_service == null:
		return DomainResultScript.failure(&"trade.persistence_required", "trade requires authoritative player persistence")
	var members: Array = trade.get("members", [])
	if members.size() != 2:
		return DomainResultScript.failure(&"trade.invalid_state", "trade must contain two players")
	var first_id := String(members[0])
	var second_id := String(members[1])
	if first_id.is_empty() or first_id == second_id:
		return DomainResultScript.failure(&"trade.invalid_state", "trade must contain two distinct players")
	var offers: Dictionary = trade.get("offers", {})
	var candidates: Dictionary = {}
	var before: Dictionary = {}
	var transfers: Dictionary = {first_id: [], second_id: []}
	var currency_by_member: Dictionary = {}
	var summary: Dictionary = {}
	for member_id: String in [first_id, second_id]:
		if not _party_entity_is_active(member_id):
			return DomainResultScript.failure(&"trade.participant_unavailable", "both trade participants must remain online")
		var current := autosave_service.player_for(member_id)
		var offer: Dictionary = offers.get(member_id, {})
		if current == null or offer.is_empty() or current.inventory.revision != int(offer.get("inventory_revision", -1)):
			return DomainResultScript.failure(&"trade.inventory_changed", "inventory changed after the trade was locked")
		var offered_currency := int(offer.get("currency", -1))
		if offered_currency < 0 or offered_currency > current.inventory.currency:
			return DomainResultScript.failure(&"trade.invalid_currency", "trade currency exceeds the actor balance")
		var prepared := PlayerTransaction.prepare(current, ["inventory"], player_panel_service.catalog)
		if not prepared.is_ok:
			return DomainResultScript.failure(prepared.error_code, prepared.error_message)
		before[member_id] = current
		candidates[member_id] = prepared.value
		currency_by_member[member_id] = offered_currency
		summary[member_id] = {"items": [], "currency": offered_currency}
	var seen_items: Dictionary = {}
	for source_id: String in [first_id, second_id]:
		var target_id := second_id if source_id == first_id else first_id
		var source_offer: Dictionary = offers[source_id]
		var source_candidate: Player = candidates[source_id]
		for item_offer: Dictionary in source_offer.get("items", []):
			var instance_id := String(item_offer.get("instance_id", ""))
			var quantity := int(item_offer.get("quantity", 0))
			if instance_id.is_empty() or seen_items.has(instance_id):
				return DomainResultScript.failure(&"trade.invalid_item", "trade contains a duplicate or empty item identity")
			seen_items[instance_id] = true
			var source_item := source_candidate.inventory.find(instance_id)
			if source_item == null or source_item.locked or source_item.bound \
					or quantity <= 0 or quantity > source_item.quantity:
				return DomainResultScript.failure(&"trade.item_changed", "a traded item is no longer available")
			var copied_item: DomainResult = PlayerTransaction._item(source_item, player_panel_service.catalog)
			if not copied_item.is_ok:
				return DomainResultScript.failure(copied_item.error_code, copied_item.error_message)
			var transfer: GameItem = copied_item.value
			transfer.quantity = quantity
			if quantity != source_item.quantity:
				transfer.instance_id = "trade." + Crypto.new().generate_random_bytes(16).hex_encode()
			var removed := source_candidate.inventory.remove_quantity(instance_id, quantity)
			if not removed.is_ok:
				return DomainResultScript.failure(removed.error_code, removed.error_message)
			transfers[target_id].append(transfer)
			var traded_items: Array = summary[source_id]["items"]
			traded_items.append({
				"instance_id": instance_id,
				"definition_id": source_item.definition_id,
				"quantity": quantity,
			})
			summary[source_id]["items"] = traded_items
	for target_id: String in [first_id, second_id]:
		var target_candidate: Player = candidates[target_id]
		var source_id := second_id if target_id == first_id else first_id
		var outgoing := int(currency_by_member[target_id])
		var incoming := int(currency_by_member[source_id])
		if outgoing > 0:
			var spent := target_candidate.inventory.spend_currency(outgoing)
			if not spent.is_ok:
				return spent
		if incoming > 0:
			if target_candidate.inventory.currency > 9223372036854775807 - incoming:
				return DomainResultScript.failure(&"trade.currency_overflow", "trade currency exceeds the maximum balance")
			target_candidate.inventory.currency += incoming
			target_candidate.inventory.revision += 1
		for item: GameItem in transfers[target_id]:
			var added := target_candidate.inventory.add_reward(item)
			if not added.is_ok:
				return DomainResultScript.failure(added.error_code, added.error_message)
	var changes: Dictionary = {}
	for member_id: String in [first_id, second_id]:
		changes[member_id] = player_panel_service.changes(before[member_id], candidates[member_id])
	var committed := autosave_service.commit_players_atomic(
		candidates, ["inventory"] as Array[String]
	)
	if not committed.is_ok:
		return committed
	for member_id: String in [first_id, second_id]:
		var change: PlayerChange = changes[member_id]
		change.revision = autosave_service.player_for(member_id).revision
		_queue_player_change(member_id, change)
	return DomainResultScript.ok({"members": members.duplicate(), "summary": summary})


func _player_for_panel(entity_id: String) -> Player:
	return autosave_service.player_for(entity_id) if autosave_service != null else null


func _panel_persistence_available() -> bool:
	return autosave_service != null


func _commit_panel_player(
	entity_id: String,
	candidate: Player,
	is_manufacturing: bool,
	ground_transfer: Dictionary = {},
	domains: Array[String] = [],
) -> DomainResult:
	if autosave_service == null:
		return DomainResultScript.failure(&"panels.persistence_required", "player persistence is unavailable")
	var committed := autosave_service.commit_player(entity_id, candidate, false, ground_transfer, domains)
	if committed.is_ok and is_manufacturing and _production_runtime != null:
		_production_runtime.track(committed.value)
	return committed


func _update_panel_runtime(state: Player) -> DomainResult:
	if autosave_service == null:
		return DomainResultScript.failure(&"panels.persistence_required", "player persistence is unavailable")
	return autosave_service.update_runtime_state(state.entity_id, state, ["daily"] as Array[String])


func _scene_players_for_panel(map_instance_id: String) -> Dictionary:
	return ScenePlayerListProjector.build(map_instance_id, sessions, autosave_service)


## 消费仅来自战斗模块的死亡事件，进度进入同一玩家存档并推送任务日志。
## [param event] 权威战斗模块确认的击杀事件。
func _apply_quest_kill(event: Dictionary) -> void:
	if autosave_service == null or commerce_service == null:
		return
	var entity_id := String(event.get("killer_id", ""))
	var current := autosave_service.player_for(entity_id)
	if current == null:
		return
	var change := _kill_progression.apply(current, event)
	if change == null: return
	autosave_service.update_runtime_state(entity_id, current,
		["quests", "daily", "achievements", "vehicle"] as Array[String])
	change.revision = current.revision
	if change.attributes_changed: _refresh_achievement_combat(entity_id, current)
	_queue_player_change(entity_id, change)
	if not change.quests.is_empty() or not change.daily.is_empty():
		_queue_llm_runtime_event(entity_id, &"objective_changed", {
			"source": "monster_kill",
			"species_id": String(event.get("species_id", "")),
			"task_count": change.quests.size(),
			"daily_changed": not change.daily.is_empty(),
		})


## 应用地图实例产出的权威技能成长事件，并按升级语义选择即时提交或自动存档。
## [param progression_event] 含玩家实体、技能、来源及客观结算值的内部事件。
## 设计：成长写入在线聚合，升级同步综合等级；持久化仍由既有检查点和退出负责。
func _apply_skill_progression_event(progression_event: Dictionary) -> void:
	if autosave_service == null or player_panel_service == null:
		return
	var entity_id := String(progression_event.get("entity_id", ""))
	if entity_id.is_empty():
		return
	var granted := autosave_service.apply_skill_progression(entity_id,
		player_panel_service.grant_progression.bind(progression_event))
	if not granted.is_ok:
		if granted.error_code != &"progression.no_experience":
			push_warning("Skill progression rejected [%s]: %s" % [
				granted.error_code, granted.error_message,
			])
		return
	var progression: Dictionary = granted.value
	var session: ServerSession = sessions.session_for_entity(entity_id)
	var upgraded := bool(progression.get("upgraded", false))
	if upgraded and session != null and session.has_active_peer():
		_pending_level_ups.append({"peer": session.peer_id, "message": {"type": "skill_level_up",
			"result": _wire_result(_success({"skill_id": String(progression.get("skill_id", "")),
				"new_level": int(progression.get("new_level", 0))}))}})
	if bool(progression.get("visible_progress_changed", false)):
		var player := autosave_service.player_for(entity_id)
		_queue_player_change(entity_id, player_panel_service.progression_change(player, String(progression.skill_id), upgraded))


## 合并同一权威刻的通知；领域状态已经逐事件按原顺序提交。
## [param entity_id] 玩家身份。[param change] 本次最终值。
func _queue_player_change(entity_id: String, change: PlayerChange) -> void:
	if _pending_player_changes.has(entity_id): _pending_player_changes[entity_id].merge(change)
	else: _pending_player_changes[entity_id] = change


## 在发布世界快照前封存增量，再调用可能同步重入的传输信号。
func _flush_player_changes() -> void:
	var level_ups := _pending_level_ups
	_pending_level_ups = []
	for entity_id: String in _pending_player_changes.keys():
		if not _pending_player_changes.has(entity_id): continue
		var session := sessions.session_for_entity(entity_id)
		if session == null or not session.has_active_peer():
			_pending_player_changes.erase(entity_id)
			continue
		_send_reliable(session.peer_id, {"type": "player_changed", "result": _wire_result(_success({"player_change": {}}))})
	for level_up: Dictionary in level_ups: _send_reliable(level_up.peer, level_up.message)


## 将地图到期的采矿周期原子地写入背包，再扣除矿源储量并发放采矿经验。
## [param instance] 调用方传入的 `instance` 参数。
func _settle_mining_cycles(instance: AuthoritativeMapInstance) -> void:
	if instance == null or autosave_service == null or player_panel_service == null:
		return
	for cycle: Dictionary in instance.drain_mining_cycles():
		var token := String(cycle.get("token", ""))
		var entity_id := String(cycle.get("actor_id", ""))
		var current := autosave_service.player_for(entity_id)
		if token.is_empty() or current == null:
			instance.reject_mining_cycle(token)
			continue
		var source_ready: DomainResult = instance.mining_module.prepare_cycle(token)
		if not source_ready.is_ok:
			instance.reject_mining_cycle(token)
			if source_ready.error_code != &"mining.cycle_missing":
				_send_mining_rejection(entity_id, source_ready.error_code, source_ready.error_message)
			continue
		var allowed := _validate_mining_equipment(current)
		if not allowed.is_ok:
			instance.reject_mining_cycle(token)
			_send_mining_rejection(entity_id, allowed.error_code, allowed.error_message)
			continue
		var vehicle_state := instance.vehicle_combat_state_for(entity_id)
		var energy_cost := float(allowed.value.get("working_energy_per_mining_cycle", 0.0))
		var available_energy := vehicle_state.working_energy if vehicle_state != null else current.vehicle.reserve_energy
		if available_energy + 0.000001 < energy_cost:
			instance.reject_mining_cycle(token)
			_send_mining_rejection(
				entity_id, &"combat.insufficient_working_energy", "working energy is insufficient for mining"
			)
			continue
		var achievement := current.achievements.prepare(AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED,
			String(cycle.get("item_definition_id", "")), int(cycle.get("quantity", 0)), token))
		var previous_bonus := current.achievements.bonuses().to_dictionary() if not achievement.is_empty() else {}
		var granted := player_panel_service.receive_loot(current, {
			"loot_id": token,
			"item_definition_id": String(cycle.get("item_definition_id", "")),
			"quantity": int(cycle.get("quantity", 0)),
		})
		if not granted.is_ok:
			instance.reject_mining_cycle(token)
			_send_mining_rejection(entity_id, granted.error_code, granted.error_message)
			if granted.error_code == &"inventory_full":
				_queue_llm_runtime_event(entity_id, &"inventory_full", {
					"source": "mining",
					"inventory_used": current.inventory.items().size(),
					"inventory_capacity": current.inventory.capacity,
				})
			continue
		if vehicle_state != null:
			var consumed := vehicle_state.consume_working_energy(energy_cost)
			assert(consumed.is_ok)
			current.vehicle.reserve_energy = vehicle_state.reserve_energy
			current.vehicle.working_energy = vehicle_state.working_energy
		else:
			current.vehicle.reserve_energy -= energy_cost
		var committed = instance.commit_mining_cycle(token)
		current.achievements.commit(achievement)
		var stored := autosave_service.commit_player(
			entity_id, current, false, {}, ["achievements", "character", "inventory", "skills", "vehicle"] as Array[String]
		)
		assert(committed.is_ok and stored.is_ok)
		if committed.is_ok and stored.is_ok and _actor_controller_registry != null \
			and _actor_controller_registry.has_controller(entity_id):
			queue_llm_event(entity_id, {
				"event_id": "%s.gather.%s" % [entity_id, token],
				"event_kind": "gather_result",
				"payload": {
					"source_id": String(committed.value.get("source_id", "")),
					"quantity": int(committed.value.get("quantity", 0)),
					"remaining": int(committed.value.get("remaining", 0)),
					"depleted": bool(committed.value.get("depleted", false)),
				},
			})
		var change := player_panel_service.pickup_change(current, granted.value)
		if not achievement.is_empty():
			change.achievements[achievement.key] = achievement.count
			var bonus := current.achievements.bonuses()
			change.attributes_changed = previous_bonus != bonus.to_dictionary()
			if change.attributes_changed:
				current.vehicle.achievement_bonuses = bonus
				current.vehicle.reconcile_loadout_state(false)
		var event: Dictionary = committed.value
		var mining_durability_changed := false
		if instance.combat_module != null and instance.combat_module.actors.has(entity_id):
			var condition: EquipmentConditionLoadout = instance.combat_module.actors[entity_id].equipment_condition
			var condition_before := condition.snapshot()
			condition.record_use("mining")
			var condition_after := condition.snapshot()
			mining_durability_changed = _durability_changed(condition_before, condition_after)
			# 采矿成功后立即把累计余量和耐久写回在线聚合；否则普通磨损只会
			# 在下一次自动存档或装备损坏时才可见。
			EquipmentConditionCapture.apply(current, condition_after)
			var condition_stored := autosave_service.update_runtime_state(
				entity_id, current, ["vehicle"] as Array[String]
			)
			assert(condition_stored.is_ok)
			condition.clear_durability_sync()
		if mining_durability_changed:
			change.merge(player_panel_service.vehicle_durability_change(current))
		if change.attributes_changed: _refresh_achievement_combat(entity_id, current)
		_queue_player_change(entity_id, change)
		_apply_skill_progression_event({
			"entity_id": entity_id,
			"source": "mined_material",
			"skill_id": "mining",
			"quantity": int(event["quantity"]),
			"experience_coefficient": float(event["experience_coefficient"]),
		})
		var session := sessions.session_for_entity(entity_id)
		_queue_player_change(entity_id, player_panel_service.progression_change(current, "mining", false))
		if session != null and session.has_active_peer():
			_send_reliable(session.peer_id, {
				"type": "mining_collected",
				"result": _wire_result(_success({
					"mining_event": event,
					"player_change": {},
				})),
			})


## 热更新成就及食品战斗增益，保留冷却、命令序号、维修周期和已发射弹体。
## [param entity_id] 已完成权威结算的玩家。
## [param state] 新增益所在的已提交状态。
func _refresh_achievement_combat(entity_id: String, state: Player) -> void:
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
		if not target.is_vehicle_combat_active() and loadout.error_code == &"equipment.chassis_required_for_field":
			return
		push_error("Achievement combat update failed: " + loadout.error_message)
		return
	var updated := target.refresh_achievement_loadout(entity_id, loadout.value)
	if not updated.is_ok:
		push_error("Achievement combat update failed: " + updated.error_message)


## 整点耐久变化时同步存档和面板；装备损坏时额外重算战斗装配。
## [param instance] 已推进本刻战斗与采矿的地图。
func _settle_equipment_conditions(instance: AuthoritativeMapInstance) -> void:
	if autosave_service == null or player_panel_service == null or instance.combat_module == null:
		return
	for entity_id: String in instance.combat_module.actors:
		var condition: EquipmentConditionLoadout = instance.combat_module.actors[entity_id].equipment_condition
		if not condition.needs_recalculation and not condition.needs_durability_sync: continue
		var current := autosave_service.player_for(entity_id)
		if current == null: continue
		var captured: DomainResult = _capture_player_runtime(current)
		if not captured.is_ok: continue
		if not condition.needs_recalculation:
			var condition_stored := autosave_service.update_runtime_state(
				entity_id, current, ["vehicle"] as Array[String]
			)
			if not condition_stored.is_ok: continue
			condition.clear_durability_sync()
			var session := sessions.session_for_entity(entity_id)
			if session != null and session.has_active_peer():
				_queue_player_change(entity_id, player_panel_service.vehicle_durability_change(current))
			continue
		var loadout := _build_entity_combat_loadout(instance, current)
		if not loadout.is_ok:
			push_error("Equipment wear refresh failed: " + loadout.error_message)
			continue
		var stored := autosave_service.commit_player(
			entity_id, current, false, {}, ["vehicle"] as Array[String]
		)
		if not stored.is_ok: continue
		instance.refresh_achievement_loadout(entity_id, loadout.value)
		if instance.mining_module != null: instance.mining_module.interrupt(entity_id, &"equipment_broken")
		var session := sessions.session_for_entity(entity_id)
		if session != null and session.has_active_peer():
			_queue_player_change(entity_id, player_panel_service.vehicle_durability_change(current))


## 复用完整玩家聚合校验采矿装配，不信任客户端声明的武器类型。
## [param state] 服务器保存的最新角色状态。
## 返回开始和结算阶段共用的装备校验结果。
func _validate_mining_equipment(state: Player) -> DomainResult:
	if player_panel_service == null:
		return DomainResult.failure(&"mining.state_unavailable", "mining player aggregate is unavailable")
	var player := state
	var checked := player.vehicle.loadout.validate_mining(player.skills.base_level("mining"))
	if not checked.is_ok:
		return checked
	return DomainResult.ok({"mining_time_reduction_ms": player.vehicle.loadout.attachment_bonus("mining_time_ms"),
		"mining_power": player.vehicle.clothing_bonuses.apply_value("mining_power", 0),
		"working_energy_per_mining_cycle": (player.vehicle.loadout.at(1) as VehicleMiningArm).working_energy_per_mining_cycle,
		"prospecting_chance": player.vehicle.clothing_bonuses.trait_value("prospecting")})


## 向仍在线的采矿者报告异步背包/存档拒绝。
## [param entity_id] 调用方传入的 `entity_id` 参数。
## [param code] 调用方传入的 `code` 参数。
## [param message] 调用方传入的 `message` 参数。
func _send_mining_rejection(entity_id: String, code: StringName, message: String) -> void:
	_queue_llm_runtime_event(entity_id, &"action_invalidated", {"action": "gather_mine", "error_code": String(code), "message": message})
	var session := sessions.session_for_entity(entity_id)
	if session == null or not session.has_active_peer():
		return
	_send_reliable(session.peer_id, {
		"type": "command_rejected",
		"result": _wire_result(_failure(code, message)),
	})


## 处理玩家对地面掉落物的拾取请求并原子更新在线背包与地面实体。
## [param peer_id] 由传输层提供的不可伪造 peer 标识。
## [param intent] 仅包含 loot_id 的客户端意图。
## 返回拾取事件与类型化玩家增量，或身份、距离和容量错误；落盘沿用检查点周期。
## 设计：先预检地面实体，再提交背包，最后移除掉落；服务器主线程保证两阶段期间无并发插入。
func handle_peer_loot_pickup(peer_id: int, intent: Dictionary) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return _failure(&"loot.session_missing", "peer has no active authoritative session")
	return _handle_actor_loot_pickup(session.entity_id, intent)


func _handle_actor_loot_pickup(actor_id: String, intent: Dictionary) -> Dictionary:
	_clear_due_ground_items()
	var session: ServerSession = sessions.session_for_entity(actor_id)
	if session == null:
		return _failure(&"loot.session_missing", "actor has no active authoritative session")
	if autosave_service == null or player_panel_service == null:
		return _failure(&"loot.persistence_required", "loot pickup requires authoritative persistence")
	var loot_id := String(intent.get("loot_id", ""))
	if loot_id.is_empty() or intent.size() != 1:
		return _failure(&"loot.invalid_payload", "loot pickup intent must contain only loot_id")
	var current_instance := map_registry.instance_by_id(session.map_instance_id)
	if current_instance == null:
		return _failure(&"loot.map_unavailable", "session map instance is unavailable")
	var prepared := current_instance.prepare_loot_pickup(actor_id, loot_id)
	if not prepared.is_ok:
		return _failure(prepared.error_code, prepared.error_message)
	var current := autosave_service.player_for(actor_id)
	if current == null:
		return _failure(&"loot.state_missing", "authoritative player state is not registered")
	var transfer: Dictionary = {}
	var recipient := current
	if prepared.value.has("item"):
		var copied := PlayerTransaction.prepare(current, ["inventory"], player_panel_service.catalog, [], [prepared.value.item.instance_id])
		if not copied.is_ok: return _failure(copied.error_code, copied.error_message)
		recipient = copied.value
		var copied_item := PlayerTransaction._item(prepared.value.item, player_panel_service.catalog)
		if not copied_item.is_ok: return _failure(copied_item.error_code, copied_item.error_message)
		prepared.value.item = copied_item.value
		transfer = {"map_id": String(current_instance.definition.map_id), "loot_id": loot_id, "item": {}}
	var granted := player_panel_service.receive_loot(recipient, prepared.value)
	if not granted.is_ok:
		return _failure(granted.error_code, granted.error_message)
	# 所有校验已完成；此段不调用外部信号或等待，移除和入包共同提交。
	var committed := autosave_service.commit_player(
		actor_id, recipient, false, transfer, ["inventory"] as Array[String]
	)
	if not committed.is_ok: return _failure(committed.error_code, committed.error_message)
	var pickup := current_instance.commit_loot_pickup(actor_id, loot_id)
	assert(pickup.is_ok and committed.is_ok)
	var change := player_panel_service.pickup_change(current, granted.value)
	_queue_player_change(actor_id, change)
	return _success({"loot_event": pickup.value, "player_change": {}})


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
	if _command_router == null:
		_send_reliable(peer_id, {
			"type": "command_rejected",
			"result": _wire_result(_failure(
				&"command_router.unavailable", "command router is not initialized",
			)),
		})
		return
	_command_router.dispatch(peer_id, command_type, payload)


## 比较模拟前后的每件装备耐久，只把整点耐久下降作为界面变化发布。
## [param before] 使用前的装配快照。[param after] 使用后的装配快照。
## 返回是否至少有一件装备的耐久发生变化。
func _durability_changed(before: Dictionary, after: Dictionary) -> bool:
	for instance_id: String in after:
		if int(before.get(instance_id, {}).get("durability", -1)) != int(after[instance_id].get("durability", -1)):
			return true
	return false


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


## 处理可靠通道收到的组队、聊天或玩家交易命令。
func _on_transport_social_command(peer_id: int, command: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.SOCIAL_COMMAND, command)


## 处理 `_on_transport_map_transition_intent` 对应的信号回调。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _on_transport_map_transition_intent(peer_id: int, intent: Dictionary) -> void:
	dispatch_transport_command(peer_id, Protocol.MAP_TRANSITION_INTENT, intent)


## 发布 `emit_snapshot` 对应的模块状态。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _emit_snapshot() -> void:
	if _snapshot_publisher == null:
		push_error("Authoritative snapshot publisher is unavailable")
		return
	emitted_snapshot_count += 1
	var result := _snapshot_publisher.publish(
		server_tick, float(server_tick) / float(config.simulation_hz)
	)
	if not result.is_ok:
		push_error("Authoritative snapshot publish failed [%s]: %s" % [
			result.error_code, result.error_message,
		])


func _build_shared_snapshot(
	registered_instance: AuthoritativeMapInstance,
	requested_server_tick: int,
	server_time_seconds: float,
) -> Dictionary:
	return registered_instance.world_snapshot(requested_server_tick, server_time_seconds)


func _build_local_snapshot(peer_id: int) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return {}
	var session_map := map_registry.instance_by_id(session.map_instance_id)
	if session_map == null:
		return {}
	return session_map.local_snapshot_for_actor(server_tick, session.entity_id)


func _send_peer_world_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if not _network_started:
		return
	_transport_endpoint.send_world_snapshot(peer_id, snapshot)


func _send_peer_local_snapshot(peer_id: int, snapshot: Dictionary) -> void:
	if not _network_started:
		return
	_transport_endpoint.send_local_snapshot(peer_id, snapshot)


func _forward_peer_world_snapshot_generated(peer_id: int, snapshot: Dictionary) -> void:
	peer_world_snapshot_generated.emit(peer_id, snapshot)


func _forward_peer_local_snapshot_generated(peer_id: int, snapshot: Dictionary) -> void:
	peer_local_snapshot_generated.emit(peer_id, snapshot)


## 执行 `send_reliable` 对应的模块操作。
## [param peer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _send_reliable(peer_id: int, message: Dictionary) -> void:
	var session := sessions.session_for_peer(peer_id)
	var value: Dictionary = message.get("result", {}).get("value", {}) if message.get("result", {}).get("value") is Dictionary else {}
	if session != null:
		if message.get("type") == "player_panels" and not value.is_empty() \
			and _pending_player_changes.has(session.entity_id): value["player_change"] = {}
		var bundle: Dictionary = value.get("panel_bundle", value)
		if bundle.has("character") and bundle.has("inventory"):
			value.erase("player_change")
			var player := autosave_service.player_for(session.entity_id)
			if player != null: bundle["daily_activities"] = commerce_service.daily.snapshot(player)
			_pending_player_changes.erase(session.entity_id)
			bundle["sync_id"] = session.sync_id
			_published_player_revisions[session.sync_id] = int(bundle.transaction_revision)
		elif value.get("player_change") is Dictionary:
			var pending: PlayerChange = _pending_player_changes.get(session.entity_id, PlayerChange.new())
			_pending_player_changes.erase(session.entity_id)
			if pending.attributes_changed and pending.vehicle_stats.is_empty():
				pending.vehicle_stats = autosave_service.player_for(session.entity_id).calculate_vehicle_stats()
			var raw: Dictionary = pending.to_dictionary()
			raw["sync_id"] = session.sync_id
			raw["base_revision"] = _published_player_revisions.get(session.sync_id, 0)
			raw["transaction_revision"] = autosave_service.player_for(session.entity_id).revision
			value["player_change"] = raw
			_published_player_revisions[session.sync_id] = int(raw.transaction_revision)
			if not session.manufacturing_station.is_empty() and not value.has("manufacturing") \
				and (pending.inventory_revision >= 0 or not pending.skills.is_empty() or not pending.food.is_empty()):
				var player := autosave_service.player_for(session.entity_id)
				if _production_runtime != null: _production_runtime.capture(player)
				value.merge(manufacturing_service.build_bundle(player, {"station_id": session.manufacturing_station}))
		if message.get("type") == "player_panels" and not value.is_empty() and not bundle.has("character"):
			value["sync_id"] = session.sync_id
			value["transaction_revision"] = autosave_service.player_for(session.entity_id).revision
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
	_published_player_revisions.erase(session.sync_id)
	session.sync_id = Crypto.new().generate_random_bytes(16).hex_encode()
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
		"world_snapshot": session_map.world_snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		),
		"local_snapshot": session_map.local_snapshot_for_actor(server_tick, session.entity_id),
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
	if injected_repository == null:
		var background := (player_state_repository as FilePlayerStateRepository).enable_background_writes()
		if not background.is_ok: return _failure(background.error_code, background.error_message)
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
	display_name := "",
) -> DomainResult:
	if autosave_service == null:
		return DomainResultScript.ok()
	var vehicle_state := instance.vehicle_combat_state_for(entity.entity_id)
	var inventory_stacks := [
		_initial_inventory_stack(entity.entity_id, "spare_engine", "beginner_engine", 0, 0, 0, false, false, 900),
		_initial_inventory_stack(entity.entity_id, "training_shirt", "male_sleeveless_shirt", 1, 60, 0, false, true, 64),
	]
	var equipment_slots := [
		_initial_equipment_slot(entity.entity_id, "chassis", "recruit_tank", 0, 0, 0, 1020),
		_initial_equipment_slot(entity.entity_id, "primary_weapon", "recruit_energy_cannon", 1, 1, 1, 900),
		_initial_equipment_slot(entity.entity_id, "propulsion", "beginner_engine", 3, 3, 3, 900),
	]
	var initial_state: Dictionary = PlayerStateRecordScript.new().to_dictionary()
	initial_state.merge({
		"schema_version": PlayerStateRecord.CURRENT_SCHEMA_VERSION,
		"account_id": "account.%s" % entity.entity_id,
		"account_name": entity.entity_id,
		"account_status": "active",
		"character_id": entity.entity_id,
		"display_name": display_name if not String(display_name).is_empty() else entity.entity_id,
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
		"inventory_stacks": inventory_stacks,
		"equipment_slots": equipment_slots,
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
	}, true)
	var state_result = PlayerStateRecordScript.from_dictionary(initial_state)
	if not state_result.is_ok:
		return state_result
	var registered := autosave_service.register_player(state_result.value)
	if registered.is_ok and registered.value is Player:
		entity.sex = registered.value.sex
	return registered


func _initial_inventory_stack(
	entity_id: String,
	stack_key: String,
	definition_id: String,
	slot_index: int,
	x: int,
	y: int,
	locked: bool,
	bound: bool,
	durability: int,
) -> Dictionary:
	var stack: Dictionary = InventoryStackRecordScript.new().to_dictionary()
	stack.merge({
		"stack_id": "inventory.%s.%s" % [entity_id, stack_key],
		"item_definition_id": definition_id,
		"quantity": 1,
		"slot_index": slot_index,
		"container_id": "main",
		"position_px": [x, y],
		"footprint_px": [45, 45],
		"locked": locked,
		"bound": bound,
		"max_durability": durability,
		"durability": durability,
	}, true)
	return stack


func _initial_equipment_slot(
	entity_id: String,
	slot_id: String,
	definition_id: String,
	slot_location: int,
	equip_kind: int,
	upgrade_level: int,
	durability: int,
) -> Dictionary:
	var slot: Dictionary = EquipmentSlotRecordScript.new().to_dictionary()
	slot.merge({
		"owner_kind": "vehicle",
		"slot_id": slot_id,
		"slot_location": slot_location,
		"equip_kind": equip_kind,
		"item_instance_id": "equipment.%s.%s" % [entity_id, slot_id],
		"item_definition_id": definition_id,
		"max_durability": durability,
		"durability": durability,
		"upgrade_level": upgrade_level,
	}, true)
	return slot


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
func _capture_player_runtime(state: Variant, domains: Array[String] = []):
	var record: PlayerStateRecord = state if state is PlayerStateRecord else null
	var capture_runtime := record != null or domains.is_empty() or "location" in domains or "vehicle" in domains
	var capture_production := record != null or domains.is_empty() or "production" in domains
	if not capture_runtime and not capture_production:
		return DomainResultScript.ok(state)
	var entity_id: String = record.character_id if record != null else state.entity_id
	var session: ServerSession = sessions.session_for_entity(entity_id)
	if session == null:
		return DomainResultScript.failure(
			&"persistence.autosave_session_missing",
			"registered autosave character has no authoritative session",
		)
	var instance := map_registry.instance_by_id(session.map_instance_id)
	var entity: AuthoritativeEntity = instance.entities.get(entity_id) if instance != null else null
	if entity == null:
		return DomainResultScript.failure(
			&"persistence.autosave_entity_missing",
			"registered autosave character has no authoritative entity",
		)
	if record != null or "location" in domains or domains.is_empty():
		state.map_id = String(instance.definition.map_id)
		state.map_instance_id = instance.instance_id
		state.position = entity.position
		state.facing_direction = entity.facing_index
		state.checkpoint_id = "%s.autosave" % instance.definition.map_id
	var vehicle_state := instance.vehicle_combat_state_for(entity.entity_id)
	if (record != null or "vehicle" in domains or domains.is_empty()) \
		and instance.combat_module != null and instance.combat_module.actors.has(entity.entity_id):
		var condition: EquipmentConditionLoadout = instance.combat_module.actors[entity.entity_id].equipment_condition
		EquipmentConditionCapture.apply(state, condition.snapshot())
	if capture_runtime:
		if vehicle_state == null and instance.is_vehicle_combat_active(): return DomainResultScript.failure(
			&"persistence.autosave_vehicle_missing", "authoritative vehicle state is unavailable"
		)
		if vehicle_state != null:
			if record != null:
				record.vehicle_max_health = vehicle_state.max_health
				record.vehicle_health = vehicle_state.health
				record.reserve_energy_capacity = vehicle_state.reserve_energy_capacity
				record.reserve_energy = vehicle_state.reserve_energy
				record.working_energy_capacity = vehicle_state.working_energy_capacity
				record.working_energy = vehicle_state.working_energy
				record.output_power = vehicle_state.power_output
			else:
				state.vehicle.max_health = vehicle_state.max_health
				state.vehicle.health = vehicle_state.health
				state.vehicle.reserve_energy_capacity = vehicle_state.reserve_energy_capacity
				state.vehicle.reserve_energy = vehicle_state.reserve_energy
				state.vehicle.working_energy_capacity = vehicle_state.working_energy_capacity
				state.vehicle.working_energy = vehicle_state.working_energy
				state.vehicle.output_power = vehicle_state.power_output
	if capture_production and _production_runtime != null: _production_runtime.capture(state)
	return DomainResultScript.ok(state)


## 将已载入聚合恢复到会话拥有的权威实体和地图实例。
## [param session] 已建立但尚未向客户端发布的服务器会话。
## [param state] 仓储返回且已完成结构校验的玩家聚合。
## 返回该函数计算、查询或操作得到的结果。
## 设计：存档提供资源当前值和上次位置，地图定义仍决定可达性、容量与功率上限。
func _restore_persistent_player_state(
	session: ServerSession,
	state: Player,
) -> bool:
	var resumed_food := FoodStatus.new(state.food_status.to_dictionary())
	resumed_food.resume(int(Time.get_unix_time_from_system()))
	state.food_status = resumed_food
	state.vehicle.food_status = resumed_food
	state.production.pause("重新登录后生产已暂停，请返回原设施继续")
	var source := map_registry.instance_by_id(session.map_instance_id)
	var target: AuthoritativeMapInstance = source \
		if source != null and source.definition.map_id == StringName(state.map_id) else null
	if target == null:
		target = map_registry.instance_by_map_id(state.map_id)
	if target == null:
		var ensured := ensure_runtime_map(state.map_id)
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
	restored_entity.sex = state.sex
	restored_entity.action = &"idle"
	target.refresh_dynamic_entity_position(session.entity_id)
	if target.vehicle_combat_state_for(session.entity_id) != null:
		var combat_restore := target.restore_vehicle_combat_state(session.entity_id, state)
		if not combat_restore.ok:
			return false
	autosave_service.update_runtime_state(session.entity_id, state, ["location"] as Array[String])
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
	state: Player,
) -> Dictionary:
	if target == null or state == null or player_panel_service == null or _combat_catalog == null:
		return _failure(&"combat.player_loadout_unavailable", "player combat loadout dependencies are unavailable")
	target.player_resolver = Callable(autosave_service, "player_for")
	var loadout := _build_entity_combat_loadout(target, state)
	if not loadout.is_ok:
		if not target.is_vehicle_combat_active() and loadout.error_code == &"equipment.chassis_required_for_field":
			return _success(true)
		return _failure(loadout.error_code, loadout.error_message)
	return target.set_vehicle_combat_loadout(entity_id, loadout.value)


## 仅构造并校验候选战斗装配，不写地图运行时；用于持久化提交前预检。
## [param target] 用于确定是否要求完整战车装配的权威地图实例。
## [param state] 即将提交的玩家候选持久化状态。
## 返回已校验的装配定义，或依赖、角色还原和装备规则错误。
func _build_entity_combat_loadout(
	target: AuthoritativeMapInstance,
	state: Player,
) -> DomainResult:
	if target == null or state == null or player_panel_service == null or _combat_catalog == null:
		return DomainResult.failure(
			&"combat.player_loadout_unavailable",
			"player combat loadout dependencies are unavailable",
		)
	var player := state
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
	_clear_due_ground_items()
	if _persistence_coordinator == null:
		return
	var result := _persistence_coordinator.save_all()
	if not result.is_ok:
		push_error("Authoritative persistence flush failed [%s]: %s" % [
			result.error_code, result.error_message,
		])


## 保存退出事务成功后停止该角色运行，避免回执之后又产生未保存的战斗或生产变化。
## [param session] 即将结束的权威会话。[param committed] 刚刚写盘的完整玩家记录。
func _release_exited_player(session: ServerSession, committed: Player) -> void:
	if _production_runtime != null: _production_runtime.track(committed)
	_pending_vehicle_recoveries.erase(session.entity_id)
	_pending_player_changes.erase(session.entity_id)
	_remove_entity_from_registered_map(session.entity_id)
	if party_service != null:
		party_service.remove_expired_entity(session.entity_id)
	if trade_service != null:
		trade_service.remove_expired_entity(session.entity_id)
	if friend_service != null:
		friend_service.remove_expired_entity(session.entity_id)
	if chat_service != null:
		chat_service.remove_expired_entity(session.entity_id)
	if mail_service != null:
		mail_service.remove_expired_entity(session.entity_id)
	sessions.close(session.peer_id)
	_published_player_revisions.erase(session.sync_id)
	autosave_service.unregister_player(session.entity_id)


## 在服务器节点退出场景树前执行最后一次权威存档。
func _exit_tree() -> void:
	_close_pending_runtime_maps()
	_save_all_persistent_players()
	if chat_service != null:
		var flushed := chat_service.history.flush()
		if not flushed.is_ok: push_error("Private chat flush failed: " + flushed.error_message)


## 回收独立及进程内服务的低优先级文件线程，未进场景树的测试实例也必须完成收尾。
## [param what] 引擎生命周期通知。
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE: _close_pending_runtime_maps()
	if what == NOTIFICATION_PREDELETE and chat_service != null:
		var closed := chat_service.history.close()
		if not closed.is_ok: push_error("Private chat close failed: " + closed.error_message)
	if what == NOTIFICATION_PREDELETE and player_state_repository != null:
		var closed := player_state_repository.close()
		if not closed.is_ok: push_error("Authoritative persistence close failed: " + closed.error_message)


func _close_pending_runtime_maps() -> void:
	for loading: Dictionary in _pending_runtime_maps.values(): loading.thread.wait_to_finish()
	_pending_runtime_maps.clear()


## 读取全量荣耀地图索引，但不构建导航图；地图实例在首次进入时创建。
## 返回该函数计算、查询或操作得到的结果。
func _load_runtime_map_index() -> Dictionary:
	_runtime_definition_paths_by_map_id.clear()
	_runtime_map_ids_by_legacy_world.clear()
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
		if not _runtime_map_ids_by_legacy_world.has(world_id):
			_runtime_map_ids_by_legacy_world[world_id] = {}
		var world_index: Dictionary = _runtime_map_ids_by_legacy_world[world_id]
		if world_index.has(legacy_code):
			return _failure(&"runtime_map_index_duplicate", "runtime legacy map key is duplicated")
		world_index[legacy_code] = map_id
	return _success(_runtime_definition_paths_by_map_id.size())


## 确保受控索引中的地图存在权威实例；未知客户端 ID 无法注入文件路径。
## [param map_id] 调用方传入的 `map_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func ensure_runtime_map(map_id: String) -> Dictionary:
	var existing := map_registry.instance_by_map_id(map_id) if map_registry != null else null
	if existing != null:
		return _success(existing)
	var prepared: AuthoritativeMapInstance
	if _pending_runtime_maps.has(map_id) and not _pending_runtime_maps[map_id].thread.is_alive():
		var loaded: Dictionary = _pending_runtime_maps[map_id].thread.wait_to_finish()
		_pending_runtime_maps.erase(map_id)
		if not loaded.ok: return loaded
		prepared = loaded.value
		map_registry.navigation_cache.acquire(prepared.definition.navigation_data_path, prepared.definition.navigation_grid_size, prepared.definition.navigation_cell_size, prepared.navigation)
	var dormant := map_registry.dormant_instance(map_id)
	if dormant != null:
		if prepared != null:
			dormant.navigation = prepared.navigation
			dormant._spawn_point_ids = prepared._spawn_point_ids
			dormant._navigation_point_grid = prepared._navigation_point_grid
		var resumed := dormant.resume_runtime(server_tick)
		if not resumed.ok:
			return resumed
		return map_registry.register_instance(dormant)
	var definition_path := String(_runtime_definition_paths_by_map_id.get(map_id, ""))
	if definition_path.is_empty():
		return _failure(&"runtime_map_unknown", "runtime map is absent from the controlled index")
	var loaded_instance: AuthoritativeMapInstance = prepared if prepared != null else MapInstanceScript.new()
	_configure_map_instance(loaded_instance)
	if prepared == null:
		var loaded := loaded_instance.load_runtime(definition_path, _combat_catalog, _mining_catalog, config.simulation_hz)
		if not loaded.ok: return loaded
	loaded_instance.combat_module.rewards = reward_service
	var restored_ground := _restore_ground_items(loaded_instance)
	if not restored_ground.is_ok: return _failure(restored_ground.error_code, restored_ground.error_message)
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
	var target_map_id := _target_map_id_for_transition(transition, source_world_id)
	if target_map_id.is_empty():
		return null
	var ensured := ensure_runtime_map(target_map_id)
	return ensured.value if ensured.ok else null


func _target_map_id_for_transition(transition: MapTransition, source_world_id: StringName) -> String:
	if not transition.destination_map_id.is_empty():
		return String(transition.destination_map_id)
	if transition.destination_legacy_code.is_empty():
		return ""
	var target_world := transition.destination_world_id
	if target_world.is_empty():
		target_world = source_world_id
	var world_index: Dictionary = _runtime_map_ids_by_legacy_world.get(String(target_world), {})
	return String(world_index.get(transition.destination_legacy_code.strip_edges().to_lower(), ""))


## 返回地图迁移事务使用的当前在线玩家，不创建第二份状态所有者。
func _player_for_transition(entity_id: String) -> Player:
	return autosave_service.player_for(entity_id) if autosave_service != null else null


## 提交地图迁移前采集的玩家候选，并同步生产运行时的已提交状态。
func _commit_transition_player(entity_id: String, candidate: Player) -> DomainResult:
	if autosave_service == null:
		return DomainResultScript.ok(candidate)
	var committed := autosave_service.commit_player(
		entity_id, candidate, false, {}, ["location", "production"] as Array[String]
	)
	if committed.is_ok and _production_runtime != null:
		_production_runtime.track(committed.value)
	return committed


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
		var map_id := String(definition.map_id)
		if not _runtime_definition_paths_by_map_id.has(map_id):
			_runtime_definition_paths_by_map_id[map_id] = definition_path
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
	instance.navigation_cache = map_registry.navigation_cache
	instance.dynamic_blocking_enabled = config.dynamic_blocking_enabled
	instance.dynamic_blocking_radius = config.dynamic_blocking_radius
	if party_service != null:
		instance.set_loot_recipient_resolver(Callable(party_service, "loot_recipients_for"))


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
func _valid_llm_player_id(actor_id: String) -> bool:
	if not actor_id.begins_with("llm.") or actor_id.length() > 64:
		return false
	var suffix := actor_id.substr(4)
	if suffix.is_empty():
		return false
	for index: int in range(suffix.length()):
		var code := suffix.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) \
				or (code >= 97 and code <= 122) or code == 45 or code == 46 or code == 95):
			return false
	return true


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
		_food_runtime = AuthoritativeFoodRuntime.new(autosave_service,
			_capture_player_runtime, _apply_food_runtime, _publish_food_status)
	_food_runtime.advance(sessions.all_sessions(), int(Time.get_unix_time_from_system()))


## 向在线角色发布已提交的食品和玩家投影。
## [param _peer_id] 当前连接；变化在本刻发布入口统一发送。
## [param state] 同一事务玩家状态。
## [param attributes] 战斗属性是否到期。[param expired] 是否移除了食品效果。
func _publish_food_status(_peer_id: int, state: Player, attributes: bool, expired: bool) -> void:
	var change := PlayerChange.new()
	change.character_health = state.health
	if expired: change.food = state.food_status.to_dictionary()
	change.attributes_changed = attributes
	_queue_player_change(state.entity_id, change)


## 将实际提交后的生产进度和物品变化发布给当前连接。
## [param peer_id] 在线连接身份。
## [param state] 仓储已经接受的完整记录。
## [param operation] 已完成轮次或暂停结果。
## [param change] 同一生产事务的玩家组件变化。
func _publish_production(peer_id: int, state: Player, operation: Dictionary, change: PlayerChange) -> void:
	_queue_player_change(state.entity_id, change)
	if peer_id == 0:
		_queue_llm_runtime_event(state.entity_id, &"production_result", operation)
		return
	var bundle := {"player_change": {}}
	var session := sessions.session_for_peer(peer_id)
	if session != null and not session.manufacturing_station.is_empty():
		bundle.merge(manufacturing_service.build_bundle(state, operation))
	_send_reliable(peer_id, {"type": "player_panels",
		"result": _wire_result(_success(bundle))})


## 报告生产写入或状态错误，不把候选产物发送成成功结果。
## [param peer_id] 出错连接。
## [param code] 领域或仓储错误码。
## [param message] 已去重的人类可读提示。
func _publish_production_failure(entity_id: String, code: StringName, message: String) -> void:
	var session := sessions.session_for_entity(entity_id)
	if session != null and session.has_active_peer():
		_send_reliable(session.peer_id, {"type": "player_panels", "result": _wire_result(_failure(code, message))})
	else:
		_queue_llm_runtime_event(entity_id, &"production_result", {"ok": false, "error_code": String(code), "message": message})


## 将食品事务资源同步回当前地图，热更新武器时保留射击冷却和维修状态。
## [param entity_id] 会话拥有的角色。
## [param state] 已提交的权威状态。
## [param refresh_attributes] 增益变化时才重建战斗配置，补给只同步资源。
func _apply_food_runtime(entity_id: String, state: Player, refresh_attributes: bool = true) -> void:
	if refresh_attributes: _refresh_achievement_combat(entity_id, state)
	var target := map_registry.instance_by_id(state.map_instance_id)
	if target == null:
		return
	var combat_state := target.vehicle_combat_state_for(entity_id)
	if combat_state != null:
		combat_state.health = clampi(state.vehicle.health, 0, combat_state.max_health)
		combat_state.reserve_energy = clampf(state.vehicle.reserve_energy, 0.0, combat_state.reserve_energy_capacity)
		combat_state.working_energy = clampf(state.vehicle.working_energy, 0.0, combat_state.working_energy_capacity)
