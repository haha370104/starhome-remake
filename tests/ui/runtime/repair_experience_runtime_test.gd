extends "res://tests/ui/runtime/player_changes_runtime_test.gd"


func _run() -> void:
	Engine.max_fps = 60
	if not await _test_repair_experience(): return
	print("REPAIR_EXPERIENCE_RUNTIME checks=%d failures=%d" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


func _test_repair_experience() -> bool:
	if not await _boot("res://data/maps/glory_nft_bl_d04.json"): return false
	server.set_process(false)
	var combat := server.map_instance.combat_module
	combat.monsters.clear()
	var actor: Dictionary = combat.actors[player.entity_id]
	var vehicle: VehicleCombatState = actor.vehicle_state
	actor.self_repair_base_strength = 12
	actor.self_repair_bonus_strength = 0
	vehicle.health = vehicle.max_health - 19
	var initial_skills := player.skills.to_dictionary()
	initial_skills.repair = {"level": 50, "current_exp": 0, "fractional_exp": 0.0}
	player.skills = SkillBook.new(initial_skills)
	_check(server.autosave_service.commit_player(player.entity_id, player).is_ok, "准备不会提前升级的维修等级")
	await _sync()
	_reset_observations()
	var before := player.skills.current_experience("repair")
	await _start_repair()
	_check(bool(actor.self_repair.active), "正式维修意图启动周期")
	server.advance_simulation(2.9)
	await process_frame
	_check(player.skills.current_experience("repair") == before, "周期未完成不发经验")
	server.advance_simulation(0.1)
	await process_frame
	_check(vehicle.health == vehicle.max_health - 7, "第一个周期实际回血12点")
	_check_experience(before + 12, "回血12点增加12点经验")
	server.advance_simulation(3.0)
	await process_frame
	_check(vehicle.health == vehicle.max_health and not bool(actor.self_repair.active), "末周期补满血并停止维修")
	_check_experience(before + 19, "维修力12但实际回血7点只增加7点经验")
	_check(server.map_instance.drain_skill_progression_events().is_empty(), "已消费维修事件不重复发经验")
	server.advance_simulation(3.0)
	await process_frame
	_check_experience(before + 19, "满血后不继续发经验")
	await _start_repair()
	_check(not bool(actor.self_repair.active), "满血拒绝开始维修")
	_check_experience(before + 19, "满血拒绝不发经验")
	actor.self_repair_base_strength = 7
	vehicle.health -= 7
	await _start_repair()
	server.advance_simulation(3.0)
	await process_frame
	_check(vehicle.health == vehicle.max_health, "维修力7实际回血7点")
	_check_experience(before + 26, "回血7点增加7点经验")
	vehicle.health -= 7
	vehicle.working_energy = 0.0
	vehicle.reserve_energy = 0.0
	await _start_repair()
	server.advance_simulation(3.0)
	await process_frame
	_check(vehicle.health == vehicle.max_health - 7 and not bool(actor.self_repair.active), "能量不足停止且不回血")
	_check_experience(before + 26, "未回血不发经验")
	_check(full_updates == 0 and equipment_updates == 0, "维修经验使用增量而非全量或外观刷新")
	_save_and_compare()
	var repository := FilePlayerStateRepository.new(config.player_state_store_path)
	_check(repository.initialize().is_ok, "打开维修经验隔离存档")
	var loaded := repository.load_player(player.entity_id)
	_check(loaded.is_ok, "重载维修经验记录")
	if loaded.is_ok:
		_check(int(loaded.value.character_skills.repair.current_exp) == before + 26, "实际回血累计经验正确落盘")
	var skill_level := player.skills.base_level("repair")
	var threshold := int(SkillProgression.get_need_points(&"repair", skill_level, server.player_panel_service._skill_progression_config).value)
	var states := player.skills.to_dictionary()
	states.repair = {"level": skill_level, "current_exp": threshold - 7, "fractional_exp": 0.0}
	player.skills = SkillBook.new(states)
	_check(server.autosave_service.commit_player(player.entity_id, player).is_ok, "准备临界升级经验")
	vehicle.working_energy = vehicle.working_energy_capacity
	vehicle.reserve_energy = vehicle.reserve_energy_capacity
	await _sync()
	await _start_repair()
	server.advance_simulation(3.0)
	await process_frame
	_check(player.skills.base_level("repair") == skill_level + 1, "实际回血7点触发维修升级")
	_check(panels.current_player.skills.base_level("repair") == skill_level + 1, "客户端同步维修升级")
	_check_experience(0, "升级沿用原有经验清零规则")
	_check(vehicle.health == vehicle.max_health, "升级不影响本次实际回血")
	_save_and_compare()
	var store_path := config.player_state_store_path
	var saved_skills := player.skills.to_dictionary()
	await _close()
	if not await _boot("res://data/maps/glory_nft_bl_d04.json", store_path): return false
	_check(player.skills.to_dictionary() == saved_skills, "保存重启保留维修经验与等级")
	_check(panels.current_player.skills.to_dictionary() == saved_skills, "重启客户端恢复相同技能状态")
	await _close()
	return true


func _start_repair() -> void:
	_check(not network.request_use_ability("self_repair", Vector2.ZERO).is_empty(), "客户端发送正式自维修意图")
	await process_frame
	await process_frame


func _check_experience(expected: int, label: String) -> void:
	_check(player.skills.current_experience("repair") == expected, label + "：服务端")
	_check(panels.current_player.skills.current_experience("repair") == expected, label + "：客户端")
