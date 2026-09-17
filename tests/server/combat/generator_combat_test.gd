extends SceneTree

var checks := 0
var failures: Array[String] = []
var _catalog := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()


## 验证装置原子扣料、主炮命中链、临时状态清理与一次死亡奖励。
func _initialize() -> void:
	_check(_catalog.initialize().is_ok and _fixture.initialize().is_ok, "目录和隔离夹具")
	_test_activation()
	_test_hit_lifecycle()
	_test_exclusions()
	print("Generator combat: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 拒绝条件不会半扣弹药能量，装配刷新不重置同一实例冷却。
func _test_activation() -> void:
	var item := _generator("unit", 14)
	item.generator_profile.chance = 0.5
	item.generator_profile.cooldown_seconds = 3
	var state := VehicleCombatState.new()
	state.health = 100
	state.working_energy = 20
	var activation := GeneratorActivation.new()
	var count := item.magazine.remaining
	_check(not activation.try_activate(item, state, 0, 20, 0.5), "概率右端不触发")
	_check(not activation.try_activate(item, state, 0, 20, NAN), "非法随机数")
	_check(item.magazine.remaining == count and state.working_energy == 20, "未抽中不扣费")
	state.working_energy = 2
	_check(not activation.try_activate(item, state, 0, 20, 0), "能量不足")
	_check(item.magazine.remaining == count and state.working_energy == 2, "不足无部分扣费")
	state.working_energy = 20
	_check(activation.try_activate(item, state, 0, 20, 0), "首次触发")
	_check(item.magazine.remaining == count - 1 and state.working_energy == 17, "一发弹药和配置能量")
	activation.retain(PackedStringArray(["unit"]))
	_check(not activation.try_activate(item, state, 59, 20, 0), "同实例刷新不重置冷却")
	_check(activation.try_activate(item, state, 60, 20, 0), "冷却精确边界")
	item.magazine.remaining = 0
	_check(not activation.try_activate(item, state, 120, 20, 0) and state.working_energy == 14, "缺弹不扣能量")
	item.magazine.remaining = 1
	item.durability = 0
	_check(not activation.try_activate(item, state, 120, 20, 0), "损坏不触发")
	item.durability = 1
	state.health = 0
	_check(not activation.try_activate(item, state, 120, 20, 0), "战车死亡不触发")
	state.health = 100
	item.generator_profile.heat_damage = 0
	item.generator_profile.energy_attack_percent_reduction = 0.5
	_check(not activation.try_activate(item, state, 120, 20, 0), "只有未核实目标类型的压制不空耗弹药")


## 实际弹体命中后两件各触发一次，高热击杀使用原有掉落和任务路径。
func _test_hit_lifecycle() -> void:
	var module := _module(9)
	var state := module.vehicle_state_for("p")
	var condition: EquipmentConditionLoadout = module.actors.p.equipment_condition
	var original := condition.generators()[0].magazine.remaining
	_check(_fire(module, 1).is_ok, "接受主炮")
	_check(not _fire(module, 1).is_ok, "重复命令拒绝")
	module.advance_ticks(5, false)
	_check(module.monster_for("m").health == 8, "命中只扣一次主炮伤害")
	_check(condition.generators()[0].magazine.remaining == original - 1 and condition.generators()[1].magazine.remaining == original - 1, "两件发生器各消耗一发")
	_check(state.working_energy == 89, "主炮5能量加两件各3")
	_check(module.monster_for("m").generator_afflictions.labels() == PackedStringArray(["高热"]), "同类状态单一标签")
	module.monster_for("m").defense = 1000
	module.advance_ticks(60, false)
	_check(not module.monster_for("m").is_alive() and module.death_events.size() == 1, "高热一次致死")
	_check(module.ground_loot.size() == 1, "持续伤害走原掉落")
	var kills := module.drain_quest_kills()
	_check(kills.size() == 1 and kills[0].killer_id == "p", "击杀归属及任务")
	_check(module.drain_quest_kills().is_empty(), "击杀只消费一次")
	var heat_events := 0
	var total := 0
	for event: Dictionary in module.combat_events:
		if event.event_type == &"generator_heat_hit": heat_events += 1; total += int(event.damage)
	_check(heat_events == 2 and total == 8, "两个装置不叠加同类伤害且穿透防御")
	_check(module.monster_for("m").generator_afflictions.labels().is_empty(), "死亡清理")
	module.advance_ticks(600, false)
	_check(module.monster_for("m").is_alive() and module.monster_for("m").health == 9, "复活不继承高热")
	_check(module.death_events.size() == 1, "到期不重复致死")


## 缺弹、落空、换装、玩家死亡和离开不会产生幽灵状态或额外收费。
func _test_exclusions() -> void:
	var module := _module(100)
	var condition: EquipmentConditionLoadout = module.actors.p.equipment_condition
	for item: VehicleEquipment in condition.generators(): item.magazine.remaining = 0
	_check(_fire(module, 1).is_ok, "装置缺弹不阻止主炮")
	module.advance_ticks(5, false)
	_check(module.monster_for("m").health == 99 and module.monster_for("m").generator_afflictions.labels().is_empty(), "缺弹仍正常主炮命中")
	module = _module(100)
	_fire(module, 1, Vector2(0, 100))
	module.advance_ticks(5, false)
	_check(module.monster_for("m").health == 100 and module.vehicle_state_for("p").working_energy == 95, "落空不触发不收费")
	module = _module(100)
	_fire(module, 1)
	module.generators.retain_sources("p", PackedStringArray(), module.monsters)
	module.actors.p.equipment_condition = EquipmentConditionLoadout.new()
	module.advance_ticks(5, false)
	_check(module.monster_for("m").generator_afflictions.labels().is_empty(), "飞行途中卸装不触发")
	module = _module(100)
	_fire(module, 1)
	module.advance_ticks(5, false)
	module.generators.retain_sources("p", PackedStringArray(), module.monsters)
	module.advance_ticks(40, false)
	_check(module.monster_for("m").health == 99, "卸装移除已附着伤害")
	module = _module(100)
	_fire(module, 1)
	module.advance_ticks(5, false)
	module.unregister_vehicle("p")
	module.advance_ticks(40, false)
	_check(module.monster_for("m").health == 99 and module.monster_for("m").generator_afflictions.labels().is_empty(), "离开清理")
	module = _module(100)
	_fire(module, 1)
	module.advance_ticks(5, false)
	module._record_combat_event({"event_type": &"monster_attack_resolved", "target_entity_id": "p", "damage": 1, "target_destroyed": true})
	_check(module.monster_for("m").generator_afflictions.labels().is_empty(), "权威死亡事件清理")
	var magnet := GeneratorRules.Profile.new()
	magnet.duration_seconds = 3
	magnet.attack_percent_reduction = 0.5
	module.monster_for("m").generator_afflictions.apply(magnet, "p", "mag", module.current_tick, 20)
	module.monster_for("m").attack_mode.base_attack = 20
	var before := module.vehicle_state_for("p").health
	module._begin_monster_attack("m", "p", Vector2.ZERO)
	_check(module.vehicle_state_for("p").health == before - 10, "实际怪物攻击降攻")


## 建立采用真实装备和弹仓、可控怪物与炮弹的隔离战斗模块。
## [param health] 怪物生命。
## 返回可以立即发射主炮的权威模块。
func _module(health: int) -> AuthoritativeCombatModule:
	var player: Player = PlayerStateMapper.new(_catalog).to_domain(_fixture._state).value
	for location: int in [14, 34]: player.vehicle.loadout.equip(_generator("g%d" % location, location), location, player.vehicle.loadout.revision)
	var module := AuthoritativeCombatModule.new()
	_check(module.configure(20, 31, 0).is_ok, "模块配置")
	var assembly := {"max_health": 100, "reserve_energy_capacity": 10000, "working_energy_capacity": 100,
		"power_output": 20, "passive_power_load": 0, "equipment_condition": EquipmentConditionLoadout.new(player)}
	var weapon := {"weapon_id": "test.cannon", "minimum_damage": 1, "maximum_damage": 1, "working_energy_cost": 5,
		"range": 250, "cooldown_ticks": 1, "projectile_speed": 1000, "muzzle_offset": [0, 0], "muzzle_forward_offset": 0}
	_check(module.register_vehicle("p", "map", Vector2.ZERO, assembly, {"energy_cannon.primary": weapon}).is_ok, "注册战车")
	_check(module.register_monster({"monster_id": "m", "species_id": "test", "map_instance_id": "map", "position": Vector2(100, 0),
		"max_health": health, "defense": 0, "respawn_seconds": 30, "base_attack": 20,
		"drops": [{"item_definition_id": "test.drop", "minimum_quantity": 1, "maximum_quantity": 1, "chance": 1}],
		"projectile_hitbox": {"offset": [0, 0], "radius": 20}}).is_ok, "注册怪物")
	return module


## 用独立规则强制命中，测试不会修改共享目录的正式概率。
## [param id] 装备实例身份。
## [param location] 两个允许位置之一。
## 返回真实弹仓加可控规则的发生器。
func _generator(id: String, location: int) -> VehicleEquipment:
	var item: VehicleEquipment = _catalog.create("glory_equipment_gaoregun_217b753365", {"instance_id": id, "equipment_location": location}).value
	var profile := GeneratorRules.Profile.new()
	profile.chance = 1
	profile.duration_seconds = 3
	profile.heat_damage = 4
	profile.working_energy_cost = 3
	item.generator_profile = profile
	return item


## 提交经过标准协议的开炮意图。
## [param module] 测试地图权威模块。
## [param sequence] 严格递增的输入序号。
## [param aim] 实际瞄准点。
## 返回权威接受或拒绝。
func _fire(module: AuthoritativeCombatModule, sequence: int, aim: Vector2 = Vector2(100, 0)) -> DomainResult:
	return module.handle_weapon_attack("p", UseAbilityIntent.new("map", "energy_cannon.primary", aim, sequence).to_dictionary())


## 汇总实际战斗断言。
## [param condition] 当前预期。
## [param label] 失败说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
