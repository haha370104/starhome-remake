extends SceneTree

var failures: Array[String] = []
var checks := 0
var catalog: CombatDefinitionCatalog


## 加载真实目录后验证毒胶弹体、腐蚀脉冲和地图生命周期。
func _initialize() -> void:
	catalog = CombatDefinitionCatalog.load_default().value
	_test_spray_speed()
	_test_attachment()
	_test_ground()
	_test_refresh_and_lifecycle()
	for failure: String in failures:
		push_error(failure)
	print("CORROSIVE_ATTACK checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 创建两地图战车与一只真实 D03 低温毒胶，伤害固定为40便于核对脉冲。
## 返回独立权威战斗模块。
func _fixture() -> AuthoritativeCombatModule:
	var module := AuthoritativeCombatModule.new()
	module.configure(20, 123)
	var assembly := {"max_health": 1000, "reserve_energy_capacity": 100,
		"working_energy_capacity": 100, "power_output": 10, "passive_power_load": 0}
	_expect(module.register_vehicle("p", "map", Vector2(100, 0), assembly, {}).is_ok, "战车注册")
	_expect(module.register_vehicle("remote", "other", Vector2(100, 0), assembly, {}).is_ok, "异图战车注册")
	var population: Array = catalog.monster_lifecycles_for_map("buli_d03_field_zone", "map").value
	for definition: Dictionary in population:
		if definition.species_id == "glory_monster_005":
			definition.monster_id = "gel"
			definition.position = Vector2.ZERO
			definition.base_attack = 40
			_expect(module.register_monster(definition).is_ok, "冷系毒胶注册")
			break
	return module


## 验证直接命中改为附着持续伤害，并随移动、到期和死亡正确结束。
func _test_attachment() -> void:
	var module := _fixture()
	module._begin_monster_attack("gel", "p", Vector2(100, 0))
	module.advance_ticks(10, false)
	var state: VehicleCombatState = module.actors.p.vehicle_state
	var clouds: Array = module.snapshot_for_actor("p").corrosive_clouds
	_expect(state.health == 1000 and clouds.size() == 1, "命中形成附着，不再瞬间结算完整伤害")
	if clouds.is_empty():
		return
	_expect(clouds[0].attached_actor_id == "p", "附着对象是实际碰撞战车")
	module.advance_ticks(15, false)
	_expect(state.health == 990, "首个一秒脉冲扣四分之一伤害")
	module.update_actor_position("p", Vector2(800, 800))
	module.advance_ticks(20, false)
	_expect(state.health == 980, "离开命中地点仍承受附着伤害")
	_expect(module.snapshot_for_actor("p").corrosive_clouds[0].position == [800.0, 784.0], "附着快照跟随战车")
	_expect(module.snapshot_for_actor("remote").corrosive_clouds.is_empty(), "异图不泄漏毒雾快照")
	module.advance_ticks(20, false)
	_expect(state.health == 970 and not module.corrosion.is_empty(), "附着满三秒时仍可见且按周期扣血")
	module.advance_ticks(40, false)
	_expect(state.health == 960 and module.corrosion.is_empty(), "四个脉冲后彻底结束")
	module.advance_ticks(100, false)
	_expect(state.health == 960, "消失后不再暗中扣血")


## 验证弹丸可躲开、落地后只伤害范围内的同图战车。
func _test_ground() -> void:
	var module := _fixture()
	module._begin_monster_attack("gel", "p", Vector2(100, 0))
	module.update_actor_position("p", Vector2(400, 400))
	module.advance_ticks(10, false)
	var clouds: Array = module.snapshot_for_actor("p").corrosive_clouds
	_expect(clouds.size() == 1, "落空后留下地面残留")
	if clouds.is_empty():
		return
	_expect(clouds[0].attached_actor_id == "" and clouds[0].position == [100.0, -16.0], "残留停在原瞄准点")
	module.advance_ticks(12, false)
	var state: VehicleCombatState = module.actors.p.vehicle_state
	_expect(state.health == 1000, "躲开地面毒雾不会扣血")
	module.update_actor_position("p", Vector2(100, 0))
	module.advance_ticks(20, false)
	_expect(state.health == 990, "进入毒雾范围后受伤")
	module.update_actor_position("p", Vector2(500, 0))
	module.advance_ticks(20, false)
	_expect(state.health == 990, "离开地面毒雾停止受伤")
	_expect((module.actors.remote.vehicle_state as VehicleCombatState).health == 1000, "异图相同坐标不受伤")
	module.advance_ticks(40, false)
	_expect(module.corrosion.is_empty(), "空图继续结清地面残留时钟")


## 验证同源刷新不无限叠伤、不饿死伤害时钟，且注销与死亡会清除附着。
func _test_refresh_and_lifecycle() -> void:
	var module := _fixture()
	var attack := {"attack_id": "refresh", "attacker_id": "gel", "combat_actor_id": "toxic_gel_cold",
		"map_instance_id": "map", "damage": 40}
	module.corrosion.add(CorrosiveCloud.new(attack, Vector2.ZERO, "p", 0, 20), 0)
	module.advance_ticks(19, false)
	module.corrosion.add(CorrosiveCloud.new(attack, Vector2.ZERO, "p", 19, 20), 19)
	module.advance_ticks(1, false)
	var state: VehicleCombatState = module.actors.p.vehicle_state
	_expect(state.health == 990 and module.snapshot_for_actor("p").corrosive_clouds.size() == 1, "刷新不叠层且原伤害时钟照常触发")
	module.corrosion.advance(20, module.actors)
	_expect(state.health == 990, "重复推进同tick不会重复扣血")
	module.unregister_vehicle("p")
	_expect(module.corrosion.is_empty(), "离图注销立即清理附着")
	module = _fixture()
	module.corrosion.add(CorrosiveCloud.new(attack, Vector2.ZERO, "p", 0, 20), 0)
	(module.actors.p.vehicle_state as VehicleCombatState).health = 5
	module.advance_ticks(20, false)
	_expect((module.actors.p.vehicle_state as VehicleCombatState).health == 0 and module.corrosion.is_empty(), "致死脉冲与附着一起结清")
	var death: Dictionary = module.combat_events[-1]
	_expect(death.has("death_id") and bool(death.get("corrosion_pulse", false)) \
		and death.get("attacker_display_name") == "低温毒胶", "真实毒雾致死保存来源与独立日志身份")
	var instance := AuthoritativeMapInstance.new()
	instance.navigation = RefCounted.new()
	instance.combat_module = module
	module.corrosion.add(CorrosiveCloud.new(attack, Vector2.ZERO, "", 20, 20), 20)
	_expect(not instance.can_suspend_runtime(), "地面残留未过期时不能冻结空图")
	module.advance_ticks(80, false)
	_expect(instance.can_suspend_runtime(), "残留结清后允许空图休眠")


## 验证所有毒胶目录、下发事件和权威推进同步采用原速度的四成。
func _test_spray_speed() -> void:
	var species_count := 0
	for id: String in catalog.monster_ids():
		var definition := catalog.monster_definition(id)
		if definition.combat.attack_archetype == "corrosive_projectile":
			species_count += 1
			_expect(is_equal_approx(float(definition.combat.runtime_projectile_speed), 400.0), "%s毒胶喷射速度为原1000的40%%" % id)
	_expect(species_count == 7, "覆盖普通、低温、恶性、仿生及三种变异毒胶")
	_expect(is_equal_approx(float(catalog.monster_definition("om_adult").combat.runtime_projectile_speed), 416.666667),
		"普通奥姆虫弹速不受毒胶调速影响")
	var module := _fixture()
	module._begin_monster_attack("gel", "p", Vector2(100, 0))
	var attack: Dictionary = module.combat_events.back()
	_expect(attack.projectile_speed == 400.0 and attack.impact_tick == 6, "权威开始事件下发降速后的预计到达时间")
	module.advance_ticks(1, false)
	var pending: Dictionary = module.pending_monster_attacks[0]
	_expect(is_equal_approx((pending.current_position as Vector2).distance_to(pending.origin), 20.0), "20Hz下每tick推进20像素")
	module.advance_ticks(1, false)
	_expect(module.corrosion.is_empty(), "降低速度后不会沿用原1000速度提前命中")
	_expect(CorrosiveCloud.DURATION_SECONDS >= 3.0, "地面与附着腐蚀至少保持三秒")


## 汇总业务断言。
## [param condition] 待验证条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
