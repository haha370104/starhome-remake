class_name ManufacturingRecipeBook
extends RefCounted

const GloryRecipeCatalogScript := preload("res://scripts/domain/recipes/glory_recipe_catalog.gd")
const ManufacturingRecipeScript := preload(
	"res://scripts/domain/manufacturing/manufacturing_recipe.gd"
)

var _recipes_by_id: Dictionary = {}
var _recipe_ids_by_station: Dictionary = {}


## 从荣耀配方证据和稳定物品目录组装生活技能与工业配方。
## [param item_catalog] 已完成初始化的共享物品目录。
## 返回可执行配方书；无法解析的证据行会被安全排除而不会生成伪物品。
## 设计：原始类名和目录结构止于本适配器，领域配方只保存业务设施与稳定物品 ID。
func initialize(item_catalog: ItemCatalog) -> DomainResult:
	_recipes_by_id.clear()
	_recipe_ids_by_station.clear()
	if item_catalog == null:
		return DomainResult.failure(&"manufacturing.catalog_missing", "item catalog is missing")
	var glory_catalog := GloryRecipeCatalogScript.new()
	var loaded := glory_catalog.initialize()
	if not loaded.is_ok:
		return loaded
	for recipe_id: String in glory_catalog.recipe_ids():
		var source := glory_catalog.recipe(recipe_id)
		var station_id := _station_for(source)
		if station_id.is_empty():
			continue
		var normalized := _normalize(source, station_id, item_catalog)
		if normalized.is_empty():
			continue
		var recipe_model = ManufacturingRecipeScript.new(normalized)
		_recipes_by_id[recipe_model.recipe_id] = recipe_model
		var station_ids: PackedStringArray = _recipe_ids_by_station.get(
			station_id, PackedStringArray()
		)
		station_ids.append(recipe_model.recipe_id)
		_recipe_ids_by_station[station_id] = station_ids
	var industrial := JsonConfigLoader.load_dictionary("res://data/gameplay/industrial_recipes_v1.json")
	if not industrial.is_ok:
		return industrial
	var upgrades := JsonConfigLoader.load_dictionary("res://data/gameplay/material_upgrade_recipes_v1.json")
	if not upgrades.is_ok:
		return upgrades
	var definitions: Array = industrial.value.get("recipes", []).duplicate(true)
	definitions.append_array(upgrades.value.get("recipes", []))
	for definition: Dictionary in definitions:
		var model = ManufacturingRecipeScript.new(definition)
		if _recipes_by_id.has(model.recipe_id) or item_catalog.definition(model.product_definition_id).is_empty():
			return DomainResult.failure(&"manufacturing.catalog_invalid", "duplicate recipe or unknown industrial product")
		for requirement: Dictionary in model.materials:
			if item_catalog.definition(String(requirement.get("definition_id", ""))).is_empty() \
					or int(requirement.get("quantity", 0)) <= 0:
				return DomainResult.failure(&"manufacturing.catalog_invalid", "invalid industrial material")
		_recipes_by_id[model.recipe_id] = model
		var ids: PackedStringArray = _recipe_ids_by_station.get(model.station_id, PackedStringArray())
		ids.append(model.recipe_id)
		_recipe_ids_by_station[model.station_id] = ids
	return DomainResult.ok(self)


## 按稳定配方 ID 查询充血配方对象。
## [param recipe_id] 生产面板提交的配方标识。
## 返回配方；不存在时返回 null。
func recipe(recipe_id: String) -> RefCounted:
	return _recipes_by_id.get(recipe_id)


## 列出指定设施按等级、名称稳定排序的配方对象。
## [param station_id] 裁缝、烹饪、提炼或工业制造设施标识。
## 返回独立数组，调用方不能修改配方书索引。
func recipes_for_station(station_id: String) -> Array[RefCounted]:
	var result: Array[RefCounted] = []
	for recipe_id: String in _recipe_ids_by_station.get(station_id, PackedStringArray()):
		result.append(_recipes_by_id[recipe_id])
	result.sort_custom(func(a: RefCounted, b: RefCounted) -> bool:
		if a.required_skill_level != b.required_skill_level:
			return a.required_skill_level < b.required_skill_level
		return a.display_name < b.display_name
	)
	return result


## 根据荣耀来源证据把配方映射到业务设施。
## [param source] GloryRecipeCatalog 的规范化记录。
## 返回 tailoring、cooking 或空字符串。
func _station_for(source: Dictionary) -> String:
	var group := String(source.get("group", ""))
	var source_file := String(source.get("source_file", ""))
	if group == "manufacturing" and "sewlist" in source_file:
		return "tailoring"
	if group == "local_crafting":
		var product_name := String(source.get("product_name", ""))
		if not product_name.begins_with("合成") and product_name != "玻璃酒瓶" \
				and not product_name.begins_with("String") and not product_name.begins_with("test"):
			return "cooking"
	return ""


## 把中文材料名和产物名解析为稳定物品定义，形成领域配方构造参数。
## [param source] 已归类的荣耀配方记录。
## [param station_id] 业务设施标识。
## [param item_catalog] 显示名到稳定 ID 的旧内容适配边界。
## 返回完整规范化定义；任一名称无法解析时返回空字典。
func _normalize(
	source: Dictionary,
	station_id: String,
	item_catalog: ItemCatalog,
) -> Dictionary:
	var product_name := String(source.get("product_name", "")).strip_edges()
	var product_id := item_catalog.definition_id_by_display_name(product_name)
	if product_id.is_empty():
		return {}
	var requirements: Array[Dictionary] = []
	for material_value: Variant in source.get("materials", []):
		if not material_value is Dictionary:
			return {}
		var material: Dictionary = material_value
		var material_name := String(material.get("name", "")).strip_edges()
		var material_id := item_catalog.definition_id_by_display_name(material_name)
		if material_id.is_empty():
			return {}
		requirements.append({
			"definition_id": material_id,
			"quantity": int(material.get("amount", 0)),
		})
	return {
		"recipe_id": String(source.get("id", "")),
		"station_id": station_id,
		"display_name": product_name,
		"product_definition_id": product_id,
		"output_quantity": int(source.get("output_amount", 1)),
		"skill_id": station_id,
		"required_skill_level": int(source.get("required_skill_level", 10)),
		"skill_experience": float(source.get("skill_experience", 1)),
		"materials": requirements,
	}
