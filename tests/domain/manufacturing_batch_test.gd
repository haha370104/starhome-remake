extends SceneTree

const IRON := "item:material:8f615d2ef879"

var _checks := 0
var _failures: Array[String] = []
var _catalog := ItemCatalog.new()
var _config: Dictionary


## 验证批量生产的整轮原子性、原概率和经验切面，不运行真实账号。
func _initialize() -> void:
	_check(_catalog.initialize().is_ok, "目录")
	_config = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json").value
	_test_inventory_plan()
	_test_speed_and_quality()
	_test_rewards()
	_test_rejections()
	print("Manufacturing batch: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures: push_error(failure)
	quit(1 if not _failures.is_empty() else 0)


## 验证满包时先预演全部消耗和产出，多堆合并不修改任何未提交的引用。
func _test_inventory_plan() -> void:
	var inventory := Inventory.new(4)
	var source := _material("material", 20, 99)
	var first := _material("product", 95, 99, "first")
	var second := _material("product", 94, 99, "second")
	var engine: VehicleEngine = _catalog.create("beginner_engine", {"instance_id": "engine", "durability": 77}).value
	inventory.restore_items([source, first, second, engine])
	var products: Array[GameItem] = [_material("product", 9, 99, "new")]
	var costs: Array[Dictionary] = [{"definition_id": "material", "quantity": 10}]
	var prepared := InventoryCraftingBatch.prepare(inventory, costs, products)
	_check(prepared.is_ok and first.quantity == 95 and second.quantity == 94 and source.quantity == 20, "预演合并不修改输入")
	_check(InventoryCraftingBatch.commit(inventory, prepared.value).is_ok, "满包利用两堆剩余空间")
	_check(first.quantity == 99 and second.quantity == 99 and source.quantity == 10, "多堆精确合并")
	_check(inventory.find("engine") == engine and engine.durability == 77, "无关装备保持原实例及耐久")
	_check(not InventoryCraftingBatch.commit(inventory, prepared.value).is_ok, "不能重复提交")
	var before := _quantities(inventory)
	prepared = InventoryCraftingBatch.prepare(inventory, [{"definition_id": "material", "quantity": 1}], [_material("product", 1, 99, "overflow")])
	_check(not prepared.is_ok and _quantities(inventory) == before, "容量失败不消耗部分材料")
	var new_engine: GameItem = _catalog.create("beginner_engine", {"instance_id": "second.engine"}).value
	prepared = InventoryCraftingBatch.prepare(inventory, costs, [new_engine])
	_check(prepared.is_ok and source.quantity == 10, "消耗整堆腾出产物槽位")
	_check(not InventoryCraftingBatch.commit(Inventory.new(), prepared.value).is_ok, "拒绝跨库存计划")
	_check(InventoryCraftingBatch.commit(inventory, prepared.value).is_ok and inventory.find("material") == null and inventory.find("second.engine") == new_engine, "整堆置换")
	var revision := inventory.revision
	for output: GameItem in [_material("product", 1, 99, "engine"), _material("product", 100, 99, "large")]:
		_check(not InventoryCraftingBatch.prepare(inventory, [], [output]).is_ok and inventory.revision == revision, "非法产物无写入")
	var duplicate := _material("product", 1, 99, "same")
	_check(not InventoryCraftingBatch.prepare(inventory, [], [duplicate, duplicate]).is_ok, "产物之间身份不重复")
	first.locked = true
	second.bound = true
	prepared = InventoryCraftingBatch.prepare(inventory, [], [_material("product", 1, 99, "plain")])
	_check(not prepared.is_ok, "锁定或不同绑定不能借堆叠扩容")


## 对比一档和十档产量、材料、经验，并验证每件装备品质独立。
func _test_speed_and_quality() -> void:
	var single := _player()
	var multiple := _player()
	var recipe := _recipe("beginner_engine")
	var one := ManufacturingBatch.execute(recipe, single, _catalog, "one", 0, _config, [0.0])
	var rolls: Array[float] = []
	rolls.resize(10)
	rolls.fill(0.0)
	var ten := ManufacturingBatch.execute(recipe, multiple, _catalog, "ten", 0, _config, rolls)
	_check(one.is_ok and ten.is_ok, "一档十档均可完成：" + one.error_message + " / " + ten.error_message)
	if not one.is_ok or not ten.is_ok: return
	_check(single.inventory.count_definition("beginner_engine") == 1 and multiple.inventory.count_definition("beginner_engine") == 10, "产量乘速度")
	_check(single.inventory.count_definition(IRON) == 98 and multiple.inventory.count_definition(IRON) == 80, "材料乘速度")
	_check(single.skills.current_experience("manufacturing") == 7 and multiple.skills.current_experience("manufacturing") == 7, "经验不乘速度")
	_check(one.value.success_probability == ten.value.success_probability, "成功率不乘速度")
	var player := _player()
	recipe = _recipe("glory_equipment_gun8_e7ce1423fa")
	var result := ManufacturingBatch.execute(recipe, player, _catalog, "quality", 0, _config, [0.0, 0.85, 0.96, 0.995])
	_check(result.is_ok, "多品质装备")
	for index in range(4):
		var id := "quality" if index == 0 else "quality.%d" % index
		_check(player.inventory.find(id).quality.grade == index, "每件独立品质%d" % index)
	player = _player()
	recipe = _recipe(IRON)
	recipe.output_quantity = int(_catalog.create(IRON, {}).value.max_stack) + 3
	result = ManufacturingBatch.execute(recipe, player, _catalog, "stacked", 0, _config, [0.0])
	_check(result.is_ok and player.inventory.count_definition(IRON) == 98 + recipe.output_quantity, "超过一堆的产物分堆入账")
	for item: GameItem in player.inventory.items(): _check(item.quantity <= item.max_stack, "合法堆叠上限")
	player = _player()
	recipe = _recipe("beginner_engine")
	recipe.station_id = "cooking"
	recipe.skill_id = "cooking"
	recipe.required_skill_level = 5
	result = ManufacturingBatch.execute(recipe, player, _catalog, "failed", 0.9, _config, [0.0, 0.0])
	_check(result.is_ok and not result.value.succeeded and is_equal_approx(result.value.success_probability, 0.5), "保留烹饪越级概率")
	_check(player.inventory.count_definition(IRON) == 96 and player.inventory.count_definition("beginner_engine") == 0, "失败轮只消耗对应速度材料")
	_check(player.skills.current_experience("cooking") == 0, "原失败规则无经验")


## 覆盖背包满、材料不足、经验无效与随机输入异常的完整回滚。
func _test_rejections() -> void:
	var player := _player()
	var recipe := _recipe("beginner_engine")
	player.inventory.capacity = 2
	var before := _quantities(player.inventory)
	var skills := player.skills
	var result := ManufacturingBatch.execute(recipe, player, _catalog, "full", 0, _config, [0.0, 0.0])
	_check(not result.is_ok and _quantities(player.inventory) == before and player.skills == skills, "多产物满包时技能库存都不改变")
	player.inventory.capacity = 40
	result = ManufacturingBatch.execute(recipe, player, _catalog, "bad.exp", 0, {}, [0.0])
	_check(not result.is_ok and _quantities(player.inventory) == before and player.skills == skills and player.level == 10, "经验结算失败不扣料且保留技能原引用")
	_check(not ManufacturingBatch.execute(recipe, player, _catalog, "invalid", 0, _config, []).is_ok, "拒绝无效速度")
	_check(not ManufacturingBatch.execute(recipe, player, _catalog, "invalid", 0, _config, [NAN]).is_ok, "拒绝无效品质")
	_check(not ManufacturingBatch.execute(recipe, player, _catalog, "invalid", NAN, _config, [0.0]).is_ok, "拒绝无效概率")
	var overflow: Array[float] = []
	overflow.resize(11)
	overflow.fill(0.0)
	_check(not ManufacturingBatch.execute(recipe, player, _catalog, "invalid", 0, _config, overflow).is_ok, "最多十档")
	player.inventory.items()[0].locked = true
	result = ManufacturingBatch.execute(recipe, player, _catalog, "locked", 0, _config, [0.0])
	_check(not result.is_ok and _quantities(player.inventory) == before, "锁定材料不可消耗")


## 验证食品与账号规则仍从同一经验切面结算，倍率溢出也不留下半轮材料变化。
func _test_rewards() -> void:
	var player := _player()
	player.account_id = "batch.account"
	var now := int(Time.get_unix_time_from_system())
	player.food_status = FoodStatus.new({"active": [{"kind": FoodEffect.SKILLS.find("manufacturing"), "amount": 20, "expires_at": now + 100}]})
	player.reward_pipeline = RewardPolicyLoader.from_document({"schema_version": 1, "rules": [
		{"id": "vip.production", "channel": "experience", "multiplier": 2,
		"account_ids": ["batch.account"], "skill_ids": ["manufacturing"], "sources": ["manufacturing"]}]}).value
	var result := ManufacturingBatch.execute(_recipe("beginner_engine"), player, _catalog, "boosted", 0, _config, [0.0, 0.0, 0.0])
	_check(result.is_ok and is_equal_approx(result.value.progression.granted_experience, 16.8), "食品和账号倍率只作用于一轮原经验")
	_check(player.skills.current_experience("manufacturing") == 16, "实际入账而非只显示倍率")
	player.reward_pipeline = RewardPolicyLoader.from_document({"schema_version": 1, "rules": [
		{"id": "overflow", "channel": "experience", "multiplier": 1e308}]}).value
	var before := _quantities(player.inventory)
	var skills := player.skills
	result = ManufacturingBatch.execute(_recipe("beginner_engine"), player, _catalog, "no.reward", 0, _config, [0.0])
	_check(not result.is_ok and result.error_code == &"reward.overflow", "切面溢出拒绝")
	_check(_quantities(player.inventory) == before and player.skills == skills, "切面失败原子回滚")


## 创建真实物品目录支持的隔离人物和100个铁。
## 返回没有真实存档路径的测试聚合。
func _player() -> Player:
	var player := Player.new({"character_id": "batch.test", "level": 10, "skills": {"manufacturing": 100, "cooking": 0}})
	var remaining := 100
	var serial := 0
	while remaining > 0:
		var item: GameItem = _catalog.create(IRON, {"instance_id": "iron.%d" % serial}).value
		item.quantity = mini(remaining, item.max_stack)
		remaining -= item.quantity
		serial += 1
		_check(player.inventory.add_reward(item).is_ok, "测试材料入包")
	return player


## 构造可控的测试配方，物品仍由正式目录创建。
## [param product] 产物稳定定义。
## 返回每份消耗两个铁、奖励七经验的配方。
func _recipe(product: String) -> ManufacturingRecipe:
	return ManufacturingRecipe.new({"recipe_id": "test.batch", "station_id": "equipment_manufacturing",
		"product_definition_id": product, "skill_id": "manufacturing", "required_skill_level": 10,
		"skill_experience": 7, "materials": [{"definition_id": IRON, "quantity": 2}]})


## 创建只用于库存预演的通用材料。
## [param definition] 测试定义。
## [param quantity] 实例数量。
## [param maximum] 最大堆叠。
## [param id] 可选实例身份。
## 返回独立测试材料。
func _material(definition: String, quantity: int, maximum: int, id: String = "") -> GameItem:
	return GameItem.new({"id": definition, "max_stack": maximum}, {"instance_id": id if not id.is_empty() else definition, "quantity": quantity})


## 读取库存数量及版本用于失败前后对比，不触碰实例。
## [param inventory] 当前测试库存。
## 返回稳定数量快照。
func _quantities(inventory: Inventory) -> Dictionary:
	var values := {"revision": inventory.revision}
	for item: GameItem in inventory.items(): values[item.instance_id] = item.quantity
	return values


## 累计领域不变量断言。
## [param condition] 预期条件。
## [param label] 故障定位。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
