extends SceneTree

var catalog := ItemCatalog.new()
var checks := 0
var failures := PackedStringArray()


## 验证真实飞行、穿透、死亡、换装与芯片成长均不会增加致命一击次数。
func _initialize() -> void:
	_check(catalog.initialize().is_ok, "catalog")
	catalog.central_rules.fatal_chance_percent.assign([100,100,100])
	catalog.sama_rules.chance_percent.assign([100,100,100,100])
	var module := _module(true)
	_monster(module, "first", Vector2(30,0), 1000)
	_monster(module, "second", Vector2(150,0), 1000)
	_monster(module, "third", Vector2(250,0), 1000)
	_check(_shoot(module, 1).is_ok, "accepted cannon")
	module.advance_ticks(1)
	var random_state := module.central._random.state
	_check(module.monsters.first.health == 940 and _fatal_events(module).size() == 1, "first contact capped extra damage")
	module.advance_ticks(8)
	_check(module.monsters.second.health == 990 and module.monsters.third.health == 990, "piercing later targets ordinary only")
	_check(module.central._random.state == random_state and _fatal_events(module).size() == 1, "one random draw even across ticks")
	_check(not _shoot(module, 2).is_ok and module.central._random.state == random_state, "rejected cooldown no proc or draw")
	module.advance_ticks(11)
	_check(_shoot(module, 3).is_ok, "next accepted shot")
	module.advance_ticks(8)
	_check(_fatal_events(module).size() == 2 and module.monsters.first.health == 880, "new shot has independent contact")
	for reason: String in ["removed", "broken", "dead"]:
		module = _module(true)
		_monster(module, "target", Vector2(150,0), 1000)
		_shoot(module, 1)
		if reason == "removed": module.actors.tester.equipment_condition._items.erase("gun")
		elif reason == "broken": module.actors.tester.equipment_condition._items.gun.durability = 0
		else: module.vehicle_state_for("tester").health = 0
		module.advance_ticks(10)
		_check(_fatal_events(module).is_empty(), "no effect after source " + reason)
	module = _module(true)
	_monster(module, "weak", Vector2(30,0), 5)
	_monster(module, "strong", Vector2(150,0), 1000)
	_shoot(module, 1)
	module.advance_ticks(10)
	_check(module.monsters.weak.health == 0 and module.monsters.strong.health == 990 and _fatal_events(module).is_empty(), "ordinary kill still consumes first contact")
	_check(module.death_events.size() == 1 and module.ground_loot.size() == 1 and module.drain_quest_kills().size() == 1, "ordinary kill reward once")
	module = _module(false, true)
	_monster(module, "combo", Vector2(150,0), 30)
	_shoot(module, 1)
	module.advance_ticks(10)
	_check(module.monsters.combo.health == 0 and _fatal_events(module).size() == 1, "fatal then fission")
	_check(_fatal_events(module)[0].damage == 18, "ninety percent of remaining health")
	_check(module.death_events.size() == 1 and module.ground_loot.size() == 1 and module.drain_quest_kills().size() == 1, "fission combo reward and quest once")
	module.advance_ticks(5)
	_check(module.death_events.size() == 1 and module.drain_quest_kills().is_empty(), "no recursive reward")
	module = _module(false)
	_monster(module, "boss", Vector2(150,0), 1000000)
	_shoot(module, 1)
	module.advance_ticks(10)
	_check(module.monsters.boss.health == 999940, "very large monster still uses same configured cap")
	module = _module(false)
	_monster(module, "armored", Vector2(150,0), 1000)
	module.monsters.armored.defense = 200
	_shoot(module, 1)
	module.advance_ticks(10)
	_check(module.monsters.armored.health == 970 and _fatal_events(module)[0].damage == 25, "cap uses actual ordinary damage; no second defense subtraction")
	module = _module(false, true)
	catalog.central_rules.fatal_current_health_percent = 100
	_monster(module, "fatal_kill", Vector2(150,0), 30)
	_shoot(module, 1)
	module.advance_ticks(10)
	_check(module.monsters.fatal_kill.health == 0 and _fatal_events(module)[0].has("death"), "configured lethal percentage carries death event")
	_check(module.death_events.size() == 1 and module.ground_loot.size() == 1 and module.drain_quest_kills().size() == 1, "fatal kill cannot double settle fission or rewards")
	catalog.central_rules.fatal_current_health_percent = 90
	module = _module(false)
	module.vehicle_state_for("tester").working_energy = 0
	random_state = module.central._random.state
	_check(not _shoot(module, 1).is_ok and module.pending_projectiles.is_empty() and module.central._random.state == random_state, "no energy means no ticket or probability draw")
	module = _module(false)
	module.actors.tester.central_controller = PlayerCentralController.new()
	_monster(module, "no_chip", Vector2(150,0), 1000)
	_shoot(module, 1)
	_check(module.pending_projectiles[0].central_shot == null, "no chip no per-projectile object")
	module.advance_ticks(10)
	_check(module.monsters.no_chip.health == 990, "no unowned ability")
	module = _module(false)
	catalog.central_rules.fatal_chance_percent.assign([0,0,100])
	module.actors.tester.central_controller = PlayerCentralController.restore({"grades":{"gun":1}}).value
	_monster(module, "frozen", Vector2(150,0), 1000)
	_shoot(module, 1)
	module.actors.tester.central_controller.use_module(catalog.central_rules.modules.central_gun_module_3)
	module.advance_ticks(10)
	_check(module.monsters.frozen.health == 990, "mid-flight chip upgrade cannot amplify previous shot")
	_check(module.central.accepted_shot(module.actors.tester.central_controller, catalog.central_rules, {"instance_id":"gun", "skill_id":"missile"}) == null, "secondary weapons excluded")
	_check(module.central.accepted_shot(module.actors.tester.central_controller, catalog.central_rules, {"instance_id":"gun", "skill_id":"rocket_launcher"}) == null, "rocket excluded")
	print("Central combat: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 用真实武器及可选撒玛建立独立受控战斗，不修改配置文件。
## [param piercing] 是否加入穿透。[param fission] 是否加入核变。
## 返回初始化的权威模块。
func _module(piercing: bool, fission: bool = false) -> AuthoritativeCombatModule:
	var condition := EquipmentConditionLoadout.new()
	condition._items.gun = catalog.create("recruit_energy_cannon", {"instance_id":"gun"}).value
	if piercing:
		condition._items.piercing = catalog.create("glory_equipment_samajnq_1011d2a44c", {"instance_id":"piercing", "sama":{"version":1,"color":3,"growth":0,"quality":0}}).value
	if fission:
		condition._items.fission = catalog.create("glory_equipment_samahbq_5a2ea60d71", {"instance_id":"fission", "sama":{"version":1,"color":3,"growth":0,"quality":0}}).value
	var assembly := {"max_health":1000, "reserve_energy_capacity":1000, "working_energy_capacity":1000, "power_output":100,
		"passive_power_load":0, "equipment_condition":condition, "central_controller":{"grades":{"gun":3}}, "central_rules":catalog.central_rules}
	var weapon := {"weapon_id":"rookie_energy_cannon", "instance_id":"gun", "skill_id":"energy_cannon", "minimum_damage":10, "maximum_damage":10,
		"working_energy_cost":10, "activation_power":0, "range":400, "cooldown_ticks":20, "projectile_speed":1000.0, "muzzle_offset":[0.0,0.0], "muzzle_forward_offset":0.0}
	var module := AuthoritativeCombatModule.new()
	_check(module.configure(20,371,0).is_ok, "configure")
	_check(module.register_vehicle("tester", "test", Vector2.ZERO, assembly, {"cannon":weapon}).is_ok, "register")
	return module


## 放置静止、保证掉落的可攻击怪物以核对实际碰撞和结算次数。
## [param module] 模拟。[param id] 怪物身份。[param point] 位置。[param health] 初始生命。
func _monster(module: AuthoritativeCombatModule, id: String, point: Vector2, health: int) -> void:
	_check(module.register_monster({"monster_id":id, "species_id":"om_adult", "map_instance_id":"test", "position":point,
		"max_health":health, "respawn_seconds":30, "projectile_hitbox":{"offset":[0,0],"radius":10},
		"drops":[{"item_definition_id":"low_grade_gel", "minimum_quantity":1,"maximum_quantity":1,"chance":1.0}]}).is_ok, "monster")


## 通过正常能力意图发射，保留能源和冷却验证。
## [param module] 模拟。[param sequence] 命令序号。
## 返回射击结果。
func _shoot(module: AuthoritativeCombatModule, sequence: int) -> DomainResult:
	return module.handle_weapon_attack("tester", UseAbilityIntent.new("test","cannon",Vector2(400,0),sequence).to_dictionary())


## 收集实际已发布的致命一击事件。
## [param module] 当前模拟。
## 返回事件列表。
func _fatal_events(module: AuthoritativeCombatModule) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in module.combat_events:
		if event.event_type == &"central_fatal_hit": result.append(event)
	return result


## 汇总时序与伤害断言。
## [param condition] 条件。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
