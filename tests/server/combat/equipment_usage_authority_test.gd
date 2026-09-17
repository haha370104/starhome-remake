extends SceneTree

const PEER := 75
var checks := 0
var failures: Array[String] = []


## 等待挂载原版地图数据后启动隔离测试。
func _initialize() -> void:
	call_deferred("_run")


## 验证实际开火拒绝不磨损、损坏属性刷新、速修恢复及重启。
func _run() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.map_config_path = "res://data/maps/d04_field_zone.json"
	config.player_state_store_path = "res://.godot/equipment-usage-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_check(server.initialize(config).ok, "server")
	_check(server.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "session")
	var session := server.sessions.session_for_peer(PEER)
	var map := server.map_registry.instance_by_id(session.map_instance_id)
	map.combat_module.monsters.clear()
	var current := server.autosave_service.state_for(session.entity_id)
	var gun_id := ""
	var engine_id := ""
	for slot: EquipmentSlotRecord in current.equipment_slots:
		if slot.slot_location == 1:
			gun_id = slot.item_instance_id
			slot.durability = 1
			slot.usage.progress["shot"] = 19.0
		elif slot.slot_location == 3:
			engine_id = slot.item_instance_id
			slot.usage.progress["movement"] = 59.95
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "items")
	var player: Player = server.player_panel_service.restore_player(current).value
	_check(player.inventory.add_reward(catalog.create("maintenance_quickrepairbox2", {"instance_id": "box"}).value).is_ok, "repair box")
	current = PlayerStateMapper.new(catalog).to_record(player).value
	_check(server.autosave_service.commit_player_state(session.entity_id, current).is_ok, "fixture commit")
	var loadout := server._build_entity_combat_loadout(map, current)
	_check(loadout.is_ok and map.refresh_achievement_loadout(session.entity_id, loadout.value).is_ok, "fixture loadout")
	var module := map.combat_module
	var actor: Dictionary = module.actors[session.entity_id]
	var condition: EquipmentConditionLoadout = actor.equipment_condition
	var origin: Vector2 = actor.position
	var intent := UseAbilityIntent.new(map.instance_id, "energy_cannon.primary", origin + Vector2(100, 0), 1).to_dictionary()
	var energy: VehicleCombatState = actor.vehicle_state
	energy.working_energy = 0
	_check(not module.handle_weapon_attack(session.entity_id, intent).is_ok, "no energy rejected")
	_check(condition.snapshot()[gun_id].durability == 1, "rejected shot no wear")
	energy.working_energy = energy.working_energy_capacity
	intent.input_sequence = 2
	_check(module.handle_weapon_attack(session.entity_id, intent).is_ok, "accepted shot")
	_check(condition.snapshot()[gun_id].durability == 0 and condition.needs_recalculation, "accepted shot breaks weapon")
	var after_energy := energy.working_energy
	intent.input_sequence = 3
	_check(not module.handle_weapon_attack(session.entity_id, intent).is_ok and energy.working_energy == after_energy, "broken weapon no extra shot or energy")
	server._settle_equipment_conditions(map)
	_check(not actor.weapons.has("energy_cannon.primary"), "broken weapon removed from real abilities")
	var cooldown: Dictionary = actor.cooldown_ready_ticks.duplicate()
	var repaired := server.handle_peer_player_panel_command(PEER, {"type": "quick_repair_equipment", "instance_id": gun_id,
		"material_id": "box", "inventory_revision": current.inventory_revision})
	_check(repaired.ok, "field group repair")
	_check(actor.weapons.has("energy_cannon.primary"), "repair restores real ability")
	_check(actor.cooldown_ready_ticks == cooldown and energy.working_energy == after_energy, "repair preserves cooldown and energy")
	module.update_actor_position(session.entity_id, origin + Vector2(1, 0))
	module.advance_ticks(1, false)
	condition = actor.equipment_condition
	var engine: Dictionary = condition.snapshot()[engine_id]
	_check(engine.durability == engine.max_durability - 1, "actual movement wears engine at threshold")
	var captured: PlayerStateRecord = server._capture_persistent_player_state(server.autosave_service.state_for(session.entity_id)).value
	for slot: EquipmentSlotRecord in captured.equipment_slots:
		if slot.item_instance_id == engine_id: _check(slot.durability == engine.durability, "live wear reaches persistent record")
	server._save_all_persistent_players()
	server.free()
	var restarted := AuthoritativeServer.new()
	_check(restarted.initialize(config).ok, "restart")
	_check(restarted.open_session(PEER, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000).ok, "rejoin")
	for slot: EquipmentSlotRecord in restarted.autosave_service.state_for(session.entity_id).equipment_slots:
		if slot.item_instance_id == engine_id: _check(slot.durability == engine.durability, "wear survives restart")
	restarted.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	print("Equipment usage authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总断言结果。
## [param condition] 实际结果。
## [param label] 失败描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
