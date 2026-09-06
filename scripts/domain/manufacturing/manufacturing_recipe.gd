class_name ManufacturingRecipe
extends RefCounted

var recipe_id := ""
var station_id := ""
var display_name := ""
var product_definition_id := ""
var output_quantity := 1
var skill_id := ""
var required_skill_level := 0
var skill_experience := 1.0
var materials: Array[Dictionary] = []


## 从已经解析为稳定物品 ID 的配置创建配方领域对象。
## [param definition] 配方书产生的可信规范化定义。
func _init(definition: Dictionary = {}) -> void:
	recipe_id = String(definition.get("recipe_id", ""))
	station_id = String(definition.get("station_id", ""))
	display_name = String(definition.get("display_name", ""))
	product_definition_id = String(definition.get("product_definition_id", ""))
	output_quantity = maxi(1, int(definition.get("output_quantity", 1)))
	skill_id = String(definition.get("skill_id", ""))
	required_skill_level = maxi(0, int(definition.get("required_skill_level", 0)))
	skill_experience = maxf(1.0, float(definition.get("skill_experience", 1.0)))
	var material_value: Variant = definition.get("materials", [])
	if material_value is Array:
		for entry: Variant in material_value:
			if entry is Dictionary:
				materials.append((entry as Dictionary).duplicate(true))


## 判断本配方是否能出现在指定生产设施中。
## [param requested_station_id] 客户端当前交互的设施标识。
## 返回设施与配方是否匹配。
func belongs_to_station(requested_station_id: String) -> bool:
	return station_id == requested_station_id


## 计算当前有效技能等级下的单次成功率。
## [param effective_skill_level] 含人物装备加成的技能等级。
## 返回 0 到 1 的概率。
## 设计：裁缝为硬门槛；烹饪允许越级且每差一级降低 10%。
func success_probability(effective_skill_level: int) -> float:
	if station_id == "tailoring":
		return 1.0 if effective_skill_level >= required_skill_level else 0.0
	var missing_levels := maxi(0, required_skill_level - effective_skill_level)
	return clampf(1.0 - float(missing_levels) * 0.1, 0.0, 1.0)


## 由玩家聚合执行一次配方并结算材料、产物与技能经验。
## [param player] 当前权威事务中的充血 Player 聚合。
## [param item_catalog] 创建产物实例的受控物品目录。
## [param product_instance_id] 服务端生成的唯一产物实例 ID。
## [param random_roll] 服务端随机数，范围为 0 到 1。
## [param progression_config] 技能升级与综合等级规则。
## 返回成功/失败、消耗、产物和技能成长；预检拒绝时不修改玩家。
func execute(
	player: Player,
	item_catalog: ItemCatalog,
	product_instance_id: String,
	random_roll: float,
	progression_config: Dictionary,
) -> DomainResult:
	if player == null or item_catalog == null or recipe_id.is_empty():
		return DomainResult.failure(&"manufacturing.recipe_invalid", "recipe is unavailable")
	var effective_level := player.skills.effective_level(skill_id, player.character_equipment)
	var probability := success_probability(effective_level)
	if station_id == "tailoring" and probability <= 0.0:
		return DomainResult.failure(&"manufacturing.skill_insufficient", "tailoring level is insufficient")
	var succeeded := clampf(random_roll, 0.0, 1.0) < probability
	if not succeeded:
		var consumed := player.inventory.consume_requirements(materials)
		if not consumed.is_ok:
			return consumed
		return DomainResult.ok({
			"recipe_id": recipe_id,
			"succeeded": false,
			"success_probability": probability,
			"consumed": consumed.value,
		})
	var created := item_catalog.create(product_definition_id, {
		"instance_id": product_instance_id,
		"quantity": output_quantity,
		"container_id": "main",
		"position_px": [0, 0],
	})
	if not created.is_ok:
		return created
	var crafted := player.inventory.craft_product(materials, created.value)
	if not crafted.is_ok:
		return crafted
	var progression := player.grant_skill_experience(
		skill_id, skill_experience, progression_config
	)
	if not progression.is_ok:
		return progression
	return DomainResult.ok({
		"recipe_id": recipe_id,
		"succeeded": true,
		"success_probability": probability,
		"product_definition_id": product_definition_id,
		"output_quantity": output_quantity,
		"progression": progression.value,
	})


## 投影生产面板所需的只读配方状态。
## [param player] 用于计算材料持有量和有效技能等级的玩家聚合。
## [param item_catalog] 用于显示材料与产物名称的目录。
## 返回不含领域对象引用的网络安全字典。
func to_view_dictionary(player: Player, item_catalog: ItemCatalog) -> Dictionary:
	var material_views: Array[Dictionary] = []
	var ready := true
	for requirement: Dictionary in materials:
		var definition_id := String(requirement["definition_id"])
		var required := int(requirement["quantity"])
		var owned := player.inventory.count_consumable_definition(definition_id)
		ready = ready and owned >= required
		material_views.append({
			"definition_id": definition_id,
			"display_name": item_catalog.display_name(definition_id),
			"required": required,
			"owned": owned,
		})
	var effective_level := player.skills.effective_level(skill_id, player.character_equipment)
	var probability := success_probability(effective_level)
	return {
		"recipe_id": recipe_id,
		"station_id": station_id,
		"display_name": display_name,
		"product_definition_id": product_definition_id,
		"output_quantity": output_quantity,
		"skill_id": skill_id,
		"required_skill_level": required_skill_level,
		"effective_skill_level": effective_level,
		"skill_experience": skill_experience,
		"success_probability": probability,
		"can_craft": ready and probability > 0.0,
		"materials": material_views,
	}
