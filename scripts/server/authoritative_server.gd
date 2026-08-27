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
const TransportEndpointScript := preload("res://scripts/network/transport/network_transport_endpoint.gd")

signal snapshot_generated(snapshot: Dictionary)
signal command_rejected(peer_id: int, code: StringName)

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


## Initializes node dependencies after the node enters the scene tree.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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


## Initializes the subsystem and returns its startup result.
## [param requested_config] Configuration data that controls the operation.
## [param injected_map_instances] Optional fully loaded fixture/production instances admitted as one registry.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func initialize(
	requested_config: DedicatedServerConfig,
	injected_map_instances: Array[AuthoritativeMapInstance] = [],
) -> Dictionary:
	config = requested_config
	var errors := config.validation_errors()
	if not errors.is_empty():
		return _failure(&"invalid_server_config", "; ".join(errors))
	map_registry = MapRegistryScript.new()
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
	_ticks_per_snapshot = config.simulation_hz / config.snapshot_hz
	return _success(map_instance.definition.map_id)


## Performs the `start_network` operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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


## Performs the `stop_network` operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func stop_network() -> void:
	if not _network_started:
		return
	_transport_endpoint.close()
	_network_started = false


## Installs and binds the process-wide endpoint at the protocol's stable root NodePath.
## Design: Server and client executables have different scene roots, so RPCs live on a fixed sibling node.
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
	_transport_endpoint.peer_disconnected.connect(_on_peer_disconnected)


## Advances fixed-step simulation state.
## [param delta] Elapsed time in seconds for this update.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _physics_process(delta: float) -> void:
	advance_simulation(delta, Time.get_ticks_msec())


## Advances the managed state using the supplied update.
## [param elapsed_seconds] Elapsed time in seconds for this update.
## [param now_msec] Input value consumed by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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
		if server_tick % _ticks_per_snapshot == 0:
			_emit_snapshot()
	var cleanup_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	for entity_id in sessions.cleanup_expired(cleanup_time):
		_remove_entity_from_registered_map(entity_id)


## Processes the requested protocol or gameplay operation.
## [param peer_id] Stable identifier of the target value.
## [param request] Serialized input received at the subsystem boundary.
## [param now_msec] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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
	var session_result := sessions.create(peer_id, entity_id, current_time)
	if not session_result.ok:
		map_instance.remove_entity(entity_id)
		return session_result
	session_result.value.map_instance_id = map_instance.instance_id
	return _session_response(session_result.value, false)


## Processes the requested protocol or gameplay operation.
## [param peer_id] Stable identifier of the target value.
## [param now_msec] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func disconnect_session(peer_id: int, now_msec := -1) -> Dictionary:
	var current_time := now_msec if now_msec >= 0 else Time.get_ticks_msec()
	return sessions.mark_disconnected(peer_id, current_time)


## Processes the requested protocol or gameplay operation.
## [param peer_id] Stable identifier of the target value.
## [param intent] Serialized input received at the subsystem boundary.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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


## Validates and atomically applies one map transition requested by [param peer_id].
## [param peer_id] Authenticated ENet peer that owns the transitioning entity.
## [param raw_intent] Untrusted `MapTransitionIntent` dictionary from the shared protocol boundary.
## Returns a success containing `map_joined`, target-only snapshot, and acknowledged transition sequence.
## Design: Source removal happens only after destination spawn succeeds, so failure retains the old map state.
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
		"snapshot": destination_instance.snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		),
		"transition_sequence": intent.input_sequence,
	})


## Builds the current map-scoped world snapshot visible to [param peer_id].
## [param peer_id] Active authenticated peer whose session determines the interest map.
## Returns an empty dictionary for unknown/unavailable sessions, otherwise only that map's entities.
## Design: This is the single interest-filter seam used by tests and network publication.
func snapshot_for_peer(peer_id: int) -> Dictionary:
	var session: ServerSession = sessions.session_for_peer(peer_id)
	if session == null:
		return {}
	var session_map := map_registry.instance_by_id(session.map_instance_id)
	if session_map == null:
		return {}
	return session_map.snapshot(
		server_tick, float(server_tick) / float(config.simulation_hz)
	)


## Handles the signal callback for `on_peer_disconnected`.
## [param peer_id] Stable identifier of the target value.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _on_peer_disconnected(peer_id: int) -> void:
	disconnect_session(peer_id)


## Handles a transport-authenticated session [param request] from [param peer_id].
## [param peer_id] ENet sender identity supplied by MultiplayerAPI.
## [param request] Versioned open/resume session payload.
func _on_transport_session_request(peer_id: int, request: Dictionary) -> void:
	var result := open_session(peer_id, request)
	_send_reliable(peer_id, {
		"type": "session_opened" if result.ok else "command_rejected",
		"result": _wire_result(result),
	})


## Handles a transport-authenticated movement [param intent] from [param peer_id].
## [param peer_id] ENet sender identity supplied by MultiplayerAPI.
## [param intent] Untrusted movement payload for authority validation.
func _on_transport_move_intent(peer_id: int, intent: Dictionary) -> void:
	var result := handle_peer_move(peer_id, intent)
	if not result.ok:
		_send_reliable(peer_id, {"type": "command_rejected", "result": _wire_result(result)})


