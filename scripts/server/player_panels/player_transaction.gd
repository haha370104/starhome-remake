class_name PlayerTransaction
extends RefCounted

const PLAYER_FIELDS := [
	"entity_id", "position", "movement_speed", "facing_direction", "account_id",
	"account_name", "account_status", "display_name", "sex", "level",
	"profession", "faction", "residence", "description", "max_health",
	"health", "experience", "revision", "map_id", "map_instance_id",
	"checkpoint_id", "inventory", "garden", "warehouse", "production",
	"central", "vehicle_presets", "character_equipment", "vehicle", "skills",
	"quest_states", "achievements", "daily_activities", "amethyst", "food_status",
	"reward_pipeline"
]
const VEHICLE_FIELDS := [
	"vehicle_id", "definition_id", "loadout", "max_health", "health",
	"reserve_energy_capacity", "reserve_energy", "working_energy_capacity", "working_energy", "output_power",
	"achievement_bonuses", "food_status", "central", "central_rules", "clothing_bonuses"
]
const INVENTORY_COMMANDS := ["move_inventory_item", "arrange_inventory", "split_inventory_item", "merge_inventory_item"]


## 在稳定在线聚合身份上合入已通过映射校验的状态。
## [param target] 在线聚合。[param source] 完整候选；其所有权转移给在线存储。
static func adopt(target: Player, source: Player) -> void:
	for field: String in PLAYER_FIELDS: target.set(field, source.get(field))


## 为背包写入和采矿成就建立隔离候选，其他子域只能被此组用例读取。
## [param player] 当前只读在线聚合。[param catalog] 共享只读目录。
## [param write_ids] 可能修改的实例；空数组表示整个背包。
## 返回候选或物品恢复错误；不会改变源聚合。
static func inventory_candidate(player: Player, catalog: ItemCatalog, write_ids: PackedStringArray = []) -> DomainResult:
	var candidate := Player.new()
	adopt(candidate, player)
	candidate.vehicle = PlayerVehicle.new()
	for field: String in VEHICLE_FIELDS: candidate.vehicle.set(field, player.vehicle.get(field))
	candidate.achievements = PlayerAchievements.new(player.achievements.to_dictionary())
	candidate.vehicle.achievement_bonuses = candidate.achievements.bonuses()
	candidate.inventory = Inventory.new(player.inventory.capacity, player.inventory.revision, player.inventory.currency)
	var items: Array[GameItem] = []
	for item: GameItem in player.inventory.items():
		if not write_ids.is_empty() and item.instance_id not in write_ids:
			items.append(item)
			continue
		var recorded := InventoryStackRecord.from_item(item, items.size())
		if not recorded.is_ok: return recorded
		var created := catalog.create(item.definition_id, recorded.value.item_state())
		if not created.is_ok: return created
		items.append(created.value)
	var restored := candidate.inventory.restore_items(items)
	return DomainResult.ok(candidate) if restored.is_ok else restored
