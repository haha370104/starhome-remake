extends "res://tests/ui/runtime/player_changes_runtime_test.gd"


func _run() -> void:
	Engine.max_fps = 60
	if not await _test_concurrent_actions(): return
	print("MINING_SELF_REPAIR_RUNTIME checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _test_concurrent_actions() -> bool:
	if not await _boot("res://data/maps/glory_nft_bl_d04.json"): return false
	server.set_process(false)
	server.map_instance.combat_module.monsters.clear()
	_grant("glory_equipment_collector_ac947ee094", "concurrent.collector")
	await _sync()
	_check((await _send({"type": "equip_vehicle_item", "instance_id": "concurrent.collector", "location": 1})).get("ok", false), "装配采掘臂")
	var map := server.map_instance
	var source: MineSource = map.mining_module.sources.values()[0]
	var entity: AuthoritativeEntity = map.entities[player.entity_id]
	entity.position = source.position + Vector2(40, 0)
	entity.target_position = entity.position
	map.combat_module.update_actor_position(player.entity_id, entity.position)
	hall.local_player_controller.set_position(entity.position)
	var actor: Dictionary = map.combat_module.actors[player.entity_id]
	var vehicle: VehicleCombatState = actor.vehicle_state
	vehicle.health = vehicle.max_health - 11
	var quantity := player.inventory.count_definition(source.item_definition_id)
	var remaining := source.remaining
	var experience := player.skills.current_experience("repair")
	var arm := player.vehicle.loadout.at(1)
	var durability := arm.durability
	await _sync()
	_reset_observations()
	hall.combat.request_mining(source.position)
	await process_frame
	await process_frame
	server.advance_simulation(1.0)
	await _publish_world()
	_check(map.mining_module.action_snapshot(player.entity_id).active, "开始采矿后保持活动")
	var action: Dictionary = map.mining_module._actions[player.entity_id].duplicate(true)
	await _press_repair()
	_check(map.mining_module.action_snapshot(player.entity_id).active, "点击真实自维修按钮不停止采矿")
	_check(map.mining_module._actions.get(player.entity_id, {}) == action, "原矿源、预约时刻和周期不变")
	_check(bool(actor.self_repair.active), "自维修同时成功启动")
	if not map.mining_module.action_snapshot(player.entity_id).active:
		await _close()
		return true
	_check_concurrent("自维修开始")
	await _press_repair()
	_check(map.mining_module._actions.get(player.entity_id, {}) == action, "重复开启自维修不重置采矿")
	server.advance_simulation(float(int(action.next_cycle_tick) - server.server_tick) / float(config.simulation_hz))
	await _publish_world()
	_check(player.inventory.count_definition(source.item_definition_id) == quantity + 1 and source.remaining == remaining - 1, "采矿在原第三秒产出，不因维修重新计时")
	_check(vehicle.health == vehicle.max_health - 11, "维修保留自身三秒计时")
	_check_concurrent("第一个采矿周期")
	server.advance_simulation(float(int(actor.self_repair.next_cycle_tick) - server.server_tick) / float(config.simulation_hz))
	await _publish_world()
	_check(vehicle.health == vehicle.max_health - 6, "维修按原周期实际回血5点")
	_check(player.skills.current_experience("repair") == experience + 5, "并行维修按实际回血增加经验")
	_check_concurrent("第一个维修周期")
	server.advance_simulation(float(int(map.mining_module._actions[player.entity_id].next_cycle_tick) - server.server_tick) / float(config.simulation_hz))
	await _publish_world()
	_check(player.inventory.count_definition(source.item_definition_id) == quantity + 2 and source.remaining == remaining - 2, "并行第二次采矿正常结算")
	_check(arm.durability == durability - 1 and arm.usage.progress.get("mining", -1) == 0, "并行采矿按两次扣一点耐久")
	_check(panels.current_player.vehicle.loadout.at(1).durability == arm.durability, "客户端同步采矿耐久")
	server.advance_simulation(4.0)
	await _publish_world()
	_check(vehicle.health == vehicle.max_health and not bool(actor.self_repair.active), "维修补满血后自动停止")
	_check(player.inventory.count_definition(source.item_definition_id) == quantity + 3 and source.remaining == remaining - 3, "维修停止不影响后续采矿")
	_check(player.skills.current_experience("repair") == experience + 11, "并行维修累计经验等于实际回血")
	_check(panels.current_player.skills.current_experience("repair") == experience + 11, "客户端同步并行维修经验")
	var continuing: Dictionary = map.mining_module._actions[player.entity_id].duplicate(true)
	await _press_repair()
	_check(map.mining_module._actions.get(player.entity_id, {}) == continuing, "满血拒绝维修仍保留原采矿预约")
	_check(hall.world_view.mining_visual_controller._active, "客户端采矿表现仍保持活动")
	_consistent("并行采矿与维修")
	_check(full_updates == 0 and equipment_updates == 0, "并行动作不触发全量玩家或外观刷新")
	_save_and_compare()
	vehicle.health -= 5
	await _press_repair()
	_check_concurrent("移动前")
	var move := network.request_move(entity.position + Vector2(40, 0))
	_check(not move.is_empty(), "通过正式传输提交移动")
	await process_frame
	await process_frame
	await _publish_world()
	_check(not map.mining_module.action_snapshot(player.entity_id).active and not bool(actor.self_repair.active), "移动仍按原规则打断采矿和维修")
	await _close()
	return true


func _press_repair() -> void:
	hall.hud.top_menu.action_buttons.self_repair.pressed.emit()
	await process_frame
	await process_frame
	await _publish_world()


func _publish_world() -> void:
	if network.remote_interpolator.last_server_tick >= server.server_tick:
		server.advance_simulation(1.0 / float(config.simulation_hz))
	server._emit_snapshot()
	await process_frame
	await process_frame


func _check_concurrent(label: String) -> void:
	var bundle: Dictionary = server.snapshot_bundle_for_peer(server.sessions.session_for_entity(player.entity_id).peer_id)
	var snapshot: Dictionary = bundle.local_snapshot
	_check(bool(snapshot.local_mining.active) and bool(snapshot.local_vehicle.self_repair_active), label + "：权威快照中两者同时活动")
	_check(hall.world_view.mining_visual_controller._active and hall.world_view.self_repair_visual_controller._active, label + "：客户端两种表现同时活动")
