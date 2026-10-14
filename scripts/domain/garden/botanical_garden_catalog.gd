class_name BotanicalGardenCatalog
extends RefCounted

class Plant extends RefCounted:
	var id: String
	var item_id: String
	var position: Vector2
	var fruit_offset: Vector2
	var variant: String

var map_id := ""
var interaction_radius := 150.0
var regrowth_seconds := 30
var plants: Array[Plant] = []


## 读取经过来源核对的树锚点；距离、点位选择和再生时间是复刻配置。
## 返回类型化目录或格式错误。
static func load_default() -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary("res://data/world/botanical_garden_v1.json")
	if not loaded.is_ok: return loaded
	var raw: Dictionary = loaded.value
	var result := BotanicalGardenCatalog.new()
	result.map_id = String(raw.get("map_id", ""))
	result.interaction_radius = float(raw.get("interaction_radius", 0))
	result.regrowth_seconds = int(raw.get("regrowth_seconds", 0))
	if result.map_id.is_empty() or not is_finite(result.interaction_radius) or result.interaction_radius <= 0 or result.regrowth_seconds <= 0:
		return DomainResult.failure(&"garden.catalog", "植物园规则无效")
	var ids := {}
	for row: Dictionary in raw.get("plants", []):
		var plant := Plant.new()
		plant.id = String(row.get("id", ""))
		plant.item_id = String(row.get("item_definition_id", ""))
		if plant.id.is_empty() or plant.item_id.is_empty() or ids.has(plant.id) or not _point(row.get("position")) or not _point(row.get("fruit_offset")):
			return DomainResult.failure(&"garden.catalog", "植物园点位无效")
		plant.position = Vector2(row.position[0], row.position[1])
		plant.fruit_offset = Vector2(row.fruit_offset[0], row.fruit_offset[1])
		plant.variant = String(row.get("fruit_variant", ""))
		ids[plant.id] = true
		result.plants.append(plant)
	return DomainResult.ok(result)


## 查找当前配置中存在的采摘点，未知身份不能获得奖励。
## [param id] 客户端选择的点位身份。
## 返回植物定义，未知时为空。
func find(id: String) -> Plant:
	for plant: Plant in plants:
		if plant.id == id: return plant
	return null


## 验证原始二维坐标，不将字符串或布尔值当作坐标。
## [param value] 原始配置值。
## 返回是否包含两个有限数字。
static func _point(value: Variant) -> bool:
	if not value is Array or value.size() != 2: return false
	for component: Variant in value:
		if not (component is int or component is float) or not is_finite(float(component)): return false
	return true
