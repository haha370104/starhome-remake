extends SceneTree

const AuthoritativeServerScript := preload("res://scripts/server/authoritative_server.gd")
const ServerConfigScript := preload("res://scripts/server/server_config.gd")
const Protocol := preload("res://scripts/network/contracts/network_protocol.gd")
const RuntimeContentBootstrapScript := preload("res://scripts/content/runtime_content_bootstrap.gd")
const CombatVisualPresenterScript := preload(
	"res://scripts/client/presentation/combat/combat_visual_presenter.gd"
)
const MonsterWorldControllerScript := preload(
	"res://scripts/client/presentation/combat/monster_world_controller.gd"
)

const MAP_PATH := "res://data/maps/glory_nft_bl_d04.json"
const MAP_CATALOG_PATH := "res://data/maps/glory_map_directory_v1.json"
const MANIFEST_PATH := "res://assets/equipment_world/combat_visual_manifest.json"
const PLAYER_COUNT := 4
const PEER_ID := 100
const COMBAT_ROUTE_RADIUS := 120.0
const RANGED_COMBAT_MONSTER_COUNT := 32

var _server: AuthoritativeServer
var _world := Node2D.new()
var _camera := Camera2D.new()
var _local_player: CombatVisualPresenter
var _players: Array[CombatVisualPresenter] = []
var _monster_controller: MonsterWorldController
var _manifest: Dictionary = {}
var _scenario := "standing"
var _presentation_snapshot_count := 0
var _synthetic_event_id := 1000000
var _spawn_generation := 0
var _last_update_usec := 0
var _elapsed_seconds := 0.0
var _driver_timer: Timer
var _moving_players: Array[Dictionary] = []
var _pending_world_snapshot: Dictionary = {}
var _pending_local_snapshot: Dictionary = {}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_scenario = OS.get_environment("STARHOME_PERFORMANCE_SCENARIO")
	if _scenario.is_empty():
		_scenario = "standing"
	var content_result := RuntimeContentBootstrapScript.mount_default()
	if not bool(content_result.get("ok", false)):
		printerr("D04 client presentation content initialization failed: ", content_result.get("message", ""))
		quit(1)
		return
	var manifest_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest_value is Dictionary:
		printerr("D04 client presentation manifest is invalid")
		quit(1)
		return
	_manifest = manifest_value
	root.size = Vector2i(1280, 720)
	_setup_world()
	_setup_server()
	_last_update_usec = Time.get_ticks_usec()
	_driver_timer = Timer.new()
	_driver_timer.name = "D04ClientBenchmarkDriverTimer"
	_driver_timer.wait_time = 0.05
	_driver_timer.timeout.connect(_on_driver_timer_timeout)
	root.add_child(_driver_timer)
	_driver_timer.start()


func _setup_world() -> void:
	_world.name = "D04ClientBenchmarkWorld"
	root.add_child(_world)
	var background := Polygon2D.new()
	background.name = "BenchmarkBackground"
	background.polygon = PackedVector2Array([
		Vector2(-4000, -4000), Vector2(8000, -4000), Vector2(8000, 8000), Vector2(-4000, 8000),
	])
	background.color = Color("1a2028")
	background.z_index = -1000
	_world.add_child(background)
	var positions := [
		Vector2(2412, 2400),
		Vector2(2470, 2400),
		Vector2(2412, 2460),
		Vector2(2470, 2460),
	]
	for index in range(PLAYER_COUNT):
		var player := CombatVisualPresenterScript.new()
		player.name = "BenchmarkPlayer_%d" % index
		_world.add_child(player)
		if player.configure(_manifest) != OK or player.present_actor(&"starter_combat_vehicle") != OK:
			printerr("D04 client player presentation failed: ", index)
			quit(1)
			return
		player.position = positions[index]
		_players.append(player)
	_local_player = _players[0]
	if _scenario == "offscreen":
		_local_player.position = Vector2(-2400, -2400)
	_camera.name = "BenchmarkCamera"
	_camera.position = _local_player.position
	_camera.position_smoothing_enabled = false
	_world.add_child(_camera)
	_camera.make_current()
	_monster_controller = MonsterWorldControllerScript.new()
	_monster_controller.name = "BenchmarkMonsterWorldController"
	root.add_child(_monster_controller)
	if _monster_controller.configure(_world, _manifest, _local_player) != OK:
		printerr("D04 client monster controller failed to configure")
		quit(1)
		return


