class_name DailyActivityCatalog
extends RefCounted

var policy: Dictionary
var tasks: Dictionary[String, MercenaryDefinition] = {}
var experience: Array[Dictionary] = []


## 加载原版任务并按当前启用刷怪、矿池和工业链过滤不可完成的目标。
## [param items] 已初始化的权威物品目录。
## 返回可执行目录或配置失败。
func initialize(items: ItemCatalog) -> DomainResult:
	tasks.clear()
	experience.clear()
	var settings := JsonConfigLoader.load_dictionary("res://data/gameplay/quests/daily_activities_v1.json")
	var source := JsonConfigLoader.load_dictionary("res://data/gameplay/quests/mercenary_tasks_v1.json")
	if not settings.is_ok or not source.is_ok:
		return DomainResult.failure(&"daily.config", "日常任务配置加载失败")
	policy = settings.value
	var monsters := JsonConfigLoader.load_dictionary("res://data/gameplay/glory/glory_monsters_v1.json").value as Dictionary
	var encounters := JsonConfigLoader.load_dictionary("res://data/gameplay/glory/glory_monster_encounters_v1.json").value as Dictionary
	var places: Dictionary = {}
	for encounter: Dictionary in encounters.encounters:
		if not bool(encounter.get("enabled", true)):
			continue
		for group: Dictionary in encounter.spawn_groups:
			if float(group.get("weight", 1.0)) <= 0:
				continue
			if not places.has(group.monster_id):
				places[group.monster_id] = []
			places[group.monster_id].append(encounter.map_id)
	var species_by_name: Dictionary = {}
	for monster: Dictionary in monsters.definitions:
		if places.has(monster.id):
			species_by_name[monster.display_name] = monster.id
	var available := _available_materials(items)
	for raw: Dictionary in source.value.tasks:
		var rule := MercenaryDefinition.new(raw, policy.rewards)
		if rule.kind == 1:
			rule.target_id = String(species_by_name.get(rule.title.trim_prefix("击杀"), ""))
			rule.locations = places.get(rule.target_id, []).duplicate()
			rule.description = "击杀 %d 只%s" % [rule.quantity, rule.title.trim_prefix("击杀")]
		elif rule.kind == 2:
			rule.target_id = "money" if String(raw.condition[1]) == "money" else String(available.get(String(raw.condition[1]), ""))
			# 原版地图提示与复刻布怪不同，收集任务明确允许既有物品。
			rule.description = "收集并交付 %d 个%s（可使用背包已有材料）" % [rule.quantity, rule.title.trim_prefix("收集")]
			if rule.is_currency_donation():
				rule.description = "捐赠 %d 星际币（交付时扣除金币余额）" % rule.quantity
		if not rule.target_id.is_empty():
			tasks[rule.id] = rule
	for raw: Dictionary in policy.experience:
		var row := raw.duplicate(true)
		row["target_id"] = String(species_by_name.get(String(row.title).trim_prefix("击杀"), ""))
		row["enabled"] = String(row.id) in ["8", "10"] or (String(row.id) in ["3", "5", "7"] and not row.target_id.is_empty())
		row["unavailable_reason"] = "对应活动或 BOSS 排名尚未开放" if not row.enabled else ""
		experience.append(row)
	if tasks.is_empty():
		return DomainResult.failure(&"daily.no_tasks", "没有可完成的佣兵任务")
	return DomainResult.ok(self)


## 从实际掉落、启用矿池和原料闭合的配方推导可获取材料，排除仅登记的旧物品。
## [param items] 当前物品定义目录。
## 返回中文名或原类名到实际产出 ID 的映射。
func _available_materials(items: ItemCatalog) -> Dictionary:
	var ids: Dictionary = {}
	var result: Dictionary = {}
	var drops := JsonConfigLoader.load_dictionary("res://data/gameplay/stage3/monsters_v1.json").value as Dictionary
	for monster: Dictionary in drops.definitions:
		for drop: Dictionary in monster.get("drops", []):
			if float(drop.get("chance", 0)) > 0:
				ids[drop.item_definition_id] = true
	var materials := JsonConfigLoader.load_dictionary("res://data/gameplay/monster_material_drops_v1.json").value as Dictionary
	for monster: Dictionary in materials.definitions:
		for drop: Dictionary in monster.drops:
			if float(drop.get("chance", 0)) > 0:
				ids[drop.item_definition_id] = true
	var mining := JsonConfigLoader.load_dictionary("res://data/gameplay/mining_v1.json").value as Dictionary
	var enabled: Dictionary = {}
	for map: Dictionary in mining.maps.values():
		if bool(map.get("enabled", false)):
			for mineral: Dictionary in map.mineral_pool:
				if float(mineral.get("weight", 0)) > 0:
					enabled[mineral.mineral_id] = true
	for mineral: Dictionary in mining.minerals:
		if enabled.has(mineral.id):
			ids[mineral.item_definition_id] = true
	var recipes: Array = JsonConfigLoader.load_dictionary("res://data/gameplay/industrial_recipes_v1.json").value.recipes
	for _pass in range(recipes.size()):
		var count := ids.size()
		for recipe: Dictionary in recipes:
			var ready := true
			for ingredient: Dictionary in recipe.materials:
				ready = ready and ids.has(ingredient.definition_id)
			if ready:
				ids[recipe.product_definition_id] = true
		if ids.size() == count:
			break
	for id: String in ids:
		var definition := items.definition(id)
		if not definition.is_empty():
			result[definition.display_name] = id
			var source_class := String(definition.get("source_class", definition.get("source_audit", {}).get("source_class", "")))
			if not source_class.is_empty():
				result[source_class] = id
	return result


## 只提供不超过玩家综合等级的任务，八档门槛属于复刻配置。
## [param level] 权威综合等级。
## 返回可抽取任务 ID。
func eligible(level: int) -> Array[String]:
	var result: Array[String] = []
	for task: MercenaryDefinition in tasks.values():
		if level >= int(policy.minimum_levels[task.grade - 1]):
			result.append(task.id)
	return result
