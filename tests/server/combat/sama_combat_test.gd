extends SceneTree

var catalog := ItemCatalog.new()
var checks := 0
var failures := PackedStringArray()


## 验证真实弹道贯穿、命中去重、矩形范围、追加击杀和来源时序。
func _initialize() -> void:
	_check(catalog.initialize().is_ok, "catalog")
	_domain_state()
	# Only this isolated test catalog makes activations certain.
	catalog.sama_rules.chance_percent.assign([100,100,100,100])
	var module := _module(["piercing"])
	for x in [50,100,150]: _monster(module, str(x), Vector2(x,0), 100)
	var shot := _shoot(module, 1, Vector2(50,0))
	_check(shot.is_ok and shot.value.piercing and shot.value.endpoint == [400.0,0.0], "piercing reaches full weapon range")
	module.advance_ticks(12)
	for id: String in ["50","100","150"]: _check(module.monsters[id].health == 93, "each crossed monster hit once")
	_check(module.pending_projectiles.is_empty(), "piercing eventually expires")
	var continued := 0
	for event: Dictionary in module.combat_events:
		if event.get("event_type") == &"energy_cannon_hit" and event.get("projectile_continues", false): continued += 1
	_check(continued == 3, "all nonfinal hit events keep visual projectile")
	module = _module(["piercing", "fission"])
	for x in [50,100,150]: _monster(module, str(x), Vector2(x,0), 80)
	_shoot(module, 1, Vector2(50,0))
	module.advance_ticks(12)
	_check(module.death_events.size() == 3 and module.ground_loot.size() == 3, "fission lethal damage shares one drop chain")
	_check(module.drain_quest_kills().size() == 3 and module.drain_quest_kills().is_empty(), "one quest/achievement kill per death")
	module.advance_ticks(10)
	_check(module.death_events.size() == 3 and module.ground_loot.size() == 3, "no duplicate reward after continued flight")
	module = _module(["pulse"])
	_monster(module, "front", Vector2(200,0), 70)
	_monster(module, "edge", Vector2(400,200), 100)
	_monster(module, "behind", Vector2(-1,0), 100)
	_monster(module, "side", Vector2(200,201), 100)
	_monster(module, "far", Vector2(401,0), 100)
	_monster(module, "other_map", Vector2(200,0), 100, "elsewhere")
	_shoot(module, 1, Vector2.RIGHT * 400)
	_check(module.monsters.front.health == 0 and module.monsters.edge.health == 20, "instant original-size frontal pulse")
	for id: String in ["behind","side","far","other_map"]: _check(module.monsters[id].health == 100, "pulse excludes " + id)
	_check(module.death_events.size() == 1 and module.ground_loot.size() == 1, "pulse death shared reward chain")
	var event_count := module.event_sequence
	_check(not _shoot(module, 2, Vector2.RIGHT * 400).is_ok and module.event_sequence == event_count, "cooldown rejection cannot proc pulse")
	module = _module(["piercing", "fission"])
	module.vehicle_state_for("tester").working_energy = 0
	_check(not _shoot(module, 1, Vector2.RIGHT * 100).is_ok and module.sama._states.is_empty(), "insufficient energy cannot activate buff")
	module = _module(["piercing"])
	_monster(module, "near", Vector2(30,0), 100)
	_monster(module, "next", Vector2(150,0), 100)
	_shoot(module, 1, Vector2.RIGHT * 400)
	module.advance_ticks(1)
	_check(module.monsters.near.health == 93, "first segment hit")
	(module.actors.tester.equipment_condition as EquipmentConditionLoadout)._items.clear()
	module.advance_ticks(10)
	_check(module.monsters.near.health == 93 and module.monsters.next.health == 93 and module.pending_projectiles.is_empty(), "removed source stops at next new target, never repeats prior hit")
	_check(module.snapshot_for_actor("tester").local_sama_effects.is_empty(), "removed source clears displayed state")
	module = _module(["piercing"])
	_shoot(module, 1, Vector2.RIGHT * 400)
	var snapshot := module.snapshot_for_actor("tester")
	_check(snapshot.local_sama_effects.size() == 1 and is_equal_approx(snapshot.local_sama_effects[0].remaining_seconds, 8), "authoritative remaining duration")
	var loadout := {"assembly": _assembly(module.actors.tester.equipment_condition), "weapons":{"cannon":_weapon()}}
	module.advance_ticks(2)
	module.refresh_achievement_loadout("tester", loadout)
	_check(module.snapshot_for_actor("tester").local_sama_effects[0].remaining_seconds < 8, "ordinary refresh never extends duration")
	module.current_tick = 160
	_check(module.snapshot_for_actor("tester").local_sama_effects.is_empty(), "expires exactly at end tick")
	module = _module(["fission"])
	_shoot(module, 1, Vector2.RIGHT * 400)
	module._record_combat_event({"event_type":&"monster_attack_resolved", "target_entity_id":"tester", "damage":1, "target_destroyed":true})
	_check(not module.sama._states.has("tester"), "death clears special effects")
	module.unregister_vehicle("tester")
	_check(not module.sama._states.has("tester"), "exit cleanup")
	module = _module(["pvp_absorption"])
	_shoot(module, 1, Vector2.RIGHT * 400)
	_check(module.snapshot_for_actor("tester").local_sama_effects.is_empty() and module.combat_events.size() == 1, "PvP effects never activate against monsters")
	module = _module(["pulse"])
	for index in 40: _monster(module, "crowd%d" % index, Vector2(200, index - 20), 100)
	_shoot(module, 1, Vector2.RIGHT * 400)
	_check(module.snapshot_for_actor("tester").recent_events[0].event_type == &"energy_cannon_projectile_spawned", "area hit burst retains originating visual event")
	print("Sama combat: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 核对概率边界、到期、来源和旋转后的矩形几何。
func _domain_state() -> void:
	var item := catalog.create("glory_equipment_samajnq_1011d2a44c", {"instance_id":"domain"}).value as VehicleEquipment
	var state := SamaCombatState.new()
	_check(state.activate(item, 0.01, 0, 20) == null, "exact probability threshold fails")
	_check(state.activate(item, 0.009, 0, 20) != null and state.active("piercing", "domain", 19) != null, "below threshold active")
	_check(state.active("piercing", "domain", 20) == null, "one second exact expiry")
	for roll: float in [NAN,INF,-0.1,1.0]: _check(state.activate(item, roll, 0, 20) == null, "bad random input")
	item.durability = 0
	_check(state.activate(item, 0, 0, 20) == null, "damaged source")
	_check(SamaCombatState.inside_pulse(Vector2(-200,400), Vector2.ZERO, Vector2.DOWN, 400), "rotated edge included")
	_check(not SamaCombatState.inside_pulse(Vector2(0,-1), Vector2.ZERO, Vector2.DOWN, 400), "rotated back excluded")


## 构建使用真实装备规则的确定性战斗模块。
## [param effects] 本次测试装配的能力。
## 返回隔离模拟。
func _module(effects: Array[String]) -> AuthoritativeCombatModule:
	var condition := EquipmentConditionLoadout.new()
	for id: String in catalog.sama_rules.profiles:
		if catalog.sama_rules.profiles[id].effect not in effects: continue
		var item := catalog.create(id, {"instance_id":id, "sama":{"version":1,"color":3,"growth":0,"quality":0}}).value as VehicleEquipment
		condition._items[item.instance_id] = item
	var result := AuthoritativeCombatModule.new()
	_check(result.configure(20, 371, 0).is_ok, "configure")
	_check(result.register_vehicle("tester", "test", Vector2.ZERO, _assembly(condition), {"cannon":_weapon()}).is_ok, "register")
	return result


## 提供不会因测试射击耗尽的独立资源，不更改用户存档。
## [param condition] 真实特殊装备实例。
## 返回权威装配配置。
func _assembly(condition: EquipmentConditionLoadout) -> Dictionary:
	return {"max_health":1000,"reserve_energy_capacity":1000,"working_energy_capacity":1000,"power_output":100,"passive_power_load":0,"equipment_condition":condition}


## 固定普通炮伤害和轨迹，使附加效果可单独断言。
## 返回测试武器定义。
func _weapon() -> Dictionary:
	return {"weapon_id":"rookie_energy_cannon","skill_id":"energy_cannon","minimum_damage":7,"maximum_damage":7,"working_energy_cost":10,"activation_power":0,"range":400,"cooldown_ticks":20,"projectile_speed":1000.0,"muzzle_offset":[0.0,0.0],"muzzle_forward_offset":0.0}


## 投放有保证掉落的静止怪物，避免AI漂移干扰碰撞断言。
## [param module] 战斗模块。[param id] 身份。[param point] 脚点。[param health] 生命。[param map_id] 地图。
func _monster(module: AuthoritativeCombatModule, id: String, point: Vector2, health: int, map_id := "test") -> void:
	_check(module.register_monster({"monster_id":id,"species_id":"om_adult","map_instance_id":map_id,"position":point,"max_health":health,"respawn_seconds":30,"projectile_hitbox":{"offset":[0,0],"radius":10},"drops":[{"item_definition_id":"low_grade_gel","minimum_quantity":1,"maximum_quantity":1,"chance":1.0}]}).is_ok, "monster")


## 通过正式能力意图触发攻击，不直接调用伤害入口。
## [param module] 战斗模块。[param sequence] 单调命令号。[param aim] 瞄准点。
## 返回正式攻击结果。
func _shoot(module: AuthoritativeCombatModule, sequence: int, aim: Vector2) -> DomainResult:
	return module.handle_weapon_attack("tester", UseAbilityIntent.new("test","cannon",aim,sequence).to_dictionary())


## 汇总行为和时序断言。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
