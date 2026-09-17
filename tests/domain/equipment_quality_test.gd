extends SceneTree

var _checks := 0
var _failures := PackedStringArray()


## 覆盖每种品质、独立成长、保存、真实装配和制造随机边界。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "initialization")
	for id: String in catalog.quality_rules.profiles:
		var base: Equipment = catalog.create(id, {}).value
		var profile: EquipmentQualityRules.Profile = catalog.quality_rules.profiles[id]
		for grade in 4:
			var item: Equipment = catalog.create(id, {"instance_id": id, "equipment_quality": {"version": 1, "grade": grade}}).value
			for attr: String in profile.bonuses:
				_check(item.stat(attr) == base.stat(attr) + profile.bonuses[attr][grade], "original quality bonus " + id)
			var clone: Equipment = catalog.create(id, item.to_view_dictionary()).value
			_check(clone.quality.grade == grade and clone.to_view_dictionary().stats == item.to_view_dictionary().stats, "no double bonus " + id)
			if item is VehicleChassis: _check(item.base_max_health == int(item.stat("max_health")), "cached health")
			if item is VehicleEngine: _check(item.drive == int(item.stat("drive")), "cached drive")
			if item is VehicleWeapon: _check(item.base_attack == int(item.stat("base_attack")), "cached attack")
		for sample: Array in [[0.0, 0], [0.79999, 0], [0.8, 1], [0.94999, 1], [0.95001, 2], [0.98999, 2], [0.99001, 3], [0.99999, 3]]:
			_check(int(catalog.quality_rules.manufactured_state(id, sample[0]).get("grade", 0)) == sample[1], "quality distribution")
	for invalid: Variant in [1, [], {"grade": 1}, {"version": 2, "grade": 1}, {"version": 1, "grade": -1}, {"version": 1, "grade": 4}, {"version": 1, "grade": 1.5}, {"version": 1, "grade": INF}]:
		_check(not EquipmentQuality.restore(invalid).is_ok, "reject invalid state")
	_check(not catalog.create("iron_piece", {"equipment_quality": {"version": 1, "grade": 1}}).is_ok, "reject quality material")
	_check(catalog.create("recruit_tank", {}).value.quality.grade == 0, "old save white")
	_test_round_trip(catalog, fixture)
	_test_manufacturing(catalog, fixture)
	print("Equipment quality: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 验证背包和已装配品质往返后仍进入模拟属性。
## [param catalog] 实际物品目录。
## [param fixture] 隔离玩家模板。
func _test_round_trip(catalog: ItemCatalog, fixture: PlayerPanelServiceFixture) -> void:
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	var id := "glory_equipment_tank7_6dce9d1c52"
	var tank: Equipment = catalog.create(id, {"instance_id": "quality.tank", "equipment_quality": {"version": 1, "grade": 3}}).value
	player.vehicle.loadout.equip(tank, 0, player.vehicle.loadout.revision)
	var gun: Equipment = catalog.create("glory_equipment_gun8_e7ce1423fa", {"instance_id": "quality.gun", "equipment_quality": {"version": 1, "grade": 2}}).value
	_check(player.inventory.add_reward(gun).is_ok, "add quality weapon")
	player.vehicle.reconcile_loadout_state()
	var health := player.vehicle.max_health
	var record: PlayerStateRecord = mapper.to_record(player).value
	player = mapper.to_domain(PlayerStateRecord.from_dictionary(record.to_dictionary()).value).value
	_check(player.inventory.find("quality.gun").quality.grade == 2, "inventory save")
	_check(player.vehicle.loadout.at(0).quality.grade == 3 and player.vehicle.max_health == health, "equipped save")
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	var conditions: EquipmentConditionLoadout = loadout.assembly.equipment_condition.duplicate_loadout()
	_check(conditions._items["quality.tank"].base_max_health == tank.base_max_health, "simulation clone preserves quality")
	var projector := PlayerPanelProjector.new(catalog, {})
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(projector.build_bundle(player)), "client projection")


## 通过真实制造配方检查独立品质随机、实际材料消费和白色旧调用兼容。
## [param catalog] 实际物品目录。
## [param fixture] 隔离玩家模板。
func _test_manufacturing(catalog: ItemCatalog, fixture: PlayerPanelServiceFixture) -> void:
	var book := ManufacturingRecipeBook.new()
	_check(book.initialize(catalog).is_ok, "recipe book")
	var config: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json").value
	var recipe: ManufacturingRecipe
	for candidate: ManufacturingRecipe in book.recipes_for_station("equipment_manufacturing"):
		if candidate.product_definition_id == "glory_equipment_gun8_e7ce1423fa": recipe = candidate
	_check(recipe != null, "quality product acquirable")
	if recipe == null: return
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 500000)
	player.skills._state_for("manufacturing").level = 1000
	var serial := 0
	for requirement: Dictionary in recipe.materials:
		var count := int(requirement.quantity)
		while count > 0:
			var item: GameItem = catalog.create(requirement.definition_id, {"instance_id": "mat.%d" % serial}).value
			item.quantity = mini(count, item.max_stack)
			count -= item.quantity
			serial += 1
			_check(player.inventory.add_reward(item).is_ok, "recipe stock")
	var result := recipe.execute(player, catalog, "made", 0.0, config, 0.995)
	_check(result.is_ok and player.inventory.find("made").quality.grade == 3, "manufacture purple")
	_check(recipe.to_view_dictionary(player, catalog).quality_description.contains("复刻概率"), "probability transparent")


## 累计行为断言。
## [param condition] 期望值。
## [param label] 故障定位。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
