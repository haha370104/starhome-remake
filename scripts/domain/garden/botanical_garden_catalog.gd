class_name BotanicalGardenCatalog
extends RefCounted

const CONFIG_PATH := "res://data/world/botanical_garden_v1.json"

var map_id := ""
var interaction_radius := 0.0
var regrowth_seconds := 0
var plants: Dictionary[String, Dictionary] = {}


## 载入受控地图上的可采摘果实，校验身份、坐标和冷却配置。
## 返回可共享给客户端与服务端的目录，或配置错误。
static func load_default() -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary(CONFIG_PATH)
	if not loaded.is_ok: return loaded
	var config: Dictionary = loaded.value
	var catalog := BotanicalGardenCatalog.new()
	catalog.map_id = String(config.get("map_id", ""))
	catalog.interaction_radius = float(config.get("interaction_radius", 0))
	catalog.regrowth_seconds = int(config.get("regrowth_seconds", 0))
	var rows: Variant = config.get("plants")
	if catalog.map_id.is_empty() or catalog.interaction_radius <= 0 or catalog.regrowth_seconds <= 0 or not rows is Array:
		return DomainResult.failure(&"garden.invalid_catalog", "植物园配置不完整")
	for raw: Variant in rows:
		if not raw is Dictionary: return DomainResult.failure(&"garden.invalid_catalog", "植物园果实配置无效")
		var row: Dictionary = raw
		var id := String(row.get("id", ""))
		var item_id := String(row.get("item_definition_id", ""))
		var point: Variant = row.get("position")
		var offset: Variant = row.get("fruit_offset")
		if id.is_empty() or item_id.is_empty() or catalog.plants.has(id) or not point is Array or point.size() != 2 \
				or not offset is Array or offset.size() != 2:
			return DomainResult.failure(&"garden.invalid_catalog", "植物园果实身份或位置无效")
		var position := Vector2(float(point[0]), float(point[1]))
		var fruit_offset := Vector2(float(offset[0]), float(offset[1]))
		if not position.is_finite() or not fruit_offset.is_finite():
			return DomainResult.failure(&"garden.invalid_catalog", "植物园果实位置无效")
		catalog.plants[id] = {"id": id, "item_definition_id": item_id,
			"position": position, "fruit_offset": fruit_offset,
			"fruit_variant": String(row.get("fruit_variant", ""))}
	return DomainResult.ok(catalog)


## 查询当前地图是否提供已配置的果实采摘。
## [param requested_map_id] 权威地图业务标识。
## 返回是否属于当前植物园。
func supports_map(requested_map_id: String) -> bool:
	return requested_map_id == map_id
