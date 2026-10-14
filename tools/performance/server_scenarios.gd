extends SceneTree

const PEER := 100
var _server: AuthoritativeServer
var _scenario := "standing"
var _actor := ""
var _sequence := 0
var _origin := Vector2.ZERO
var _fire_target: MonsterLifecycle
var _mine: MineSource
var _accepted := 0
var _distance := 0.0


## 基准只使用启动器提供的隔离资料目录，拒绝误用日常玩家环境。
func _initialize() -> void:
	if OS.get_environment("STARHOME_BENCHMARK_ISOLATED") != "1":
		printerr("Use tools/performance/run_baseline.py to isolate player data")
		quit(2)
		return
	call_deferred("_run")


## 固定D04、单角色和目录种群，预热5秒后测量20秒逻辑时间。
func _run() -> void:
	_scenario = OS.get_environment("STARHOME_PERFORMANCE_SCENARIO")
	if _scenario not in ["standing", "moving", "firing", "mining", "replenishment"]:
		quit(2)
		return
	seed(20261014)
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.default_spawn = Vector2(2412, 2400)
	config.player_state_store_path = "user://benchmark-player.json"
	_server = AuthoritativeServer.new()
	if not _server.initialize(config).ok or not _server.open_session(PEER,
		{"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok:
		printerr("Cannot initialize benchmark")
		quit(1)
		return
	_actor = _server.sessions.session_for_peer(PEER).entity_id
	_origin = _server.map_instance.entities[_actor].position
	if not _prepare():
		_server.free()
		quit(1)
		return
	for tick in 100: _step(tick)
	_accepted = 0
	_distance = 0
	var population := _server.map_instance.combat_module.monsters.size()
	PerformanceTelemetry.configure(true, OS.get_environment("STARHOME_PERFORMANCE_OUTPUT"), {
		"scenario": _scenario, "map": "d04_field_zone", "players": 1, "initial_monsters": population,
		"seed": 20261014, "warmup_ticks": 100, "sample_ticks": 400, "simulation_hz": 20,
		"git_revision": OS.get_environment("STARHOME_BENCHMARK_REVISION"),
		"worktree_dirty": OS.get_environment("STARHOME_BENCHMARK_DIRTY") == "1",
		"engine": Engine.get_version_info().string, "os": OS.get_name(),
		"scope": "headless authoritative CPU costs; not rendered FPS",
		"fixture": "starter gear; health refilled each tick; firing target health and energy refilled"})
	for tick in 400:
		_step(tick + 100)
		if tick % 20 == 0: await process_frame
	PerformanceTelemetry.set_gauge(&"accepted_actions", _accepted)
	PerformanceTelemetry.set_gauge(&"movement_distance", _distance)
	PerformanceTelemetry.set_gauge(&"final_monsters", _server.map_instance.combat_module.monsters.size())
	if _mine != null: PerformanceTelemetry.set_gauge(&"mined_units", 50 - _mine.remaining)
	var final_population := _server.map_instance.combat_module.monsters.size()
	_server._save_all_persistent_players()
	_server.free()
	var saved := PerformanceTelemetry.close()
	var exercised := _scenario in ["standing", "replenishment"] or _accepted > 0
	if _scenario == "moving": exercised = exercised and _distance > 0
	if _scenario == "mining": exercised = _mine.remaining < 50
	if _scenario == "replenishment": exercised = final_population > population - 120
	print("PERFORMANCE_SCENARIO %s accepted=%d distance=%.1f saved=%s" % [_scenario, _accepted, _distance, saved.is_ok])
	quit(0 if saved.is_ok and exercised else 1)


## 仅在测试夹具中安装采掘臂或放置连续命中的目标，不改正式平衡配置。
## 返回本场景是否具备实际可运行的动作。
func _prepare() -> bool:
	var map := _server.map_instance
	if _scenario == "firing":
		_fire_target = map.combat_module.monsters.values()[0]
		_fire_target.position = map.navigation.closest_reachable_position(_origin, _origin + Vector2(100, 0))
		_fire_target.home_position = _fire_target.position
		map.combat_module._monster_spatial_grid.update(_fire_target.monster_id, _fire_target.position)
	if _scenario != "mining": return true
	var state := _server.autosave_service.state_for(_actor)
	var grant := _server.player_panel_service.grant_loot(state,
		{"loot_id": "benchmark.arm", "item_definition_id": "glory_equipment_collector_ac947ee094", "quantity": 1})
	if not grant.is_ok: return false
	_server.autosave_service.commit_player_state(_actor, grant.value.candidate)
	state = _server.autosave_service.state_for(_actor)
	var arm_id := ""
	for item: InventoryStackRecord in state.inventory_stacks:
		if item.item_definition_id == "glory_equipment_collector_ac947ee094": arm_id = item.stack_id
	var equip := _server.handle_peer_player_panel_command(PEER, {"type": "equip_vehicle_item", "instance_id": arm_id,
		"location": 1, "inventory_revision": state.inventory_revision, "loadout_revision": state.vehicle_loadout_revision})
	if not equip.ok: return false
	_mine = map.mining_module.sources.values()[0]
	var entity: AuthoritativeEntity = map.entities[_actor]
	entity.position = _mine.position + Vector2(40, 0)
	entity.target_position = entity.position
	map.combat_module.update_actor_position(_actor, entity.position)
	_sequence += 1
	var result := _server.handle_peer_use_ability(PEER, {"map_instance_id": map.instance_id,
		"ability_id": "mining.collect", "aim_world_position": {"x": _mine.position.x, "y": _mine.position.y}, "input_sequence": _sequence})
	return result.ok


## 驱动实际权威命令和逻辑帧，拒绝次数不会伪装成成功动作。
## [param tick] 包含预热阶段的基准步号。
func _step(tick: int) -> void:
	var map := _server.map_instance
	var entity: AuthoritativeEntity = map.entities[_actor]
	var vehicle := map.vehicle_combat_state_for(_actor)
	vehicle.health = vehicle.max_health
	if _scenario == "moving" and tick % 40 == 0:
		var target: Vector2 = map.navigation.closest_reachable_position(entity.position,
			_origin + Vector2.RIGHT.rotated(float(tick) / 40.0 * PI / 2) * 400)
		_sequence += 1
		var result := _server.handle_peer_move(PEER, {"map_instance_id": map.instance_id,
			"requested_world_point": {"x": target.x, "y": target.y}, "input_sequence": _sequence})
		if result.ok: _accepted += 1
	elif _scenario == "firing" and tick % 4 == 0:
		_fire_target.health = 1000000
		vehicle.working_energy = vehicle.working_energy_capacity
		_sequence += 1
		var result := _server.handle_peer_use_ability(PEER, {"map_instance_id": map.instance_id,
			"ability_id": "energy_cannon.primary", "aim_world_position": {"x": _fire_target.position.x, "y": _fire_target.position.y}, "input_sequence": _sequence})
		if result.ok: _accepted += 1
	elif _scenario == "replenishment" and tick == 100:
		var removed := 0
		for id: String in map.combat_module.monsters.keys():
			if map.combat_module.monsters[id].population_kind == &"ordinary" and removed < 120:
				map.combat_module.monsters.erase(id)
				map.combat_module._monster_spatial_grid.remove(id)
				removed += 1
		map._next_monster_replenishment_tick = map.combat_module.current_tick + 1
	var before := entity.position
	_server.advance_simulation(0.05, 1000 + tick * 50)
	_distance += before.distance_to(entity.position)
