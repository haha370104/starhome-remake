extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const FAMILIES := ["类胶", "能量催化剂", "四足甲的壳", "生物硅"]
const GRADES := ["低级", "中级", "高级"]
var checks := 0
var failures: Array[String] = []
var items := ItemCatalog.new()


## 等待场景就绪后验证掉落期望和真实升级事务。
func _initialize() -> void:
	call_deferred("_run")


## 验证每个物种材料相对等级、稀有物期望、七种产物和生产门槛。
func _run() -> void:
	_expect(items.initialize().is_ok, "物品目录初始化")
	var catalog: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var bindings := JsonConfigLoader.load_dictionary("res://data/gameplay/original_drop_bindings_v1.json").value as Dictionary
	var ids := {}
	for binding: Dictionary in bindings.definitions:
		ids[binding.source_class] = binding.item_definition_id
	var policy := JsonConfigLoader.load_dictionary("res://data/gameplay/drop_expectation_policy_v1.json").value as Dictionary
	var fixed := {}
	var expected_categories := {"挂机辅助卡": 0.05, "特制能量源": 0.01, "密度柔解剂": 0.1, "瑕疵晶石": 0.1, "装备强化材料": 0.1}
	for rule: Dictionary in policy.fixed_expectations:
		_expect(is_equal_approx(rule.expected_quantity, expected_categories[rule.category]), "分类期望符合用户数值")
		for source: String in rule.source_classes:
			fixed[ids[source]] = float(rule.expected_quantity)
	for species: String in catalog.monster_ids():
		var drops: Array = catalog.monster_definition(species).drops
		var by_name := {}
		for drop: Dictionary in drops:
			by_name[items.display_name(drop.item_definition_id)] = drop
			if fixed.has(drop.item_definition_id):
				_expect(is_equal_approx(_mean(drop), fixed[drop.item_definition_id]), "指定稀有物的每击杀数量期望")
				_expect(drop.minimum_quantity == 1 and drop.maximum_quantity == 1, "稀有物成功时只掉一个")
		for family: String in FAMILIES:
			var highest := -1
			for grade in range(GRADES.size()):
				if by_name.has(GRADES[grade] + family):
					highest = grade
			for grade in range(highest + 1):
				if not by_name.has(GRADES[grade] + family):
					continue
				var drop: Dictionary = by_name[GRADES[grade] + family]
				_expect(is_equal_approx(_mean(drop), 0.75 * pow(2.0, highest - grade)), "同怪同类材料每低一级期望翻倍")
				if grade == highest:
					_expect(drop.maximum_quantity <= 2, "当前最高级材料单次至多两个")
	var evil: Array = catalog.monster_definition("glory_monster_010").drops
	var table := DropTable.new(evil)
	var random := RandomNumberGenerator.new()
	random.seed = 20260916
	var totals := {}
	for _sample in range(40000):
		for result: Dictionary in table.roll(random):
			totals[result.item_definition_id] = int(totals.get(result.item_definition_id, 0)) + int(result.quantity)
	for entry: Dictionary in evil:
		_expect(absf(float(totals.get(entry.item_definition_id, 0)) / 40000.0 - _mean(entry)) < 0.04,
			"恶性感光质实际抽取的数量期望符合配置")
	_test_upgrades()
	for failure: String in failures:
		push_error(failure)
	print("DROP_EXPECTATIONS_UPGRADES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 计算一次击杀的数量期望，包含未掉落时的零数量。
## [param drop] 已验证的独立掉落规则。
## 返回概率乘以均匀数量区间的均值。
func _mean(drop: Dictionary) -> float:
	return float(drop.chance) * (int(drop.minimum_quantity) + int(drop.maximum_quantity)) / 2.0


## 验证七条真实配方在149级拒绝、150级扣五产一，并恢复可显示的存档物品。
func _test_upgrades() -> void:
	var fixture := Fixture.new()
	var service := AuthoritativeManufacturingService.new()
	var book := ManufacturingRecipeBook.new()
	_expect(fixture.initialize().is_ok and service.initialize().is_ok and book.initialize(items).is_ok, "权威生产服务初始化")
	var definitions := JsonConfigLoader.load_dictionary("res://data/gameplay/material_upgrade_recipes_v1.json").value as Dictionary
	_expect(definitions.recipes.size() == 7, "一条柔解剂提炼及六条同类晶石制造")
	var mapper := PlayerStateMapper.new(items)
	for definition: Dictionary in definitions.recipes:
		var recipe: ManufacturingRecipe = book.recipe(definition.recipe_id)
		_expect(recipe.required_skill_level == 150 and recipe.output_quantity == 1
			and recipe.materials.size() == 1 and recipe.materials[0].quantity == 5, "等级150且5比1")
		var player: Player = mapper.to_domain(fixture._state).value
		player.inventory.restore_items([])
		var ingredient := String(recipe.materials[0].definition_id)
		player.receive_loot(items.create(ingredient, {"instance_id": "upgrade.input", "quantity": 6}).value)
		var state: PlayerStateRecord = mapper.to_record(player).value
		state.map_id = "glory_nft_bl_factory1" if recipe.station_id == "refining" else "glory_nft_bl_armshop1"
		state.character_skills[recipe.skill_id].level = 149
		var command := {"type": "craft_recipe", "station_id": recipe.station_id,
			"recipe_id": recipe.recipe_id, "inventory_revision": state.inventory_revision}
		var before := state.to_dictionary()
		_expect(service.execute(state, command).error_code == &"manufacturing.skill_insufficient"
			and state.to_dictionary() == before, "149级拒绝且不扣材料")
		state.character_skills[recipe.skill_id].level = 150
		var result := service.execute(state, command)
		_expect(result.is_ok, "150级可执行提炼或制造")
		if not result.is_ok:
			continue
		var next: Player = mapper.to_domain(result.value.candidate).value
		_expect(next.inventory.count_definition(ingredient) == 1
			and next.inventory.count_definition(recipe.product_definition_id) == 1, "真实候选存档扣五产一")
		_expect(not service.execute(result.value.candidate, command).is_ok, "过期版本不得重复加工")
		var created: GameItem = items.create(recipe.product_definition_id, {"quantity": 1}).value
		var image := ItemPresentationTextureResolver.resolve(created.presentation_for("inventory"))
		_expect(not image.is_empty(), "产物恢复荣耀图像")
		_expect(not service.execute(result.value.candidate, {"type": "craft_recipe", "station_id": recipe.station_id,
			"recipe_id": recipe.recipe_id, "inventory_revision": result.value.candidate.inventory_revision}).is_ok,
			"不足五个不能继续升级")


## 累积业务断言，保留全部失败以便诊断。
## [param condition] 实际约束是否成立。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
