class_name WarehouseRules
extends RefCounted

var expansion_cost: int
var allowed_maps: PackedStringArray = []


## 读取只属于个人仓库的地点和费用配置。
## 返回验证后的类型化规则。
static func load_default() -> DomainResult:
	var loaded := JsonConfigLoader.load_dictionary("res://data/gameplay/personal_warehouse_v1.json")
	if not loaded.is_ok: return loaded
	var raw: Dictionary = loaded.value
	if raw.get("schema_version") != 1 or raw.get("maximum_cabinets") != PersonalWarehouse.MAX_CABINETS or raw.get("cabinet_capacity") != InventoryLayout.ITEM_LIMIT:
		return DomainResult.failure(&"warehouse.rules", "仓库规则版本或容量无效")
	var cost: Variant = raw.get("expansion_cost_amethyst")
	if not (cost is int or cost is float) or not is_finite(float(cost)) or cost <= 0 or float(cost) != floorf(float(cost)):
		return DomainResult.failure(&"warehouse.rules", "仓库扩容费用无效")
	var maps: Variant = raw.get("allowed_map_ids")
	if not maps is Array or maps.is_empty():
		return DomainResult.failure(&"warehouse.rules", "仓库缺少允许使用地点")
	var rules := WarehouseRules.new()
	rules.expansion_cost = int(cost)
	for id: Variant in maps:
		if not id is String or id.is_empty() or id in rules.allowed_maps:
			return DomainResult.failure(&"warehouse.rules", "仓库地点无效或重复")
		rules.allowed_maps.append(id)
	return DomainResult.ok(rules)


## 由服务端验证实际地点，不读取客户端的允许使用标记。
## [param map_id] 权威玩家所在地图。
## 返回该地点是否允许仓库存取和扩容。
func allows(map_id: String) -> bool:
	return map_id in allowed_maps
