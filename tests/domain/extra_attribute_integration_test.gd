extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证完整装备目录、派生属性、装配、弹仓及存档，不允许累加保存导致重复强化。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "initialize")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay/extra_attribute_rules_v1.json"))
	for row: Dictionary in data.equipment:
		var levels := {}
		for channel: String in row.channels: levels[channel] = items.extra_attribute_rules.channels[channel].maximum
		var enhanced := items.create(row.definition_id, {"instance_id": "enhanced", "extra_attributes": {"levels": levels}})
		_check(enhanced.is_ok, "catalog validates " + row.definition_id)
		if not enhanced.is_ok: continue
		var item: Equipment = enhanced.value
		var copy: Equipment = items.create(row.definition_id, item.to_view_dictionary()).value
		_check(copy.to_view_dictionary().stats == item.to_view_dictionary().stats, "derived stats stable " + row.definition_id)
		_check(copy.magazine.remaining == copy.ammunition_capacity(), "new or legacy magazine initialized against full derived capacity")
		if item is VehicleWeapon: _check(item.base_attack == int(item.stat("base_attack")), "weapon cache refreshed")
		if item is VehicleChassis: _check(item.base_max_health == int(item.stat("max_health")), "chassis cache refreshed")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	var old_stats := player.vehicle.calculate_stats()
	var engine: Equipment = player.vehicle.loadout.at(3)
	var chassis: Equipment = player.vehicle.loadout.at(0)
	chassis.extra_attributes.apply(chassis.definition_id, items.extra_attribute_rules.material("extra_lifefluorite"), items.extra_attribute_rules, 0)
	chassis.extra_attributes.apply(chassis.definition_id, items.extra_attribute_rules.material("extra_recoveryfluorite"), items.extra_attribute_rules, 0)
	chassis.refresh_processed_stats()
	engine.extra_attributes.apply(engine.definition_id, items.extra_attribute_rules.material("extra_ratefluorite"), items.extra_attribute_rules, 0)
	engine.refresh_processed_stats()
	player.vehicle.reconcile_loadout_state()
	var stats := player.vehicle.calculate_stats()
	_check(stats.max_health == old_stats.max_health + 15 and stats.defense == old_stats.defense + 1, "health and defense equipped")
	_check(stats.propulsion == old_stats.propulsion and stats.speed == old_stats.speed + 1, "speed is final speed, not drive")
	var rocket: Equipment = items.create("starter_rocket_launcher", {"instance_id": "rocket", "extra_attributes": {"levels": {"fluorite:7": 2}}, "magazine": {"remaining": 117}}).value
	player.vehicle.loadout.restore(rocket)
	var spare: Equipment = player.inventory.find("inventory.spare_engine")
	spare.extra_attributes.apply(spare.definition_id, items.extra_attribute_rules.material("extra_ratefluorite"), items.extra_attribute_rules, 0)
	var record: PlayerStateRecord = mapper.to_record(player).value
	var saved_stats := player.vehicle.calculate_stats()
	for index: int in 3:
		player = mapper.to_domain(PlayerStateRecord.from_dictionary(record.to_dictionary()).value).value
		record = mapper.to_record(player).value
		_check(player.vehicle.calculate_stats() == saved_stats, "unchanged fields after save")
		_check(player.inventory.find(spare.instance_id).extra_attributes.level("fluorite:5") == 1, "backpack facts retained")
		_check(player.vehicle.loadout.at(0).extra_attributes.level("fluorite:3") == 1, "installed facts retained")
		_check(player.vehicle.loadout.at(13).ammunition_capacity() == 120 and player.vehicle.loadout.at(13).magazine.remaining == 117, "extra capacity round trip")
	var condition := EquipmentConditionLoadout.new(player).duplicate_loadout()
	_check(condition.ammunition_for("rocket") == {"remaining": 117, "capacity": 120}, "simulation clone retains growth")
	condition.accept_shot("rocket")
	_check(condition.ammunition_for("rocket").remaining == 116 and player.vehicle.loadout.at(13).magazine.remaining == 117, "independent simulation")
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var movement := {"base_speed_multiplier": 1500, "base_speed_cap": 240}
	var loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, movement).value
	_check(loadout.assembly.max_health == player.vehicle.max_health and loadout.assembly.defense == player.vehicle.calculate_stats().defense, "runtime health defense agree")
	var gun_id := ""
	for row: Dictionary in data.equipment:
		if "fluorite:2" in row.channels: gun_id = row.definition_id; break
	var gun: Equipment = items.create(gun_id, {"instance_id": "critical_gun", "extra_attributes": {"levels": {"fluorite:2": 20}}}).value
	_check(player.vehicle.loadout.equip(gun, 1, player.vehicle.loadout.revision).is_ok, "replace primary weapon")
	loadout = combat.vehicle_combat_loadout(player, 20, movement).value
	var module := AuthoritativeCombatModule.new()
	module.configure(20, 7)
	module.register_vehicle(player.entity_id, "test", Vector2.ZERO, loadout.assembly, loadout.weapons)
	var weapon: Dictionary = module.actors[player.entity_id].weapons["energy_cannon.primary"]
	_check(is_equal_approx(weapon.double_damage_chance, 0.05), "real actor preserves double chance")
	weapon.critical_chance = 0.1
	weapon.critical_multiplier = 1.5
	_check(VehicleCrystalHit.resolve_extra(100, weapon, 0, 0) == 200, "both effects choose double, no triple damage")
	_check(VehicleCrystalHit.resolve_extra(100, weapon, 0, 0.05) == 150, "double probability boundary")
	_check(VehicleCrystalHit.resolve_extra(100, weapon, 0.1, 0.05) == 100, "both miss")
	weapon.skill_id = "missile"
	_check(VehicleCrystalHit.resolve_extra(100, weapon, 0, 0) == 100, "no energy cannon effect on secondary")
	_check(not items.create("recruit_energy_cannon", {"extra_attributes": {"levels": {"fluorite:2": 1}}}).is_ok, "forged incompatible growth rejected")
	print("Extra attribute integration: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言。
## [param condition] 当前检查。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
