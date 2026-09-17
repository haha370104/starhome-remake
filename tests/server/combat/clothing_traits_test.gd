extends SceneTree

var checks := 0
var failures: Array[String] = []

class Navigation:
	extends RefCounted
	var graph := AStar2D.new()


## 推迟到正式目录可加载后执行专项。
func _initialize() -> void:
	call_deferred("_run")


## 验证连击断链、真实炮弹追击、节能、受击维修等待以及矿源并发预约。
func _run() -> void:
	var effects := ClothingCombatEffects.new()
	effects.observe_weapon("a")
	for index: int in range(3):
		_expect(effects.hit("a", "target", index * 20, 20, 0.25) == 0, "前三击不加伤")
	_expect(effects.hit("a", "target", 60, 20, 0.25) == 0.25, "第四击加伤")
	effects.hit("a", "target", 80, 20, 0.25)
	effects.hit("a", "target", 100, 20, 0.25)
	effects.hit("a", "other", 120, 20, 0.25)
	_expect(effects.hit("a", "target", 140, 20, 0.25) == 0, "换目标断链")
	effects.observe_weapon("b")
	_expect(effects.hit("a", "target", 150, 20, 0.25) == 0, "旧武器在途弹体不叠层")
	effects.observe_weapon("a")
	for index: int in range(3):
		effects.hit("a", "target", 160 + index, 20, 0.25)
	_expect(effects.hit("a", "target", 263, 20, 0.25) == 0, "超过五秒断链")
	effects.repair_wait_reduction = 1.2
	effects.damaged(100, 20)
	_expect(effects.repair_ready_tick == 136, "完美维修受击等待1.8秒")
	_test_combat()
	_test_mining()
	for failure: String in failures:
		push_error(failure)
	print("CLOTHING_TRAITS checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 使用正式目录和实际弹体结算检查特性不是仅改变面板。
func _test_combat() -> void:
	var items := ItemCatalog.new()
	items.initialize()
	var fixture := PlayerPanelServiceFixture.new()
	fixture.initialize()
	var player: Player = PlayerStateMapper.new(items).to_domain(fixture._state).value
	var shirt := player.inventory.find("inventory.training_shirt") as Clothing
	shirt.enhancement.trait_id = "economy"
	shirt.enhancement.trait_quality = 6
	player.equip_character_item(shirt.instance_id, "upper_body", player.inventory.revision, player.revision)
	var catalog: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout: Dictionary = catalog.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	var base_cost := (player.vehicle.loadout.at(1) as VehicleWeapon).working_energy_per_shot
	_expect(is_equal_approx(float(loadout.weapons["energy_cannon.primary"].working_energy_cost), base_cost * 0.88), "实际武器节能12%")
	shirt.enhancement.trait_id = "pursuit"
	loadout = catalog.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	var combat := AuthoritativeCombatModule.new()
	combat.configure(20, 123, 0)
	combat.register_vehicle("player", "map", Vector2.ZERO, loadout.assembly, loadout.weapons)
	var weapon: Dictionary = combat.actors.player.weapons["energy_cannon.primary"]
	_expect(float(weapon.pursuit_bonus) == 0.25, "武器规范化保留特性")
	(combat.actors.player.clothing_effects as ClothingCombatEffects).observe_weapon(String(weapon.weapon_id))
	var monster := MonsterLifecycle.new()
	monster.monster_id = "target"
	monster.map_instance_id = "map"
	monster.max_health = 1000
	monster.health = 1000
	combat.monsters["target"] = monster
	for index: int in range(4):
		combat._settle_projectile({"target_entity_id": "target", "impact_position": Vector2(50, 0), "weapon": weapon,
			"attacker_id": "player", "shot_id": str(index)})
	var damage := int(weapon.minimum_damage)
	_expect(monster.health == 1000 - damage * 3 - roundi(damage * 1.25), "第四颗实际炮弹增加25%伤害")
	var actor: Dictionary = combat.actors.player
	var state: VehicleCombatState = actor.vehicle_state
	state.max_health = 100
	state.health = 10
	actor.self_repair.active = true
	actor.self_repair.health_per_cycle = 5
	actor.self_repair.next_cycle_tick = 1
	var effects: ClothingCombatEffects = actor.clothing_effects
	effects.repair_wait_reduction = 1.2
	combat._record_combat_event({"target_entity_id": "player", "damage": 1})
	combat.advance_ticks(35, false)
	_expect(state.health == 10, "受击等待到期前不维修")
	combat.advance_ticks(1, false)
	_expect(state.health == 15 and int(actor.self_repair.next_cycle_tick) == 96, "1.8秒后恢复且下个周期仍三秒")


## 预约额外矿量时排除其他玩家已预约份额，重试不重新随机。
func _test_mining() -> void:
	var navigation := Navigation.new()
	for index: int in range(100):
		navigation.graph.add_point(index, Vector2(index % 10, floori(index / 10.0)) * 200 + Vector2(100, 100))
	var module := AuthoritativeMiningModule.new()
	module.configure(MiningCatalog.load_default().value, "d04_field_zone", "mining", 20, navigation)
	var source: MineSource = module.sources.values()[0]
	var started := module.begin_collection("a", source.position + Vector2(40, 0), source.position, 1000, 1, 0, 30, 0.12)
	_expect(started.is_ok and is_equal_approx(float(started.value.interval_seconds), 3.0 / 1.3), "挖掘力加速真实周期")
	var seed_value := 0
	while true:
		module._enhancement_random.seed = seed_value
		if module._enhancement_random.randf() < 0.12:
			break
		seed_value += 1
	module._enhancement_random.seed = seed_value
	module.advance_ticks(roundi(60.0 / 1.3))
	var ready := module.drain_ready_cycles()
	_expect(ready.size() == 1 and int(ready[0].quantity) == 2, "探矿概率触发额外一份")
	var settled := module.commit_cycle(String(ready[0].token))
	_expect(settled.is_ok and source.remaining == 48, "真实扣除两份矿量")
	module.interrupt("a", &"test")
	source.remaining = 1
	module.begin_collection("a", source.position + Vector2(40, 0), source.position, 1000, 2, 0, 0, 0.12)
	module.begin_collection("b", source.position + Vector2(40, 0), source.position, 1000, 1, 0, 0, 0.12)
	module.advance_ticks(60)
	ready = module.drain_ready_cycles()
	_expect(ready.size() == 1 and int(ready[0].quantity) == 1, "两个玩家不能重复预约最后一份矿")
	_expect(module.commit_cycle(String(ready[0].token)).is_ok and source.remaining == 0, "结算后无超采")


## 累计验证结果。
## [param condition] 成功条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
