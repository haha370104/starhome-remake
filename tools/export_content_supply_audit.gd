extends SceneTree


## 导出真正初始化后的领域目录，供离线审计对照原始候选；不启动场景或读写玩家存档。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var daily := DailyActivityCatalog.new()
	var quests := RepeatableQuestCatalog.new()
	var book := ManufacturingRecipeBook.new()
	var combat_result := CombatDefinitionCatalog.load_default()
	if not items.initialize().is_ok or not daily.initialize(items).is_ok or not quests.initialize(items).is_ok \
			or not book.initialize(items).is_ok or not combat_result.is_ok:
		push_error("供应审计无法初始化权威目录")
		quit(1)
		return
	var combat: CombatDefinitionCatalog = combat_result.value
	var data := {"items": {}, "tasks": {}, "monsters": {}, "offers": [], "recipes": [],
		"item_aliases": ItemDefinitionAliases.LEGACY_TO_CANONICAL}
	for id: String in items.definition_ids():
		data.items[id] = items.definition(id)
	for id: String in daily.tasks:
		data.tasks[id] = daily.tasks[id].snapshot()
	for id: String in combat.monster_ids():
		data.monsters[id] = combat.monster_definition(id)
	for id: String in quests.providers:
		var merchant := WeaponMerchantCatalog.new()
		if not merchant.initialize(items, id).is_ok:
			push_error("供应审计无法初始化商人：" + id)
			quit(1)
			return
		data.offers.append_array(merchant.offers())
	var facilities: Dictionary = JsonConfigLoader.load_dictionary("res://data/world/manufacturing_facilities_v1.json").value
	var stations: Dictionary = {}
	for rows: Array in facilities.maps.values():
		for row: Dictionary in rows:
			stations[row.station_id] = true
	for station: String in stations:
		for recipe: RefCounted in book.recipes_for_station(station):
			data.recipes.append({"id": recipe.recipe_id, "product": recipe.product_definition_id,
				"materials": recipe.materials, "station": station})
	var file := FileAccess.open("res://.godot/content-audit-runtime.json", FileAccess.WRITE)
	if file == null:
		push_error("供应审计无法写入运行目录快照")
		quit(1)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	print("CONTENT_SUPPLY_EXPORT_OK tasks=%d" % daily.tasks.size())
	quit()
