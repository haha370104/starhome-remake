extends SceneTree

const MainScene := preload("res://scenes/main_hall.tscn")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")
const MAP_CATALOG_PATH := "res://data/maps/glory_map_directory_v1.json"
const MOVEMENT_HALF_DISTANCE := 120.0
const MOVEMENT_RETRY_SECONDS := 0.25
const MAPS := {
	"c03": {
		"id": "glory_nft_bl_c03",
		"path": "res://data/maps/glory_nft_bl_c03.json",
		"spawn": Vector2(2412, 2400),
	},
	"d04": {
		"id": "glory_nft_bl_d04",
		"path": "res://data/maps/glory_nft_bl_d04.json",
		"spawn": Vector2(2412, 2400),
	},
	"e04": {
		"id": "glory_nft_bl_e04",
		"path": "res://assets/glory/map_definitions/glory_nft_bl_e04.json",
		"spawn": Vector2(2400, 2400),
	},
}

var _hall: Node
var _server: Node
var _map_instance
var _combat_module
var _map_key := "d04"
var _scenario := "standing"
var _state := "boot"
var _state_elapsed := 0.0
var _run_elapsed := 0.0
var _next_move_at := 2.0
var _movement_origin := Vector2.ZERO
var _movement_targets := PackedVector2Array()
var _movement_target_index := 0
var _movement_requests := 0
var _max_vehicle_displacement := 0.0
var _last_event_id := 0
var _started_events := 0
var _resolved_events := 0
var _forced_monsters := 0


func _initialize() -> void:
	_map_key = OS.get_environment("STARHOME_FOREGROUND_MAP").strip_edges().to_lower()
	if not MAPS.has(_map_key):
		_map_key = "d04"
	_scenario = OS.get_environment("STARHOME_FOREGROUND_SCENARIO").strip_edges().to_lower()
	if _scenario.is_empty():
		_scenario = "standing"
	call_deferred("_start")


func _start() -> void:
	var map_data: Dictionary = MAPS[_map_key]
	_hall = MainScene.instantiate()
	_hall.multiplayer_offline_debug_enabled = true
	_hall.multiplayer_connect_automatically = false
	_hall.multiplayer_map_instance_id = "%s.instance.1" % map_data.id
	root.add_child(_hall)
	_state = "connect"


func _process(delta: float) -> bool:
	_state_elapsed += delta
	match _state:
		"connect":
			_connect_when_ready()
		"wait_map":
			_wait_for_map()
		"running":
			_run_scenario(delta)
		"failed":
			if _state_elapsed > 1.0:
				quit(2)
	if _state in ["connect", "wait_map"] and _state_elapsed > 45.0:
		_fail("foreground scene did not reach the requested map")
	return false


func _connect_when_ready() -> void:
	if _hall == null or _hall.multiplayer_presenter == null:
		return
	var session = _hall.multiplayer_presenter.session
	if session == null or session.network_adapter == null:
		return
	var config := ServerConfigScript.new()
	var map_data: Dictionary = MAPS[_map_key]
	config.map_config_path = map_data.path
	config.map_catalog_path = MAP_CATALOG_PATH
	config.default_spawn = map_data.spawn
	config.network_enabled = false
	config.persistence_enabled = false
	config.dynamic_blocking_enabled = true
	if not session.network_adapter.configure_in_process_server(config):
		_fail("failed to configure in-process server")
		return
	if session.connect_to_server("in-process", 0) != OK:
		_fail("failed to connect in-process server")
		return
	_state = "wait_map"
	_state_elapsed = 0.0


func _wait_for_map() -> void:
	if _hall.active_world_controller == null or _hall.multiplayer_presenter.session == null:
		return
	var session = _hall.multiplayer_presenter.session
	var map_data: Dictionary = MAPS[_map_key]
	if String(session.current_map_id) != map_data.id:
		return
	if _hall.active_world_controller.definition == null \
			or String(_hall.active_world_controller.definition.map_id) != map_data.id:
		return
	var endpoint = session.network_adapter.get("_transport_endpoint")
	_server = endpoint.get("authoritative_server") if endpoint != null else null
	if _server == null or _server.map_registry == null:
		return
	_map_instance = _server.map_registry.instance_by_id(session.current_map_instance_id)
	_combat_module = _map_instance.combat_module if _map_instance != null else null
	if _combat_module == null:
		return
	_enable_test_vehicle_movement()
	if _state == "failed":
		return
	_force_ranged_monsters()
	_configure_movement_targets()
	PerformanceTelemetry.annotate({
		"driver": "tools/performance/foreground_combat_hitch_driver.gd",
		"foreground_scene": true,
		"actual_map_id": map_data.id,
		"actual_map_key": _map_key,
		"foreground_scenario": _scenario,
		"forced_ranged_monsters": _forced_monsters,
		"actual_monster_count": _combat_module.monsters.size(),
		"actual_player_count": 1,
		"movement_target_count": _movement_targets.size(),
	})
	_state = "running"
	_state_elapsed = 0.0
	_run_elapsed = 0.0
	print("FOREGROUND_READY map=%s monsters=%d ranged=%d scenario=%s move_targets=%d" % [
		map_data.id, _combat_module.monsters.size(), _forced_monsters, _scenario, _movement_targets.size(),
	])


