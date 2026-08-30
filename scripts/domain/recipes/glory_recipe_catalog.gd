class_name GloryRecipeCatalog
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const DEFAULT_PATH := "res://data/gameplay/glory/glory_recipes_v1.json"
const GROUP_ORDER := [
	"local_crafting",
	"manufacturing",
	"equipment_upgrade",
	"equipment_dismantle",
]

var content_version := ""
var execution_status := ""
var _by_id: Dictionary = {}
var _ids_by_group: Dictionary = {}
var _ids_by_product_key: Dictionary = {}


## 加载荣耀客户端恢复出的全部制作、强化与分解证据。
## [param path] 调用方传入的 `path` 参数。
## 返回该函数计算、查询或操作得到的结果。
func initialize(path := DEFAULT_PATH) -> DomainResult:
	_by_id.clear()
	_ids_by_group.clear()
	_ids_by_product_key.clear()
	if not FileAccess.file_exists(path):
		return DomainResult.failure(&"recipes.catalog_missing", "Glory recipe catalog is missing")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		return DomainResult.failure(&"recipes.catalog_invalid", "Glory recipe catalog is invalid")
	content_version = String(parsed.get("content_version", ""))
	execution_status = String(parsed.get("execution_status", ""))
	var groups: Variant = parsed.get("groups", {})
	if content_version.is_empty() or not groups is Dictionary:
		return DomainResult.failure(&"recipes.catalog_invalid", "Glory recipe groups are invalid")
	for group_name: String in GROUP_ORDER:
		var rows: Variant = groups.get(group_name, [])
		if not rows is Array:
			return DomainResult.failure(&"recipes.catalog_invalid", "Glory recipe group is invalid")
		var group_ids := PackedStringArray()
		for index: int in range(rows.size()):
			if not rows[index] is Dictionary:
				return DomainResult.failure(&"recipes.catalog_invalid", "Glory recipe row is invalid")
			var recipe := _normalize(group_name, index, rows[index])
			var recipe_id := String(recipe["id"])
			_by_id[recipe_id] = recipe
			group_ids.append(recipe_id)
			_index_product_key(String(recipe.get("product_class", "")), recipe_id)
			_index_product_key(String(recipe.get("product_name", "")), recipe_id)
		_ids_by_group[group_name] = group_ids
	return DomainResult.ok(self)


## 执行 `size` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func size() -> int:
	return _by_id.size()


## 执行 `recipe` 对应的模块操作。
## [param recipe_id] 调用方传入的 `recipe_id` 参数。
## 返回该函数计算、查询或操作得到的结果。
func recipe(recipe_id: String) -> Dictionary:
	var value: Variant = _by_id.get(recipe_id)
	return value.duplicate(true) if value is Dictionary else {}


## 执行 `recipe_ids` 对应的模块操作。
## [param group_name] 调用方传入的 `group_name` 参数。
## 返回该函数计算、查询或操作得到的结果。
func recipe_ids(group_name := "") -> PackedStringArray:
	if not group_name.is_empty():
		return PackedStringArray(_ids_by_group.get(group_name, PackedStringArray()))
	var result := PackedStringArray()
	for group: String in GROUP_ORDER:
		result.append_array(PackedStringArray(_ids_by_group.get(group, PackedStringArray())))
	return result


## 按客户端产品类名或显示名返回全部候选，避免同名赠品/普通品被覆盖。
## [param product_key] 调用方传入的 `product_key` 参数。
## 返回该函数计算、查询或操作得到的结果。
func find_by_product(product_key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for recipe_id: String in _ids_by_product_key.get(product_key.strip_edges().to_lower(), PackedStringArray()):
		result.append(recipe(recipe_id))
	return result


## 执行 `normalize` 对应的模块操作。
## [param group_name] 调用方传入的 `group_name` 参数。
## [param index] 调用方传入的 `index` 参数。
## [param source] 调用方传入的 `source` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _normalize(group_name: String, index: int, source: Dictionary) -> Dictionary:
	var result := source.duplicate(true)
	result["id"] = "glory_recipe_%s_%03d" % [group_name, index + 1]
	result["group"] = group_name
	result["source_release"] = "starhome_lz_ry"
	match group_name:
		"local_crafting":
			result["product_class"] = String(source.get("class_name", ""))
			result["product_name"] = String(source.get("display_name", ""))
			result["materials"] = _parse_embedded_materials(String(source.get("materials_json", "")))
		"manufacturing":
			result["product_class"] = String(source.get("product_class", ""))
			result["product_name"] = String(source.get("product_name", ""))
			result["materials"] = _dictionary_array(source.get("materials", []))
			result["required_skill_level"] = int(String(source.get("need_skill", "0")))
			result["skill_experience"] = int(String(source.get("get_point", "0")))
			result["output_amount"] = maxi(1, int(String(source.get("get_amount", "1"))))
		"equipment_upgrade":
			result["product_class"] = String(source.get("UpObjCName", ""))
			result["product_name"] = String(source.get("EquipmentName", ""))
			result["required_skill_level"] = int(String(source.get("NeedSkill", "0")))
		"equipment_dismantle":
			result["product_class"] = String(source.get("ProductClass", ""))
			result["product_name"] = String(source.get("EquipmentName", ""))
			result["minimum_quality"] = int(String(source.get("LowestQuality", "0")))
	result["settlement_ready"] = _settlement_ready(group_name, result)
	return result


## 执行 `settlement_ready` 对应的模块操作。
## [param group_name] 调用方传入的 `group_name` 参数。
## [param recipe] 调用方传入的 `recipe` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _settlement_ready(group_name: String, recipe: Dictionary) -> bool:
	if group_name in ["equipment_upgrade", "equipment_dismantle"]:
		return false
	var materials: Variant = recipe.get("materials", [])
	if not materials is Array or materials.is_empty():
		return false
	for material: Variant in materials:
		if not material is Dictionary or not material.has("amount") or int(material["amount"]) <= 0:
			return false
	return not String(recipe.get("product_class", "")).is_empty()


## 执行 `parse_embedded_materials` 对应的模块操作。
## [param encoded] 调用方传入的 `encoded` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _parse_embedded_materials(encoded: String) -> Array[Dictionary]:
	var parsed: Variant = JSON.parse_string(encoded)
	return _dictionary_array(parsed)


## 执行 `dictionary_array` 对应的模块操作。
## [param value] 调用方传入的 `value` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for entry: Variant in value:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


## 执行 `index_product_key` 对应的模块操作。
## [param key] 调用方传入的 `key` 参数。
## [param recipe_id] 调用方传入的 `recipe_id` 参数。
func _index_product_key(key: String, recipe_id: String) -> void:
	var normalized := key.strip_edges().to_lower()
	if normalized.is_empty():
		return
	var ids: PackedStringArray = _ids_by_product_key.get(normalized, PackedStringArray())
	if recipe_id not in ids:
		ids.append(recipe_id)
	_ids_by_product_key[normalized] = ids