func _setup_server() -> void:
	var config := ServerConfigScript.new()
	config.map_config_path = MAP_PATH
	config.map_catalog_path = MAP_CATALOG_PATH
	config.default_spawn = Vector2(2412, 2400)
	config.network_enabled = false
	config.persistence_enabled = false
	_server = AuthoritativeServerScript.new()
	_server.name = "D04ClientBenchmarkServer"
	_server.peer_world_snapshot_generated.connect(_on_peer_world_snapshot_generated)
	_server.peer_local_snapshot_generated.connect(_on_peer_local_snapshot_generated)
	var initialized := _server.initialize(config)
	if not bool(initialized.get("ok", false)):
		printerr("D04 client benchmark server initialization failed: ", initialized.get("message", ""))
		quit(1)
		return
	root.add_child(_server)
	_server.set_physics_process(false)
	for index in range(PLAYER_COUNT):
		var opened := _server.open_session(
			PEER_ID + index,
			{
				"protocol_version": Protocol.PROTOCOL_VERSION,
				"content_version": Protocol.PUBLIC_CONTENT_VERSION,
			},
		)
		if not bool(opened.get("ok", false)):
			printerr("D04 client benchmark player %d failed: %s" % [index + 1, opened.get("message", "")])
			quit(1)
			return
	if _scenario == "moving_combat":
		_prepare_ranged_combat()
		_prepare_authoritative_movement()
	PerformanceTelemetry.annotate({
		"driver": "tools/performance/d04_client_presentation_driver.gd",
		"actual_map_id": String(_server.map_instance.definition.map_id),
		"actual_player_count": PLAYER_COUNT,
		"actual_monster_count": _server.map_instance.combat_module.monsters.size(),
		"presentation_target_peer_id": PEER_ID,
		"movement_driver": "authoritative_position_fixture",
	})


func _prepare_ranged_combat() -> void:
	var combat_module = _server.map_instance.combat_module
	var center := Vector2(2412.0, 2400.0)
	var target_id := String(_server.sessions.session_for_peer(PEER_ID).entity_id)
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


func _prepare_authoritative_movement() -> void:
	for index in PLAYER_COUNT:
		var peer_id := PEER_ID + index
		var session = _server.sessions.session_for_peer(peer_id)
		var entity = _server.map_instance.entities.get(session.entity_id) if session != null else null
		if entity == null:
			continue
		_moving_players.append({
			"entity_id": session.entity_id,
			"origin": entity.position,
		})