func _enable_test_vehicle_movement() -> void:
	var session = _hall.multiplayer_presenter.session
	var actor_id := String(session.local_entity_id)
	var loadout := {
		"assembly": _map_instance._combat_assembly.duplicate(true),
		"weapons": _map_instance._combat_weapons.duplicate(true),
	}
	var result: Dictionary = _map_instance.set_vehicle_combat_loadout(actor_id, loadout)
	if not bool(result.get("ok", false)):
		_fail("failed to enable test vehicle movement: %s" % String(result.get("error_message", "unknown error")))
		return
	_hall.local_player_controller.set_movement_enabled(true)
	var entity = _map_instance.entities.get(actor_id)
	print("FOREGROUND_MOVEMENT_READY speed=%.1f" % float(entity.movement_speed if entity != null else 0.0))


func _force_ranged_monsters() -> void:
	var session = _hall.multiplayer_presenter.session
	var actor_id := String(session.local_entity_id)
	var actor: Dictionary = _combat_module.actors.get(actor_id, {})
	if actor.is_empty():
		_fail("local combat actor is not ready")
		return
	var vehicle = actor.get("vehicle_state")
	vehicle.max_health *= 100
	vehicle.health = vehicle.max_health
	var center: Vector2 = actor.position
	_movement_origin = center
	var requested_count := int(OS.get_environment("STARHOME_FOREGROUND_RANGED_COUNT"))
	if requested_count <= 0:
		requested_count = 16
	var placed := 0
	for monster_id: String in _combat_module.monsters:
		if placed >= requested_count:
			break
		var monster = _combat_module.monsters[monster_id]
		if not monster.attack_mode.is_projectile():
			continue
		var angle := float(placed) * TAU / float(requested_count)
		var requested := center + Vector2.RIGHT.rotated(angle) * (110.0 + float(placed % 4) * 18.0)
		var position: Vector2 = _map_instance.navigation.closest_reachable_position(center, requested)
		if not position.is_finite():
			continue
		monster.position = position
		monster.home_position = position
		monster.target_actor_id = actor_id
		monster.attack_ready_tick = _combat_module.current_tick
		_combat_module._sync_monster_spatial_index(monster_id, position)
		placed += 1
	_forced_monsters = placed


func _configure_movement_targets() -> void:
	_movement_targets = PackedVector2Array()
	for offset: Vector2 in [Vector2(-MOVEMENT_HALF_DISTANCE, 0.0), Vector2(MOVEMENT_HALF_DISTANCE, 0.0)]:
		var target: Vector2 = _map_instance.navigation.closest_reachable_position(
			_movement_origin, _movement_origin + offset
		)
		if not target.is_finite() or target.distance_squared_to(_movement_origin) < 1024.0:
			continue
		_movement_targets.append(target)
	_movement_target_index = 0


func _run_scenario(delta: float) -> void:
	_run_elapsed += delta
	if _scenario == "moving":
		_request_next_movement_target()
	_record_events()


func _request_next_movement_target() -> void:
	if _movement_targets.size() < 2 or _run_elapsed < _next_move_at:
		return
	if _hall.local_player_controller.has_active_route():
		return
	var target := _movement_targets[_movement_target_index]
	var result: Dictionary = _hall.local_player_controller.request_move(target)
	if bool(result.get("ok", false)):
		_movement_target_index = 1 - _movement_target_index
		_movement_requests += 1
		_next_move_at = _run_elapsed + MOVEMENT_RETRY_SECONDS
		print("FOREGROUND_MOVE request=%d target=(%.1f,%.1f)" % [
			_movement_requests, target.x, target.y,
		])
	else:
		_next_move_at = _run_elapsed + 1.0
		print("FOREGROUND_MOVE_REJECT code=%s message=%s" % [
			String(result.get("code", "unknown")), String(result.get("message", "")),
		])


func _record_events() -> void:
	for event: Dictionary in _combat_module.combat_events:
		var event_id := int(event.get("event_id", 0))
		if event_id <= _last_event_id:
			continue
		_last_event_id = event_id
		if event.get("event_type") == &"monster_attack_started":
			_started_events += 1
		elif event.get("event_type") == &"monster_attack_resolved":
			_resolved_events += 1
			if _resolved_events == 1 or _resolved_events % 20 == 0:
				print("FOREGROUND_HIT elapsed=%.3f started=%d resolved=%d" % [
					_run_elapsed, _started_events, _resolved_events,
				])
	PerformanceTelemetry.set_gauge(&"foreground_monster_attack_started", _started_events)
	PerformanceTelemetry.set_gauge(&"foreground_monster_attack_resolved", _resolved_events)
	PerformanceTelemetry.set_gauge(&"foreground_vehicle_move_requests", _movement_requests)
	if _hall.local_player_controller != null:
		_max_vehicle_displacement = maxf(
			_max_vehicle_displacement,
			_hall.local_player_controller.position().distance_to(_movement_origin),
		)
	PerformanceTelemetry.set_gauge(&"foreground_vehicle_max_displacement", _max_vehicle_displacement)


func _fail(message: String) -> void:
	if _state == "failed":
		return
	_state = "failed"
	_state_elapsed = 0.0
	printerr("FOREGROUND_FAIL ", message)
