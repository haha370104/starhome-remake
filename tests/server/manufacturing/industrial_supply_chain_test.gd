extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const REFINING := {"硫": 150, "磷": 200, "钾": 250, "钛": 350, "钪": 450, "镁": 500, "钡": 550}
const ALLOYS := {"锌钛合金": 400, "钡镁合金": 600, "锌钡合金": 600, "钛铬合金": 400, "钪镁合金": 550, "镍锌合金": 300}
var items := ItemCatalog.new()
var book := ManufacturingRecipeBook.new()
var service := AuthoritativeManufacturingService.new()
var fixture := Fixture.new()
var failures: Array[String] = []
var checks := 0


## 等待内容包可挂载后验证真实提炼与制造事务。
func _initialize() -> void:
	call_deferred("_run")


## 验证全部新增配方的等级、精确材料消耗、隔离提交、重放与矿石到合金的连续加工。
func _run() -> void:
	_expect(items.initialize().is_ok and book.initialize(items).is_ok and service.initialize().is_ok and fixture.initialize().is_ok, "正式目录与服务初始化")
	var pictures: Array[Dictionary] = []
	for station: String in ["refining", "alloy"]:
		var expected: Dictionary = REFINING if station == "refining" else ALLOYS
		for name: String in expected:
			var recipe := _recipe(station, name)
			_expect(recipe != null, "生产设施登记：" + name)
			if recipe == null:
				continue
			_expect(recipe.required_skill_level == expected[name] and recipe.output_quantity == 1, "等级和一次产量：" + name)
			if station == "refining":
				_expect(recipe.materials.size() == 1 and recipe.materials[0].quantity == 10, "十矿炼一份：" + name)
			var state := _state_with_materials(recipe)
			state.character_skills[recipe.skill_id].level = int(expected[name]) - 1
			var before := state.to_dictionary()
			_expect(_craft(state, recipe).error_code == &"manufacturing.skill_insufficient" and state.to_dictionary() == before, "低一级拒绝且状态不变：" + name)
			state.character_skills[recipe.skill_id].level = int(expected[name])
			var queried := service.execute(state, {"type": "query_manufacturing", "station_id": station})
			_expect(queried.is_ok, "真实设施可查询：" + name)
			var result := _craft(state, recipe)
			_expect(result.is_ok, "达到门槛加工成功：" + name)
			if not result.is_ok:
				continue
			var next: PlayerStateRecord = result.value.candidate
			_expect(_quantity(next, recipe.product_definition_id) == 1 and _quantity(state, recipe.product_definition_id) == 0, "只在隔离候选中产出：" + name)
			for material: Dictionary in recipe.materials:
				_expect(_quantity(next, material.definition_id) == 1, "恰好消费配置材料：" + name)
			var replay := service.execute(next, {"type": "craft_recipe", "station_id": station,
				"recipe_id": recipe.recipe_id, "inventory_revision": state.inventory_revision})
			_expect(not replay.is_ok, "旧版本不能重放制作：" + name)
			var mapped: Player = PlayerStateMapper.new(items).to_domain(state).value
			mapped.inventory.restore_items([])
			var missing: PlayerStateRecord = PlayerStateMapper.new(items).to_record(mapped).value
			_expect(not _craft(missing, recipe).is_ok, "无材料不能凭空产出：" + name)
			if name != "镍锌合金":
				var visual := ItemPresentationTextureResolver.resolve(items.definition(recipe.product_definition_id).presentation)
				_expect(not visual.is_empty(), "产物复用原版可见图像：" + name)
				if not visual.is_empty():
					pictures.append({"name": name, "texture": visual.texture})
	for name: String in ALLOYS:
		_test_chain(_recipe("alloy", name))
	var daily := DailyActivityCatalog.new()
	_expect(daily.initialize(items).is_ok, "材料供应更新后佣兵目录可加载")
	var magnesium := items.definition_id_by_display_name("镁矿")
	_expect(daily.tasks.values().filter(func(task: MercenaryDefinition) -> bool: return task.target_id == magnesium).size() == 13, "镁矿投放自动开放原有13条收集任务")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(820, 500)
		for index in range(pictures.size()):
			var sprite := Sprite2D.new()
			sprite.texture = pictures[index].texture
			sprite.position = Vector2(100 + (index % 4) * 200, 70 + floori(index / 4.0) * 145)
			root.add_child(sprite)
			var label := Label.new()
			label.text = pictures[index].name
			label.position = sprite.position + Vector2(-55, 40)
			label.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_font.tres"))
			root.add_child(label)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/industrial-supply-products.png")
	for failure: String in failures:
		push_error(failure)
	print("INDUSTRIAL_SUPPLY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 用真实服务将各成分矿石先炼为金属，再沿同一候选存档制造合金。
## [param alloy] 当前需验证的合金配方。
func _test_chain(alloy: ManufacturingRecipe) -> void:
	var state := fixture._state.duplicate_record()
	state.inventory_stacks.clear()
	state.character_skills.refining.level = 600
	state.character_skills.manufacturing.level = 600
	for ingredient: Dictionary in alloy.materials:
		var refining := _recipe("refining", items.display_name(ingredient.definition_id))
		_expect(refining != null, "合金成分存在可执行提炼配方")
		if refining == null:
			return
		var mapper := PlayerStateMapper.new(items)
		var player: Player = mapper.to_domain(state).value
		for material: Dictionary in refining.materials:
			var created := items.create(material.definition_id, {"instance_id": "chain." + ingredient.definition_id, "quantity": material.quantity})
			_expect(created.is_ok and player.receive_loot(created.value).is_ok, "原矿可入包")
		state = mapper.to_record(player).value
		state.map_id = "glory_nft_bl_factory1"
		var refined := _craft(state, refining)
		_expect(refined.is_ok, "原矿经服务提炼为合金成分")
		if not refined.is_ok:
			return
		state = refined.value.candidate
	state.map_id = "glory_nft_bl_armshop1"
	var made := _craft(state, alloy)
	_expect(made.is_ok and _quantity(made.value.candidate, alloy.product_definition_id) == 1, "完整矿石到合金生产链：" + alloy.display_name)


## 按设施与名称查找唯一运行配方。
## [param station] 设施标识。
## [param name] 产物名。
## 返回目录中的配方，缺失时为空。
func _recipe(station: String, name: String) -> ManufacturingRecipe:
	for recipe: ManufacturingRecipe in book.recipes_for_station(station):
		if recipe.display_name == name:
			return recipe
	return null


## 创建材料比需求多一个的隔离角色，便于检查实际扣除数量。
## [param recipe] 即将验证的配方。
## 返回位于正确生产地图的存档。
func _state_with_materials(recipe: ManufacturingRecipe) -> PlayerStateRecord:
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.restore_items([])
	for material: Dictionary in recipe.materials:
		var created := items.create(material.definition_id, {"instance_id": material.definition_id, "quantity": int(material.quantity) + 1})
		_expect(created.is_ok and player.receive_loot(created.value).is_ok, "材料可进入权威背包")
	var state: PlayerStateRecord = mapper.to_record(player).value
	state.map_id = "glory_nft_bl_factory1" if recipe.station_id == "refining" else "glory_nft_bl_armshop1"
	return state


## 发送带干扰字段的制作意图，产量与门槛必须仍由服务器规则决定。
## [param state] 权威状态。
## [param recipe] 只提供配方身份。
## 返回服务事务结果。
func _craft(state: PlayerStateRecord, recipe: ManufacturingRecipe) -> DomainResult:
	return service.execute(state, {"type": "craft_recipe", "station_id": recipe.station_id, "recipe_id": recipe.recipe_id,
		"inventory_revision": state.inventory_revision, "quantity": 999, "required_skill_level": 0})


## 统计候选存档中某种物品总量。
## [param state] 权威存档。
## [param id] 物品定义。
## 返回所有堆叠的数量之和。
func _quantity(state: PlayerStateRecord, id: String) -> int:
	var total := 0
	for stack: InventoryStackRecord in state.inventory_stacks:
		if stack.item_definition_id == id:
			total += stack.quantity
	return total


## 累计业务行为断言。
## [param condition] 实际业务条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
