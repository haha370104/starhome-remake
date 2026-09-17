extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证全部星级装备的真实属性、实例隔离和持久化，不改写基础配置。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "initialize")
	for profile: EquipmentStrengtheningRules.Profile in items.strengthening_rules.profiles.values():
		var base: Equipment = items.create(profile.definition_id, {}).value
		var upgraded := items.create(profile.definition_id, {"instance_id": "test", "strengthening": {"level": 10}})
		_check(upgraded.is_ok and upgraded.value.stat(profile.attribute) == base.stat(profile.attribute) + profile.values[10], "final bonus " + profile.definition_id)
		var copy: Equipment = items.create(profile.definition_id, upgraded.value.to_view_dictionary()).value
		_check(copy.to_view_dictionary().stats == upgraded.value.to_view_dictionary().stats, "no duplicate bonus")
		if copy is VehicleChassis: _check(copy.base_max_health == int(copy.stat("max_health")), "chassis cache")
		if copy is VehicleWeapon: _check(copy.base_attack == int(copy.stat("base_attack")), "weapon cache")
		if copy is VehicleEngine: _check(copy.drive == int(copy.stat("drive")), "engine cache")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	var chassis := player.vehicle.loadout.at(0) as VehicleChassis
	var cannon := player.vehicle.loadout.at(1) as VehicleWeapon
	var spare: Equipment = player.inventory.find("inventory.spare_engine")
	var base_health := player.vehicle.max_health
	var base_attack := cannon.base_attack
	for item: Equipment in [chassis, cannon, spare]:
		item.strengthening.level = 10
		item.refresh_processed_stats()
	player.vehicle.reconcile_loadout_state()
	_check(player.vehicle.max_health == base_health + 600 and cannon.base_attack == base_attack + 55, "installed bonus")
	var record: PlayerStateRecord = mapper.to_record(player).value
	player = mapper.to_domain(PlayerStateRecord.from_dictionary(record.to_dictionary()).value).value
	_check(player.inventory.find(spare.instance_id).drive == 70 and player.vehicle.max_health == base_health + 600, "full save round trip")
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	_check(loadout.assembly.max_health == player.vehicle.max_health and loadout.weapons["energy_cannon.primary"].minimum_damage == base_attack + 55, "real assembly")
	var condition: EquipmentConditionLoadout = loadout.assembly.equipment_condition.duplicate_loadout()
	_check(condition._items[chassis.instance_id].base_max_health == chassis.base_max_health, "simulation cache survives clone")
	_check(not items.create("starter_rocket_launcher", {"strengthening": {"level": 1}}).is_ok, "forged incompatible growth rejected")
	print("Equipment strengthening integration: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言。
## [param condition] 当前结果。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