func _on_peer_world_snapshot_generated(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id != PEER_ID or _monster_controller == null:
		return
	_pending_world_snapshot = snapshot
	_apply_pending_snapshot()


func _on_peer_local_snapshot_generated(peer_id: int, snapshot: Dictionary) -> void:
	if peer_id != PEER_ID or _monster_controller == null:
		return
	_pending_local_snapshot = snapshot
	_apply_pending_snapshot()


func _apply_pending_snapshot() -> void:
	if _pending_world_snapshot.is_empty() or _pending_local_snapshot.is_empty():
		return
	if _pending_world_snapshot.get("map_instance_id") != _pending_local_snapshot.get("map_instance_id") \
		or _pending_world_snapshot.get("server_tick") != _pending_local_snapshot.get("server_tick"):
		return
	var world: Dictionary = _pending_world_snapshot
	var combat_world: Dictionary = world["combat_world"]
	var combat_snapshot: Dictionary = combat_world.duplicate(true)
	combat_snapshot["server_tick"] = int(world["server_tick"])
	combat_snapshot["server_time_seconds"] = float(world["server_time_seconds"])
	combat_snapshot.merge(_pending_local_snapshot)
	combat_snapshot = _decorate_snapshot(combat_snapshot)
	_monster_controller.apply_snapshot(combat_snapshot)
	_pending_world_snapshot = {}
	_pending_local_snapshot = {}
	_presentation_snapshot_count += 1
	PerformanceTelemetry.increment(&"client_benchmark_snapshots_applied")


func _decorate_snapshot(combat_snapshot: Dictionary) -> Dictionary:
	if _scenario in ["spawning", "replacement"]:
		var monsters: Array = combat_snapshot.get("monsters", []).duplicate(true)
		if _scenario == "spawning" and _presentation_snapshot_count > 0 and _presentation_snapshot_count % 20 == 0:
			_spawn_generation += 1
		elif _scenario == "replacement":
			_spawn_generation += 1
		for index in mini(10, monsters.size()):
			var monster: Dictionary = monsters[index]
			monster["entity_id"] = "benchmark.spawn.%d.%02d" % [_spawn_generation, index]
			monsters[index] = monster
		combat_snapshot["monsters"] = monsters
	if _scenario == "firing" and _presentation_snapshot_count % 2 == 0:
		var monsters: Array = combat_snapshot.get("monsters", [])
		if not monsters.is_empty():
			var target: Dictionary = monsters[0]
			var point: Array = target.get("position", [0, 0])
			_synthetic_event_id += 1
			combat_snapshot["recent_events"] = [{
				"event_id": _synthetic_event_id,
				"event_type": "energy_cannon_hit",
				"target_entity_id": String(target.get("entity_id", "")),
				"damage": 123,
				"impact_position": point,
			}]
	return combat_snapshot


func _advance_driver() -> void:
	var now_usec := Time.get_ticks_usec()
	var delta := float(now_usec - _last_update_usec) / 1000000.0 if _last_update_usec > 0 else 0.0
	_last_update_usec = now_usec
	_elapsed_seconds += delta
	if _scenario == "moving_combat":
		_drive_authoritative_movement()
	if _server != null and delta > 0.0:
		_server.advance_simulation(delta, Time.get_ticks_msec())
	for index in _players.size():
		var player := _players[index]
		if _scenario == "moving_combat":
			var entity = _server.map_instance.entities.get(_moving_players[0]["entity_id"])
			if entity != null and index == 0:
				player.position = entity.position
			else:
				player.position = _local_player.position + Vector2.RIGHT.rotated(float(index) * TAU / PLAYER_COUNT) * 90.0
		elif _scenario == "moving":
			var radius := 260.0
			var offset := Vector2(cos(_elapsed_seconds * 0.55), sin(_elapsed_seconds * 0.55)) * radius
			player.position = _local_player.position + offset if index > 0 else Vector2(2412, 2400) + offset
		player.advance(delta)
	if _scenario in ["moving", "moving_combat"]:
		_camera.position = _local_player.position


func _drive_authoritative_movement() -> void:
	for index in range(_moving_players.size()):
		var player: Dictionary = _moving_players[index]
		var entity = _server.map_instance.entities.get(String(player["entity_id"]))
		if entity == null:
			continue
		var origin: Vector2 = player["origin"]
		var angle := _elapsed_seconds * 0.55 + float(index) * TAU / PLAYER_COUNT
		var position := origin + Vector2.RIGHT.rotated(angle) * COMBAT_ROUTE_RADIUS
		entity.position = position
		entity.target_position = position
		entity.path = PackedVector2Array([position])
		entity.path_index = 1
		entity.action = &"idle"
		_server.map_instance.combat_module.update_actor_position(String(player["entity_id"]), position)


func _on_driver_timer_timeout() -> void:
	_advance_driver()
	if _scenario == "moving_combat" and _server != null:
		var ranged_started := 0
		var ranged_resolved := 0
		for event: Dictionary in _server.map_instance.combat_module.combat_events:
			if event.get("event_type") == &"monster_attack_started": ranged_started += 1
			elif event.get("event_type") == &"monster_attack_resolved": ranged_resolved += 1
		PerformanceTelemetry.annotate({
			"ranged_attack_events_recent": {"started": ranged_started, "resolved": ranged_resolved},
		})
