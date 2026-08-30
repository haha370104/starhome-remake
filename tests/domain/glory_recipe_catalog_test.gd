extends SceneTree

const CatalogScript := preload("res://scripts/domain/recipes/glory_recipe_catalog.gd")

var failures := PackedStringArray()
var assertions := 0


func _initialize() -> void:
	var catalog = CatalogScript.new()
	var initialized: Variant = catalog.initialize()
	_expect(initialized.is_ok, "荣耀配方目录应可加载")
	_expect(catalog.size() == 346, "应注册全部 346 条客户端配方证据")
	_expect(catalog.recipe_ids("local_crafting").size() == 123, "本地制作应为 123 条")
	_expect(catalog.recipe_ids("manufacturing").size() == 128, "制造应为 128 条")
	_expect(catalog.recipe_ids("equipment_upgrade").size() == 80, "强化应为 80 条")
	_expect(catalog.recipe_ids("equipment_dismantle").size() == 15, "分解应为 15 条")
	var cotton: Array[Dictionary] = catalog.find_by_product("合成棉")
	_expect(not cotton.is_empty(), "合成棉应可按产品名检索")
	if not cotton.is_empty():
		_expect(cotton[0].get("materials", []).size() == 2, "合成棉应保留两种原料")
		_expect(bool(cotton[0].get("settlement_ready", false)), "原料数量完整的本地制作可进入结算候选")
	var incomplete_count := 0
	for recipe_id: String in catalog.recipe_ids("manufacturing"):
		if not bool(catalog.recipe(recipe_id).get("settlement_ready", false)):
			incomplete_count += 1
	_expect(incomplete_count > 0, "缺少原料数量的客户端记录不得伪装为可结算配方")
	_finish()


func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("GLORY_RECIPE_CATALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)
