class_name GroundItem
extends RefCounted

const DROP_RADIUS := 65.0
const PICKUP_RADIUS := 125.0
var loot_id: String
var map_instance_id: String
var position: Vector2
var item: GameItem


## 从隔离玩家候选中移出整件物品，绑定和锁定物品禁止丢弃。
## [param player] 事务内的玩家候选。[param instance_id] 自有物品身份。
## [param revision] 背包版本。[param map_id] 当前地图实例。
## [param origin] 权威玩家脚点。[param target] 已通过地图可达性校验的落点。
## 返回地面实例；所有检查通过前不会改变玩家。
static func drop_from(player: Player, instance_id: String, revision: int, map_id: String, origin: Vector2, target: Vector2) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if map_id.is_empty() or not origin.is_finite() or not target.is_finite() or origin.distance_to(target) > DROP_RADIUS:
		return DomainResult.failure(&"loot.drop_too_far", "只能丢在身边的可行走位置")
	var carried := player.inventory.find(instance_id)
	if carried == null: return DomainResult.failure(&"inventory.item_not_found", "背包里没有这件物品")
	if carried.locked or carried.bound:
		return DomainResult.failure(&"loot.drop_forbidden", "锁定或绑定物品不能丢弃")
	var removed := player.inventory.remove_for_transfer(instance_id)
	if not removed.is_ok: return removed
	player.inventory.commit_transfer()
	var dropped := GroundItem.new()
	dropped.loot_id = "ground." + Crypto.new().generate_random_bytes(16).hex_encode()
	dropped.map_instance_id = map_id
	dropped.position = target
	dropped.item = carried
	return DomainResult.ok(dropped)


## 把地面物品的完整实例移入玩家候选，容量不足时保留地面所有权。
## [param player] 事务内的玩家候选。[param map_id] 拾取者当前地图。
## [param actor_position] 权威玩家脚点。
## 返回是否完成入包；成功只推进一次背包版本。
func receive_into(player: Player, map_id: String, actor_position: Vector2) -> DomainResult:
	if map_id != map_instance_id or not actor_position.is_finite() or actor_position.distance_to(position) > PICKUP_RADIUS:
		return DomainResult.failure(&"loot.out_of_range", "距离物品太远")
	if player.inventory.find(item.instance_id) != null:
		return DomainResult.failure(&"loot.instance_conflict", "背包已拥有同一件物品")
	var accepted := player.inventory.add_from_transfer(item)
	if accepted.is_ok: player.inventory.commit_transfer()
	return accepted


## 生成地面表现所需的最小快照，装备成长保留在服务端实例中。
## 返回与怪物掉落相同的展示协议。
func snapshot() -> Dictionary:
	return {"loot_id": loot_id, "map_instance_id": map_instance_id, "position": [position.x, position.y],
		"item_definition_id": item.definition_id, "quantity": item.quantity, "dropped_by_player": true}
