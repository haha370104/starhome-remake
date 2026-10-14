class_name GardenProgress
extends RefCounted

var _ready_at: Dictionary = {}


## 恢复角色独立的再生时钟，缺省空状态兼容旧存档。
## [param raw] 点位身份到权威到期秒数的映射。
## 返回独立领域对象或格式错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary: return DomainResult.failure(&"garden.state", "采摘记录无效")
	for id: Variant in raw:
		var value: Variant = raw[id]
		if not id is String or id.is_empty() or not (value is int or value is float) or not is_finite(float(value)) or value < 0 or value > 9007199254740991 or float(value) != floorf(float(value)):
			return DomainResult.failure(&"garden.state", "采摘时钟无效")
	var result := GardenProgress.new()
	result._ready_at = raw.duplicate(true)
	return DomainResult.ok(result)


## 输出不可反向修改当前对象的持久化快照。
## 返回点位再生时钟副本。
func to_dictionary() -> Dictionary:
	return _ready_at.duplicate(true)


## 使用服务端时间计算成熟状态，不依赖客户端时钟。
## [param id] 点位身份。[param now] 权威当前秒数。
## 返回剩余再生秒数。
func remaining(id: String, now: int) -> int:
	return maxi(0, int(_ready_at.get(id, 0)) - now)


## 在同一候选玩家内完成距离、成熟和容量检查，成功入包后才记录冷却。
## [param rules] 权威植物目录。[param plant] 已解析的采摘点。
## [param map_id] 当前权威地图。[param position] 当前权威位置。
## [param inventory] 同事务背包。[param fruit] 本次唯一身份的产物。[param now] 权威秒数。
## 返回实际新增物品数量或不修改状态的拒绝原因。
func harvest(rules: BotanicalGardenCatalog, plant: BotanicalGardenCatalog.Plant, map_id: String,
		position: Vector2, inventory: Inventory, fruit: GameItem, now: int) -> DomainResult:
	if rules == null or plant == null or fruit == null or fruit.definition_id != plant.item_id or fruit.quantity != 1:
		return DomainResult.failure(&"garden.plant", "采摘目标无效")
	if map_id != rules.map_id or position.distance_to(plant.position) > rules.interaction_radius:
		return DomainResult.failure(&"garden.distance", "请走到果树附近再采摘")
	if remaining(plant.id, now) > 0:
		return DomainResult.failure(&"garden.regrowth", "果实尚未成熟")
	var added := inventory.add_reward(fruit)
	if not added.is_ok: return added
	_ready_at[plant.id] = now + rules.regrowth_seconds
	return DomainResult.ok(1)
