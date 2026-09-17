class_name PlayerConsumableActions
extends RefCounted


## 原子使用自有物品：食品消耗一份，能量包按战车剩余容量决定整包使用量。
## [param player] 拥有背包、人物和战车的玩家聚合。
## [param id] 物品实例标识。
## [param expected_revision] 客户端背包版本。
## [param now] 权威时刻。
## 返回使用结果；失败不消耗数量。
static func use_item(player: Player, id: String, expected_revision: int, now: int) -> DomainResult:
	var checked := player.inventory.require_revision(expected_revision)
	if not checked.is_ok:
		return checked
	var item := player.inventory.find(id) as ConsumableItem
	if item == null or item.locked:
		return DomainResult.failure(&"items.not_usable", "该物品不可使用或已锁定")
	if player.health <= 0:
		return DomainResult.failure(&"items.player_dead", "人物死亡时不能使用物品")
	var quantity := 1
	if item.energy > 0:
		if player.vehicle.health <= 0:
			return DomainResult.failure(&"items.vehicle_destroyed", "战车已损毁，不能使用能量包")
		quantity = player.vehicle.energy_pack_use_count(item.energy, item.quantity)
		if quantity <= 0:
			return DomainResult.failure(&"items.energy_full", "战车储备能量已满")
	checked = player.food_status.can_eat(item, now)
	if not checked.is_ok:
		return checked
	var removed := player.inventory.remove_quantity(id, quantity)
	if not removed.is_ok:
		return removed
	player.vehicle.reserve_energy = minf(player.vehicle.reserve_energy_capacity,
		player.vehicle.reserve_energy + item.energy * quantity)
	var heal := player.food_status.eat(item, now)
	player.vehicle.reconcile_loadout_state(false)
	if player.vehicle.health > 0:
		player.vehicle.health = mini(player.vehicle.max_health, player.vehicle.health + heal)
	return DomainResult.ok()
