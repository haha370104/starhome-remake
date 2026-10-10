class_name AuthoritativeGardenService
extends RefCounted

var catalog: BotanicalGardenCatalog
var _ready_at: Dictionary[String, int] = {}
var _grant_sequence := 0
var _grant_namespace := Crypto.new().generate_random_bytes(16).hex_encode()


## 为植物园建立权威果实目录；成熟状态只由服务器持有。
## [param garden_catalog] 客户端也使用的静态点位和产物目录。
func _init(garden_catalog: BotanicalGardenCatalog) -> void:
	catalog = garden_catalog


## 查询当前角色在本地图的果实成熟状态，禁止跨地图读取。
## [param player] 在线角色。[param map_id] 会话绑定的权威地图。
## [param now] 服务端 Unix 秒。
## 返回每个果实的剩余生长秒数。
func query(player: Player, map_id: String, now: int) -> DomainResult:
	if catalog == null or not catalog.supports_map(map_id):
		return DomainResult.failure(&"garden.unavailable", "当前地图不能采摘")
	var state: Array[Dictionary] = []
	for plant_id: String in catalog.plants:
		state.append({"plant_id": plant_id, "remaining_seconds": _remaining(player, plant_id, now)})
	return DomainResult.ok({"map_id": map_id, "plants": state})


## 校验采摘点、人物实际位置及成熟状态；不改变背包或生长时钟。
## [param player] 在线角色。[param map_id] 会话绑定地图。[param position] 模拟器中的权威位置。
## [param plant_id] 客户端选择的静态果实身份。[param now] 服务端 Unix 秒。
## 返回已确认的产物及一次性入包编号。
func prepare_harvest(player: Player, map_id: String, position: Vector2, plant_id: String, now: int) -> DomainResult:
	if catalog == null or not catalog.supports_map(map_id):
		return DomainResult.failure(&"garden.unavailable", "当前地图不能采摘")
	var plant: Dictionary = catalog.plants.get(plant_id, {})
	if plant.is_empty(): return DomainResult.failure(&"garden.plant_missing", "这处果实不存在")
	if not position.is_finite() or position.distance_to(plant.position) > catalog.interaction_radius:
		return DomainResult.failure(&"garden.too_far", "距离果实太远")
	if _remaining(player, plant_id, now) > 0:
		return DomainResult.failure(&"garden.regrowing", "果实尚未成熟")
	_grant_sequence += 1
	return DomainResult.ok({"loot_id": "garden.%s.%d" % [_grant_namespace, _grant_sequence],
		"item_definition_id": plant.item_definition_id, "quantity": 1})


## 背包提交成功后开始该玩家在此点的下一轮生长。
## [param player] 已提交的在线角色。[param plant_id] 成功采摘的果实点。[param now] 服务端 Unix 秒。
## 返回该点新的剩余生长秒数。
func commit_harvest(player: Player, plant_id: String, now: int) -> int:
	_ready_at[_key(player, plant_id)] = now + catalog.regrowth_seconds
	return catalog.regrowth_seconds


## 读取一个角色对指定果实点的权威剩余冷却。
## [param player] 在线角色。[param plant_id] 果实点。[param now] 服务端 Unix 秒。
## 返回非负剩余秒数。
func _remaining(player: Player, plant_id: String, now: int) -> int:
	return maxi(0, _ready_at.get(_key(player, plant_id), 0) - now)


## 按账号和果实点隔离成熟时钟，切图不重置。
## [param player] 在线角色。[param plant_id] 果实点。
## 返回服务端私有索引键。
func _key(player: Player, plant_id: String) -> String:
	return "%s:%s" % [player.entity_id, plant_id]
