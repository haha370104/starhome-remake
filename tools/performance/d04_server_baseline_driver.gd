extends SceneTree

const AuthoritativeServerScript := preload("res://scripts/server/authoritative_server.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")

const MAP_PATH := "res://data/maps/glory_nft_bl_d04.json"
const MAP_CATALOG_PATH := "res://data/maps/glory_map_directory_v1.json"
const PLAYER_COUNT := 4
const VEHICLE_MOVE_THRESHOLD := 240.0
const VEHICLE_ROUTE_RADIUS := 720.0
const COMBAT_ROUTE_RADIUS := 120.0
const RANGED_COMBAT_MONSTER_COUNT := 32

var _server: AuthoritativeServer
var _moving_players: Array[Dictionary] = []
var _previous_vehicle_positions: Dictionary = {}
var _previous_monster_positions: Dictionary = {}
var _moved_vehicle_ids: Dictionary = {}
var _moved_monster_ids: Dictionary = {}
var _vehicle_distance := 0.0
var _monster_distance := 0.0
var _movement_started_at_usec := 0
var _movement_sample_started := false
var _last_metadata_second := -1
var _movement_timer: Timer


func _initialize() -> void:
	var config := ServerConfigScript.new()
	config.map_config_path = MAP_PATH
	config.map_catalog_path = MAP_CATALOG_PATH
	config.default_spawn = Vector2(2412.0, 2400.0)
	config.network_enabled = false
	config.persistence_enabled = false
	var server := AuthoritativeServerScript.new()
	var initialized := server.initialize(config)
	if not bool(initialized.get("ok", false)):
		printerr("D04 baseline server initialization failed: %s" % initialized.get("message", ""))
		quit(1)
		return
	_server = server
	root.add_child(_server)
	for index in range(PLAYER_COUNT):
		var opened := _server.open_session(
			100 + index,
			{
				"protocol_version": Protocol.PROTOCOL_VERSION,
				"content_version": Protocol.PUBLIC_CONTENT_VERSION,
			},
		)
		if not bool(opened.get("ok", false)):
			printerr("D04 baseline player %d failed: %s" % [index + 1, opened.get("message", "")])
			quit(1)
			return
	var monster_count := _server.map_instance.combat_module.monsters.size()
	if OS.get_environment("STARHOME_PERFORMANCE_SCENARIO") == "moving_combat":
		_prepare_ranged_combat()
	call_deferred("_annotate_benchmark", monster_count)
	if OS.get_environment("STARHOME_PERFORMANCE_SCENARIO") in ["moving", "moving_combat"]:
		_start_moving_scenario()


func _annotate_benchmark(monster_count: int) -> void:
	PerformanceTelemetry.annotate({
		"actual_map_id": String(_server.map_instance.definition.map_id),
		"actual_player_count": PLAYER_COUNT,
		"actual_monster_count": monster_count,
		"driver": "tools/performance/d04_server_baseline_driver.gd",
	})


func _start_moving_scenario() -> void:
	if not _server.map_instance.is_vehicle_combat_active():
		printerr("D04 moving scenario requires a vehicle-combat map")
		quit(1)
		return
	for index in range(PLAYER_COUNT):
		var peer_id := 100 + index
		var session = _server.sessions.session_for_peer(peer_id)
		var entity = _server.map_instance.entities.get(session.entity_id) if session != null else null
		if entity == null or _server.map_instance.vehicle_combat_state_for(session.entity_id) == null:
			printerr("D04 moving scenario player %d has no authoritative vehicle" % (index + 1))
			quit(1)
			return
		_moving_players.append({
			"peer_id": peer_id,
			"entity_id": session.entity_id,
			"origin": entity.position,
			"waypoint_index": index * 2,
			"input_sequence": 0,
		})
	_movement_started_at_usec = Time.get_ticks_usec()
	_movement_timer = Timer.new()
	_movement_timer.wait_time = 0.5
	_movement_timer.autostart = true
	_movement_timer.timeout.connect(_update_moving_scenario)
	root.add_child(_movement_timer)


func _prepare_ranged_combat() -> void:
	var combat_module = _server.map_instance.combat_module
	var center := Vector2(2412.0, 2400.0)
	var target_id := String(_server.sessions.session_for_peer(100).entity_id)
	var placed := 0
	for monster_id: String in combat_module.monsters:
		var monster: MonsterLifecycle = combat_module.monsters[monster_id]
		if not monster.attack_mode.is_projectile() or placed >= RANGED_COMBAT_MONSTER_COUNT:
			continue
		var angle := float(placed) * TAU / float(RANGED_COMBAT_MONSTER_COUNT)
		var requested_position := center + Vector2.RIGHT.rotated(angle) * (80.0 + float(placed % 4) * 24.0)
		monster.position = _server.map_instance.navigation.closest_reachable_position(center, requested_position)
		monster.home_position = monster.position
		monster.target_actor_id = target_id
		combat_module._sync_monster_spatial_index(monster_id, monster.position)
		placed += 1
	PerformanceTelemetry.annotate({"forced_ranged_monsters": placed})


