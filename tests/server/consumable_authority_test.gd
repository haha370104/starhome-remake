extends SceneTree

var failures: Array[String] = []
var fixture := PlayerPanelServiceFixture.new()
var catalog := ItemCatalog.new()
var mapper: PlayerStateMapper


## 验证食品使用事务、属性派生、经验结算以及正式服务器的资源同步。
func _initialize() -> void:
	fixture.initialize()
	catalog.initialize()
	mapper = PlayerStateMapper.new(catalog)
	_test_transactions()
	_test_live_server()
	for failure: String in failures:
		push_error(failure)
	print("CONSUMABLE_AUTHORITY failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


## 核对权威使用、冷却拒绝、存档往返及全部属性类增益的实际消费者。
func _test_transactions() -> void:
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.restore_items([])
	for label: String in ["比萨", "白兰地", "奶酪", "伏特加", "龙舌兰酒", "韩式寿司", "炒面面包"]:
		player.receive_loot(_item(label, 3))
	player.vehicle.health = 20
	player.health = 20
	player.food_status.physical = 80
	var now := int(Time.get_unix_time_from_system())
	var state: PlayerStateRecord = mapper.to_record(player).value
	var original := state.to_dictionary()
	var command := {"type": "use_inventory_item", "instance_id": "比萨", "inventory_revision": state.inventory_revision,
		"now": 0, "amount": 999999, "food_status": {"physical": 99999}}
	var used := fixture._service.execute(state, command)
	_expect(used.is_ok and state.to_dictionary() == original, "使用只生成候选且忽略伪造效果和时间")
	player = mapper.to_domain(used.value.candidate).value
	_expect(player.inventory.find("比萨").quantity == 2 and player.food_status.physical == 90
		and player.food_status.bonus(13) == 10, "一份比萨提供原版效果")
	_expect(not fixture._service.execute(used.value.candidate, command).is_ok, "重复请求拒绝旧背包版本")
	player.use_inventory_item("白兰地", player.inventory.revision, now)
	_expect(player.vehicle.max_health == 270 and player.vehicle.health == 20, "生命上限增益不免费回血")
	player.use_inventory_item("伏特加", player.inventory.revision, now)
	_expect(player.vehicle.health == 120, "即时战车治疗100")
	var before := player.inventory.find("伏特加").quantity
	_expect(not player.use_inventory_item("伏特加", player.inventory.revision, now + 1).is_ok
		and player.inventory.find("伏特加").quantity == before, "冷却拒绝不扣物品")
	player.use_inventory_item("奶酪", player.inventory.revision, now)
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0}).value
	var baseline: Dictionary = combat.vehicle_combat_loadout(mapper.to_domain(fixture._state).value, 20, {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0}).value
	_expect(loadout.weapons["energy_cannon.primary"].minimum_damage == baseline.weapons["energy_cannon.primary"].minimum_damage + 10,
		"食品攻击进入权威武器伤害")
	var vehicle := VehicleCombatState.new()
	vehicle.configure(loadout.assembly)
	_expect(vehicle.apply_damage(12).value.applied_damage == 7, "食品防御实际减伤")
	player.use_inventory_item("韩式寿司", player.inventory.revision, now)
	_expect(player.use_inventory_item("炒面面包", player.inventory.revision, now).is_ok, "使用裁缝食品")
	var config: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json").value
	player.skills = SkillBook.new({"energy_cannon": 10, "tailoring": 20})
	player.skills.food_status = player.food_status
	for skill: String in ["energy_cannon", "tailoring"]:
		var old_exp := player.skills.current_experience(skill)
		player.skills.grant_experience(skill, 10, config)
		_expect(player.skills.current_experience(skill) == old_exp + 12, "食品提高实际技能经验：%s exp=%d bonus=%s" % [skill, player.skills.current_experience(skill), player.food_status.experience_multiplier(skill)])
	player.use_inventory_item("龙舌兰酒", player.inventory.revision, now)
	state = mapper.to_record(player).value
	var restored := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(state.to_dictionary())))
	_expect(restored.is_ok, "食品状态完成JSON存档往返")
	state = fixture._service.advance_food_status(restored.value, now + 3).value
	_expect(state.character_health == 50, "在线三秒恢复30人物生命")
	state = fixture._service.advance_food_status(state, now + 3601).value
	_expect(state.vehicle_max_health == 70 and state.vehicle_health == 70 and state.food_status.active.is_empty(), "到期截断生命且清除全部效果")
	var projected := CurrentPlayer.new(catalog)
	_expect(projected.apply_bundle(fixture._service.build_bundle(restored.value)) and projected.food_status.bonus(13) == 10,
		"客户端投影收到完整食品状态")
	var invalid := fixture._service.build_bundle(restored.value)
	invalid.food_status.physical = -1
	_expect(not projected.apply_bundle(invalid), "客户端拒绝非法食品投影")


