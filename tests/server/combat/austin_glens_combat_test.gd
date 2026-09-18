extends SceneTree

var checks := 0
var failures := PackedStringArray()
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()


## 验证独立触发概率、固定减伤顺序、冷却、来源清理及真实怪物命中回执。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "dependencies")
	var player: Player = PlayerStateMapper.new(catalog).to_domain(fixture._state).value
	var mitigation: VehicleEquipment
	for id: String in catalog.austin_rules.profiles:
		var item := catalog.create(id, {"instance_id": id}).value as VehicleEquipment
		player.vehicle.loadout.equip(item, item.equipment_location, player.vehicle.loadout.revision)
		if item.austin_profile.effect == "mitigation": mitigation = item
	var activation := AustinDefenseActivation.new()
	_check(activation.claim(mitigation, 0, 20, 0.1) == 0, "exact ten-percent boundary fails")
	_check(activation.claim(mitigation, 0, 20, 0.099) == 20, "below threshold succeeds")
	_check(activation.claim(mitigation, 1199, 20, 0) == 0, "sixty seconds cooldown")
	activation.retain([mitigation.instance_id])
	_check(activation.claim(mitigation, 1, 20, 0) == 0, "refresh does not clear retained cooldown")
	_check(activation.claim(mitigation, 1200, 20, 0) == 20, "exact ready tick")
	activation.retain([])
	_check(activation.claim(mitigation, 1200, 20, 0) == 20, "departed source cleared")
	for roll: float in [NAN, INF, -0.1, 1.0]: _check(activation.claim(mitigation, 2400, 20, roll) == 0, "invalid roll")
	mitigation.durability = 0
	_check(activation.claim(mitigation, 2400, 20, 0) == 0, "broken equipment no trigger")
	mitigation.durability = mitigation.max_durability
	# Only this isolated catalog uses a certain trigger to inspect deterministic authority ordering.
	catalog.austin_rules.trigger_chance = 1.0
	var loadout: Dictionary = CombatDefinitionCatalog.load_default().value.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	var combat := AuthoritativeCombatModule.new()
	_check(combat.configure(20, 481, 0).is_ok, "combat initialize")
	_check(combat.register_vehicle("tester", "map.test", Vector2.ZERO, loadout.assembly, loadout.weapons).is_ok, "register actual loadout")
	var state := combat.actors.tester.vehicle_state as VehicleCombatState
	state.max_health = 1000
	state.health = 500
	var damage := state.preview_damage(100)
	_hit(combat, 100)
	var event: Dictionary = combat.combat_events.back()
	_check(event.damage == damage - 20 and state.health == 500 - damage + 40, "mitigation after defense then heal")
	_check(event.austin_effects.size() == 2 and event.target_health == state.health, "actual effects and final health in authoritative event")
	_check(not event.target_destroyed, "survived")
	var before := state.health
	_hit(combat, 100)
	_check(combat.combat_events.back().austin_effects.is_empty() and state.health == before - damage, "one activation per source per interval")
	_check(combat.refresh_achievement_loadout("tester", loadout).is_ok, "actual refresh")
	state.max_health = 1000
	state.health = 500
	_hit(combat, 100)
	_check(combat.combat_events.back().austin_effects.is_empty(), "combat refresh preserves cooldown")
	combat.current_tick = 1200
	state.health = 500
	_hit(combat, 0)
	_check(combat.combat_events.back().austin_effects.is_empty(), "zero damage never procs")
	_hit(combat, 10)
	_check(combat.combat_events.back().damage == 0 and state.health == 520, "full block floors at zero; surviving missing health can heal")
	combat.current_tick = 2400
	state.health = 1
	_hit(combat, 100)
	_check(state.health == 0 and combat.combat_events.back().target_destroyed, "healing cannot resurrect")
	_check(not combat.austin._activations.has("tester"), "death clears triggers")
	state.health = 500
	_hit(combat, 100)
	_check(combat.austin._activations.has("tester"), "new alive combat gets fresh triggers")
	combat.unregister_vehicle("tester")
	_check(not combat.austin._activations.has("tester"), "map leave clears triggers")
	var module := AuthoritativeAustinModule.new()
	module.reset(10)
	state.health = 500
	var empty := EquipmentConditionLoadout.new()
	_check(module.resolve_hit("empty", empty, state, 100, 0, 20).value.applied_damage == damage, "no equipment preserves legacy damage")
	var regular := VehicleCombatState.new()
	regular.max_health = 100
	regular.health = 100
	regular.defense = 200
	_check(regular.apply_damage(100, false, 20).value.applied_damage == 30, "fixed twenty comes after fifty-percent defense")
	_check(regular.apply_damage(10, true).value.applied_damage == 5, "corrosion baseline unchanged")
	print("Austin combat: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 把真实权威预约送入正式怪物命中入口，不从客户端传入装备结果。
## [param combat] 权威战斗模块。[param damage] 怪物基础伤害。
func _hit(combat: AuthoritativeCombatModule, damage: int) -> void:
	combat._resolve_monster_attack({"target_entity_id": "tester", "map_instance_id": "map.test", "damage": damage,
		"attack_archetype": "projectile", "attack_id": "attack.test", "attacker_id": "test.monster", "combat_actor_id": "test.monster"})


## 汇总权威战斗断言。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