func _update_moving_scenario() -> void:
	var elapsed_usec := Time.get_ticks_usec() - _movement_started_at_usec
	var warmup_usec := roundi(float(OS.get_environment("STARHOME_PERFORMANCE_WARMUP_SECONDS")) * 1000000.0)
	var sample_usec := roundi(float(OS.get_environment("STARHOME_PERFORMANCE_SAMPLE_SECONDS")) * 1000000.0)
	if elapsed_usec >= warmup_usec and not _movement_sample_started:
		_movement_sample_started = true
		_reset_movement_sample()
	_drive_vehicles()
	if not _movement_sample_started:
		return
	_record_movement()
	var elapsed_second := floori(float(elapsed_usec - warmup_usec) / 1000000.0)
	if elapsed_second != _last_metadata_second:
		_last_metadata_second = elapsed_second
		_annotate_movement()
	if elapsed_usec >= warmup_usec + sample_usec and _movement_timer != null:
		_movement_timer.stop()


func _drive_vehicles() -> void:
	for player_index in range(_moving_players.size()):
		var player: Dictionary = _moving_players[player_index]
		var entity_id := String(player["entity_id"])
		var entity = _server.map_instance.entities.get(entity_id)
		if entity == null:
			continue
		var move_threshold := 48.0 if OS.get_environment("STARHOME_PERFORMANCE_SCENARIO") == "moving_combat" else VEHICLE_MOVE_THRESHOLD
		if entity.action == &"walking" \
				and entity.target_position.distance_to(entity.position) > move_threshold:
			continue
		var current_position: Vector2 = entity.position
		for candidate in 8:
			var waypoint_index := posmod(int(player["waypoint_index"]) + candidate, 8)
			var angle := float(waypoint_index) * TAU / 8.0
			var route_radius := COMBAT_ROUTE_RADIUS if OS.get_environment("STARHOME_PERFORMANCE_SCENARIO") == "moving_combat" else VEHICLE_ROUTE_RADIUS
			var requested_target: Vector2 = player["origin"] + Vector2.RIGHT.rotated(angle) * route_radius
			var target: Vector2 = _server.map_instance.navigation.closest_reachable_position(
				current_position, requested_target,
			)
			if target.distance_to(current_position) < move_threshold:
				continue
			var sequence := int(player["input_sequence"]) + 1
			var result := _server.handle_peer_move(int(player["peer_id"]), {
				"map_instance_id": _server.map_instance.instance_id,
				"requested_world_point": {"x": target.x, "y": target.y},
				"input_sequence": sequence,
			})
			if not bool(result.get("ok", false)):
				player["input_sequence"] = sequence
				continue
			var value: Dictionary = result.get("value", {})
			var accepted_target: Vector2 = value.get("authoritative_target", Vector2.INF)
			if accepted_target.distance_to(current_position) < move_threshold:
				player["input_sequence"] = sequence
				continue
			player["input_sequence"] = sequence
			player["waypoint_index"] = (waypoint_index + 1) % 8
			_moving_players[player_index] = player
			break


func _reset_movement_sample() -> void:
	_previous_vehicle_positions.clear()
	_previous_monster_positions.clear()
	_moved_vehicle_ids.clear()
	_moved_monster_ids.clear()
	_vehicle_distance = 0.0
	_monster_distance = 0.0
	for player: Dictionary in _moving_players:
		var entity_id := String(player["entity_id"])
		var entity = _server.map_instance.entities.get(entity_id)
		if entity != null:
			_previous_vehicle_positions[entity_id] = entity.position
	for monster_id: String in _server.map_instance.combat_module.monsters:
		var monster: MonsterLifecycle = _server.map_instance.combat_module.monsters[monster_id]
		_previous_monster_positions[monster_id] = monster.position


func _record_movement() -> void:
	for player: Dictionary in _moving_players:
		var entity_id := String(player["entity_id"])
		var entity = _server.map_instance.entities.get(entity_id)
		if entity == null:
			continue
		var position: Vector2 = entity.position
		if _previous_vehicle_positions.has(entity_id):
			var distance: float = _previous_vehicle_positions[entity_id].distance_to(position)
			_vehicle_distance += distance
			if distance > 1.0:
				_moved_vehicle_ids[entity_id] = true
		_previous_vehicle_positions[entity_id] = position
	for monster_id: String in _server.map_instance.combat_module.monsters:
		var monster: MonsterLifecycle = _server.map_instance.combat_module.monsters[monster_id]
		var position: Vector2 = monster.position
		if _previous_monster_positions.has(monster_id):
			var distance: float = _previous_monster_positions[monster_id].distance_to(position)
			_monster_distance += distance
			if distance > 1.0:
				_moved_monster_ids[monster_id] = true
		_previous_monster_positions[monster_id] = position


func _annotate_movement() -> void:
	var moving_monsters := 0
	var ranged_started := 0
	var ranged_resolved := 0
	for event: Dictionary in _server.map_instance.combat_module.combat_events:
		if event.get("event_type") == &"monster_attack_started": ranged_started += 1
		elif event.get("event_type") == &"monster_attack_resolved": ranged_resolved += 1
	for monster: MonsterLifecycle in _server.map_instance.combat_module.monsters.values():
		if monster.action == &"move":
			moving_monsters += 1
	PerformanceTelemetry.annotate({
		"movement_driver": "authoritative_vehicle_intents_and_monster_ai",
		"vehicle_moved_count": _moved_vehicle_ids.size(),
		"vehicle_distance_world_units": roundi(_vehicle_distance),
		"monster_moved_count": _moved_monster_ids.size(),
		"monster_distance_world_units": roundi(_monster_distance),
		"monsters_currently_moving": moving_monsters,
		"ranged_attack_events_recent": {"started": ranged_started, "resolved": ranged_resolved},
	})
