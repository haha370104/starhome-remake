extends SceneTree

var _checks: int = 0
var _failures: int = 0


## 验证原版上限、不同装备隔离和完整存档链路；不访问玩家真实存档。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "catalog")
	var tank: VehicleChassis = catalog.create("recruit_tank", {}).value
	var rules := catalog.processing_rules
	var profile := rules.profile(tank.definition_id)
	var material := rules.material("item:material:47b24f797e14")
	for index: int in 5:
		var result := tank.processing.apply(profile, material)
		_check(result.is_ok and result.value.points == (1 if index == 4 else 2), "last increment clamped")
	tank.refresh_processed_stats()
	_check(is_equal_approx(tank.output_power, 30.0), "output power reaches original cap")
	_check(not tank.processing.apply(profile, material).is_ok, "reject over cap")
	_check(tank.upgrade_level == 0, "not attachment levels")
	var snapshot := tank.to_view_dictionary()
	_check(snapshot.stats.output_power == 30, "view uses processed value")
	var restored: VehicleChassis = catalog.create(tank.definition_id, snapshot).value
	_check(restored.output_power == 30, "reload does not double increments")
	_check(not catalog.create("recruit_energy_cannon", snapshot).is_ok, "no cross equipment transfer")
	for invalid: Variant in [-1, 1.2, "2", INF, null, true, 1000001]:
		_check(not EquipmentProcessing.restore({"increments": {"drive": invalid}}).is_ok, "reject malformed increment")
	_check(not EquipmentProcessing.restore({"increments": {"invented": 1}}).is_ok, "reject unknown stat")
	_check(not EquipmentProcessing.restore({"version": 2}).is_ok, "reject future version")
	_check(not catalog.create("recruit_tank", {"processing": {"increments": {"max_health": 31}}}).is_ok, "reject excessive save")
	var gun: VehicleWeapon = catalog.create("recruit_energy_cannon", {"processing": {"increments": {"base_attack": 2, "range": 10}}}).value
	_check(gun.base_attack == 9 and gun.attack_range == 260, "gun uses attack and range increments")
	_check(gun.working_energy_per_shot == float(catalog.definition(gun.definition_id).stats.working_energy_per_shot), "energy cost unchanged")
	_test_persistence(catalog)
	print("Equipment processing model: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 检查所有规则可实例化且材料可解析，并验证已装配和背包两条保存路径。
## [param catalog] 正式目录。
func _test_persistence(catalog: ItemCatalog) -> void:
	for id: String in catalog.definition_ids():
		var profile := catalog.processing_rules.profile(id)
		if profile == null:
			continue
		var item: Equipment = catalog.create(id, {}).value
		for rule: EquipmentProcessingRules.AttributeRule in profile.attributes.values():
			if rule.attribute != "ammunition_capacity":
				_check(is_equal_approx(float(item.stat(rule.attribute)), rule.base), id + " base matches")
			for cost: Dictionary in rule.materials:
				_check(catalog.create(cost.definition_id, {}).is_ok, "recipe material exists")
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "fixture")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	var tank := player.vehicle.loadout.at(0)
	tank.processing.apply(catalog.processing_rules.profile(tank.definition_id), catalog.processing_rules.material("item:material:3481b7371d1e"))
	tank.refresh_processed_stats()
	var engine: Equipment = player.inventory.find("inventory.spare_engine")
	engine.processing.apply(catalog.processing_rules.profile(engine.definition_id), catalog.processing_rules.material("item:material:02212ea88168"))
	engine.refresh_processed_stats()
	var record := mapper.to_record(player)
	_check(record.is_ok, "persist record")
	var parsed := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(record.value.to_dictionary())))
	_check(parsed.is_ok, "JSON roundtrip")
	var restored: Player = mapper.to_domain(parsed.value).value
	_check((restored.vehicle.loadout.at(0) as VehicleChassis).base_max_health == 80, "equipped chassis persists")
	_check((restored.inventory.find(engine.instance_id) as VehicleEngine).drive == 22, "backpack engine persists")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(PlayerPanelProjector.new(catalog).build_bundle(restored)), "client accepts bundle")
	_check((current.vehicle.loadout.at(0) as VehicleChassis).base_max_health == 80, "client equipped processed stats")
	_check((current.inventory.find(engine.instance_id) as VehicleEngine).drive == 22, "client backpack processed stats")


## 记录独立边界断言。
## [param condition] 是否符合预期。
## [param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
