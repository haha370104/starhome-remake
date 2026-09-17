extends SceneTree

var failures: Array[String] = []
var checks := 0
var items := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var catalog: CombatDefinitionCatalog
var mapper: PlayerStateMapper


## 延迟执行真实目录装配与存档回归。
func _initialize() -> void:
	call_deferred("_run")


## 核对十一种宝石在面板和战斗中的数值，并验证前缀代价、减伤和热更新资源。
func _run() -> void:
	_expect(items.initialize().is_ok and fixture.initialize().is_ok, "初始化")
	mapper = PlayerStateMapper.new(items)
	catalog = CombatDefinitionCatalog.load_default().value
	for attribute: String in ClothingEnhancement.GEMS:
		var player: Player = mapper.to_domain(fixture._state).value
		var before: Dictionary = _loadout(player).assembly
		var shirt := player.inventory.find("inventory.training_shirt") as Clothing
		shirt.enhancement.gem = attribute
		shirt.enhancement.gem_stage = 7
		player.equip_character_item(shirt.instance_id, "upper_body", player.inventory.revision, player.revision)
		var stats := player.calculate_vehicle_stats()
		var loadout := _loadout(player)
		_expect(int(stats.max_health) == int(loadout.assembly.max_health), attribute + "生命一致")
		_expect(is_equal_approx(float(stats.speed), float(loadout.assembly.movement_speed)), attribute + "移速一致")
		_expect(int(stats.energy_cannon_attack) == int(loadout.weapons["energy_cannon.primary"].minimum_damage), attribute + "伤害一致")
		if attribute == "max_health":
			_expect(int(stats.max_health) == int(before.max_health) + 70 and player.vehicle.health == 70, "生命上限增加不治疗")
		elif attribute == "working_energy_capacity":
			_expect(float(stats.working_energy_capacity) == float(before.working_energy_capacity) + 35 and float(stats.working_energy_capacity) == float(loadout.assembly.working_energy_capacity), "工作能量一致")
		elif attribute == "output_power":
			_expect(is_equal_approx(float(stats.output_power), float(before.power_output) + 3.5) and stats.output_power == loadout.assembly.power_output, "输出功率一致")
		elif attribute == "self_repair":
			_expect(int(stats.self_repair_bonus) == int(loadout.assembly.self_repair_bonus_strength) and int(stats.self_repair_bonus) >= 7, "自维修包含人物装备")
		var persisted: PlayerStateRecord = mapper.to_record(player).value
		var restored: Player = mapper.to_domain(persisted).value
		_expect(restored.calculate_vehicle_stats() == stats, attribute + "存档重算一致")
	var player: Player = mapper.to_domain(fixture._state).value
	var shirt := player.inventory.find("inventory.training_shirt") as Clothing
	shirt.enhancement.prefix = "phoenix"
	shirt.enhancement.prefix_quality = 1
	player.equip_character_item(shirt.instance_id, "upper_body", player.inventory.revision, player.revision)
	_expect(player.vehicle.max_health == 10 and player.vehicle.health == 10, "凤凰固定生命代价真实生效")
	for _index: int in range(10):
		player = mapper.to_domain(mapper.to_record(player).value).value
	_expect(player.vehicle.health == 10, "重算和重登不反复恢复生命")
	_expect(CombatDefense.mitigate(100, 200) == 50 and CombatDefense.mitigate(100, 10000) == 25, "防御曲线与75%上限")
	var combat := AuthoritativeCombatModule.new()
	combat.configure(20, 42, 0)
	var loadout := _loadout(player)
	combat.register_vehicle("p", "map", Vector2.ZERO, loadout.assembly, loadout.weapons)
	var state: VehicleCombatState = combat.actors.p.vehicle_state
	state.health = 5
	state.working_energy = 7
	combat.actors.p.cooldown_ready_ticks["energy_cannon.primary"] = 999
	loadout.assembly.max_health = 100
	loadout.assembly.working_energy_capacity = 200
	_expect(combat.refresh_achievement_loadout("p", loadout).is_ok, "强化热更新")
	state = combat.actors.p.vehicle_state
	_expect(state.health == 5 and state.working_energy == 7 and state.working_energy_capacity == 200, "热更新不回复资源")
	_expect(combat.actors.p.cooldown_ready_ticks["energy_cannon.primary"] == 999, "强化不重置攻击冷却")
	state.health = 100
	state.defense = 200
	state.corrosion_reduction = 0.3
	_expect(int(state.apply_damage(100, true).value.applied_damage) == 35, "净化特性只减少腐蚀伤害")
	for failure: String in failures:
		push_error(failure)
	print("CLOTHING_STATS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 从真实装配目录构造权威战斗定义。
## [param player] 当前隔离测试玩家。
## 返回装配和武器边界数据。
func _loadout(player: Player) -> Dictionary:
	return catalog.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value


## 记录可诊断的行为断言。
## [param condition] 检查条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