## Handles an authenticated map-transition [param intent] from [param peer_id].
## [param peer_id] ENet sender identity supplied by MultiplayerAPI.
## [param intent] Untrusted shared `MapTransitionIntent` payload.
## Design: Both success and rejection are reliable control messages correlated by transition sequence.
func _on_transport_map_transition_intent(peer_id: int, intent: Dictionary) -> void:
	var result := handle_peer_map_transition(peer_id, intent)
	if result.ok:
		_send_reliable(peer_id, {"type": "map_joined", "result": _wire_result(result)})
		return
	var wire_result := _wire_result(result)
	wire_result["value"] = {
		"command_type": String(Protocol.MAP_TRANSITION_INTENT),
		"transition_sequence": int(intent.get("input_sequence", -1)),
	}
	_send_reliable(peer_id, {"type": "command_rejected", "result": wire_result})


## Publishes the current state to subscribed consumers.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _emit_snapshot() -> void:
	emitted_snapshot_count += 1
	for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
		var snapshot := registered_instance.snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		)
		snapshot_generated.emit(snapshot)
	if _network_started:
		for session: ServerSession in sessions.active_sessions():
			var session_snapshot := snapshot_for_peer(session.peer_id)
			if not session_snapshot.is_empty():
				_transport_endpoint.send_world_snapshot(session.peer_id, session_snapshot)


## Processes the requested protocol or gameplay operation.
## [param peer_id] Stable identifier of the target value.
## [param message] Serialized input received at the subsystem boundary.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _send_reliable(peer_id: int, message: Dictionary) -> void:
	if _network_started and peer_id > 0:
		_transport_endpoint.send_server_message(peer_id, message)


## Performs the `session_response` operation.
## [param session] Input value consumed by the operation.
## [param resumed] Whether the corresponding behavior is enabled.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
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
		"snapshot": session_map.snapshot(
			server_tick, float(server_tick) / float(config.simulation_hz)
		),
	})


## Performs the `wire_result` operation.
## [param result] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _wire_result(result: Dictionary) -> Dictionary:
	var wire := result.duplicate(true)
	wire["code"] = String(result.get("code", &"unknown"))
	# Internal RefCounted instances are never serialized over the wire.
	if wire.get("value") is RefCounted:
		wire.erase("value")
	return wire


## Performs the `finish_smoke_test` operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _finish_smoke_test() -> void:
	print("STARHOME_SERVER_SMOKE_OK")
	stop_network()
	get_tree().quit(0)


## Loads every server-admitted map listed by the configured world catalog.
## Returns a success containing the primary map instance, or an atomic startup failure.
## Design: The catalog is deployment configuration; clients can never request arbitrary resource paths.
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
		var registration := map_registry.register_instance(loaded_instance)
		if not registration.ok:
			return registration
		if definition_path == config.map_config_path:
			map_instance = loaded_instance
	if map_instance == null:
		return _failure(&"primary_map_not_registered", "configured primary map was not loaded")
	return _success(map_instance)


## Applies validated server collision settings to one [param instance].
## [param instance] Loaded or injectable authoritative map instance being admitted.
## Design: Injected fixtures and file-backed production maps receive identical authority policy.
func _configure_map_instance(instance: AuthoritativeMapInstance) -> void:
	instance.dynamic_blocking_enabled = config.dynamic_blocking_enabled
	instance.dynamic_blocking_radius = config.dynamic_blocking_radius


## Copies persistent authority state from [param source] into a newly spawned [param destination].
## [param source] Entity still owned by the source map before atomic commit.
## [param destination] Target-map entity that already passed spawn admission.
## Design: Map transfer resets motion but preserves input ordering, facing, speed, and monotonic revision.
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


## Repositions [param entity] for a transition that remains inside [param destination_instance].
## [param entity] Existing entity reused by a same-instance portal.
## [param destination_instance] Authoritative instance that owns both portal endpoints.
## [param spawn_position] Server-resolved and walkable destination foot point.
## Design: Same-map portals avoid duplicate-ID spawning while retaining the same atomic state semantics.
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


## Removes [param entity_id] from whichever registered map currently owns it.
## [param entity_id] Session entity removed after reconnect grace expiration.
## Returns true when a registered map contained and removed the entity.
## Design: Cleanup remains correct after map transfers even though the expired session index is gone.
func _remove_entity_from_registered_map(entity_id: String) -> bool:
	for registered_instance: AuthoritativeMapInstance in map_registry.all_instances():
		if registered_instance.remove_entity(entity_id):
			return true
	return false


## Performs the `success` operation.
## [param value] New value requested by the caller.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## Performs the `failure` operation.
## [param code] Stable identifier of the target value.
## [param message] Serialized input received at the subsystem boundary.
## Returns Structured result data produced by the operation.
## Design: Runs within the authoritative server boundary; clients must not override the resulting state.
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