## 正式服务器使用实时能源并保留战斗冷却，食品时钟与仓储同步。
func _test_live_server() -> void:
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.player_state_store_path = "res://.godot/food-authority-%d.json" % Time.get_ticks_usec()
	var server := AuthoritativeServer.new()
	_expect(server.initialize(config).ok, "独立存档服务器初始化")
	var opened := server.open_session(77, {"protocol_version": config.protocol_version, "content_version": config.content_version}, 1000)
	_expect(opened.ok, "正式会话建立")
	var session: ServerSession = server.sessions.session_for_peer(77)
	var id := session.entity_id
	var state := server.autosave_service.state_for(id)
	for label: String in ["低级能量包", "龙舌兰酒", "比萨"]:
		var item := _item(label, 3)
		state = server.player_panel_service.grant_loot(state, {"loot_id": label, "item_definition_id": item.definition_id, "quantity": 3}).value.candidate
	state.character_health = 10
	server.autosave_service.commit_player_state(id, state)
	var map: AuthoritativeMapInstance = server.map_registry.instance_by_id(session.map_instance_id)
	var runtime := map.vehicle_combat_state_for(id)
	runtime.reserve_energy = 100
	var actor: Dictionary = map.combat_module.actors[id]
	actor.cooldown_ready_ticks["energy_cannon.primary"] = 999
	state = server.autosave_service.state_for(id)
	var result := server.handle_peer_player_panel_command(77, {"type": "use_inventory_item", "instance_id": "低级能量包", "inventory_revision": state.inventory_revision})
	_expect(result.ok and runtime.reserve_energy == 1100, "使用能量包以地图实时能源为准并写回运行态")
	_expect(actor.cooldown_ready_ticks.get("energy_cannon.primary") == 999, "使用不会重置射击冷却")
	state = server.autosave_service.state_for(id)
	result = server.handle_peer_player_panel_command(77, {"type": "use_inventory_item", "instance_id": "龙舌兰酒", "inventory_revision": state.inventory_revision})
	_expect(result.ok, "服务器使用回血食品")
	# 以已提交的使用时刻为基准，避免初始化跨秒后把三秒误算成四秒。
	var used_state := server.autosave_service.state_for(id)
	var now := int(used_state.food_status.active.filter(func(effect: Dictionary) -> bool: return int(effect.kind) == 18)[0].last_tick)
	server._advance_food_status()
	server._food_runtime.advance(server.sessions.all_sessions(), now + 3)
	state = server.autosave_service.state_for(id)
	_expect(state.character_health == 40, "服务器食品时钟实际结算人物回血")
	server._food_runtime.advance(server.sessions.all_sessions(), now + 3)
	_expect(server.autosave_service.state_for(id).character_health == 40, "重复时钟不重复治疗")
	server.disconnect_session(77, 2000)
	server._food_runtime.advance(server.sessions.all_sessions(), now + 9)
	_expect(server.autosave_service.state_for(id).character_health == 40, "断线宽限期不补发回血")
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))


## 按目录名称创建可使用实例。
## [param label] 原版食品或能量包名称。
## [param quantity] 测试堆叠数量。
## 返回真实目录类型。
func _item(label: String, quantity: int) -> ConsumableItem:
	for id: String in catalog.definition_ids():
		if catalog.display_name(id) == label:
			return catalog.create(id, {"instance_id": label, "quantity": quantity}).value as ConsumableItem
	return null


## 累计权威边界断言。
## [param condition] 必须成立的条件。
## [param message] 失败定位说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
