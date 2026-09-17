class_name ManufacturingBatch
extends RefCounted


## 按生产速度形成一轮材料用量，经验不跟随此倍率增加。
## [param recipe] 已加载的配方。
## [param speed] 一轮处理的份数，权威入口限制1～10。
## 返回独立的整轮耗材，不修改原配方。
static func requirements(recipe: ManufacturingRecipe, speed: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in recipe.materials:
		result.append({"definition_id": String(row.definition_id), "quantity": int(row.quantity) * speed})
	return result


## 结算一轮多份生产，成功率保持原配方且经验只发一次。
## [param recipe] 权威配方。
## [param player] 当前隔离玩家聚合。
## [param catalog] 创建具体产物的目录。
## [param identity] 本轮服务端随机身份前缀，首个实例保持此原值。
## [param random_roll] 一轮成功判定随机数。
## [param progression_config] 原有技能成长配置。
## [param quality_rolls] 每份产物独立品质随机数，数组长度等于1～10档速度。
## 返回本轮结果；拒绝时库存、技能和综合等级均不改变。
static func execute(recipe: ManufacturingRecipe, player: Player, catalog: ItemCatalog, identity: String,
		random_roll: float, progression_config: Dictionary, quality_rolls: Array[float]) -> DomainResult:
	if recipe == null or player == null or catalog == null or recipe.recipe_id.is_empty() or identity.is_empty() \
		or quality_rolls.is_empty() or quality_rolls.size() > 10 or not is_finite(random_roll):
		return DomainResult.failure(&"manufacturing.batch_invalid", "生产配方、速度或随机数无效")
	for roll: float in quality_rolls:
		if not is_finite(roll): return DomainResult.failure(&"manufacturing.batch_invalid", "生产品质随机数无效")
	var speed := quality_rolls.size()
	var probability := recipe.success_probability(player.skills.effective_level(recipe.skill_id, player.character_equipment))
	if recipe.station_id != "cooking" and probability <= 0.0:
		return DomainResult.failure(&"manufacturing.skill_insufficient", "生产技能等级不足")
	var succeeded := probability >= 1.0 or clampf(random_roll, 0.0, 1.0) < probability
	var products: Array[GameItem] = []
	if succeeded:
		var created := _products(recipe, catalog, identity, quality_rolls)
		if not created.is_ok: return created
		products = created.value
	var costs := requirements(recipe, speed)
	var prepared := InventoryCraftingBatch.prepare(player.inventory, costs, products)
	if not prepared.is_ok: return prepared
	# 同步预演只替换技能对象；恢复原引用后再提交，奖励切面失败不会留下半轮生产。
	var old_skills := player.skills
	var old_level := player.level
	var next_skills := old_skills
	var next_level := old_level
	var progression: DomainResult = DomainResult.ok({})
	if succeeded:
		player.skills = SkillBook.new(old_skills.to_dictionary())
		progression = player.grant_skill_experience(recipe.skill_id, recipe.skill_experience, progression_config, "manufacturing")
		next_skills = player.skills
		next_level = player.level
		player.skills = old_skills
		player.level = old_level
		if not progression.is_ok: return progression
	var committed := InventoryCraftingBatch.commit(player.inventory, prepared.value)
	if not committed.is_ok: return committed
	player.skills = next_skills
	player.level = next_level
	return DomainResult.ok({"recipe_id": recipe.recipe_id, "succeeded": succeeded, "speed": speed,
		"success_probability": probability, "consumed": costs, "product_definition_id": recipe.product_definition_id,
		"output_quantity": recipe.output_quantity * speed if succeeded else 0, "progression": progression.value,
		"quality_description": catalog.quality_rules.manufacturing_description(recipe.product_definition_id)})


## 为每份产物独立选择品质，超出单堆上限时拆成拥有独立身份的合法堆叠。
## [param recipe] 产品与基础产量定义。
## [param catalog] 已初始化目录。
## [param identity] 本轮唯一前缀。
## [param rolls] 每份的品质随机数。
## 返回独立产物；尚未加入背包。
static func _products(recipe: ManufacturingRecipe, catalog: ItemCatalog, identity: String, rolls: Array[float]) -> DomainResult:
	var products: Array[GameItem] = []
	for roll: float in rolls:
		var remaining := recipe.output_quantity
		while remaining > 0:
			if products.size() >= InventoryLayout.ITEM_LIMIT:
				return DomainResult.failure(&"inventory.no_space", "本轮产物超过背包容量，请降低生产速度")
			var id := identity if products.is_empty() else "%s.%d" % [identity, products.size()]
			var created := catalog.create(recipe.product_definition_id, {"instance_id": id,
				"equipment_quality": catalog.quality_rules.manufactured_state(recipe.product_definition_id, roll)})
			if not created.is_ok: return created
			var item: GameItem = created.value
			item.quantity = mini(remaining, item.max_stack)
			remaining -= item.quantity
			products.append(item)
	return DomainResult.ok(products)
