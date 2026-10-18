class_name PlayerInventoryRecordWriter
extends RefCounted

const RECORD_FIELDS := [
	"account_id", "account_name", "account_status", "character_id", "display_name",
	"revision", "inventory_revision", "vehicle_loadout_revision", "inventory_capacity", "inventory_stacks",
	"garden", "warehouse", "production", "central", "vehicle_presets",
	"equipment_slots", "currency", "amethyst", "character_sex", "character_level",
	"character_profession", "character_faction", "character_residence", "character_description", "character_max_health",
	"character_health", "character_experience", "character_skills", "quest_states", "achievements",
	"daily_activities", "food_status", "vehicle_id", "vehicle_definition_id", "vehicle_max_health",
	"vehicle_health", "reserve_energy_capacity", "reserve_energy", "working_energy_capacity", "working_energy",
	"output_power", "map_id", "map_instance_id", "position", "facing_direction",
	"checkpoint_id"
]


## 采集背包及成就写集合，未改动记录组件只读共享到仓储复制边界。
## [param player] 已隔离的背包事务候选。[param base] 本次事务读取的完整权威记录。
## 返回通过校验的候选；调用方不得直接修改其共享组件。
## 设计：仅供背包摆放、堆叠与采集事务使用；换装、制造继续完整映射。
static func capture(player: Player, base: PlayerStateRecord) -> DomainResult:
	var candidate := PlayerStateRecord.new()
	for field: String in RECORD_FIELDS: candidate.set(field, base.get(field))
	candidate.inventory_stacks = []
	for item: GameItem in player.inventory.items():
		var record := InventoryStackRecord.from_item(item, candidate.inventory_stacks.size())
		if not record.is_ok: return record
		candidate.inventory_stacks.append(record.value)
	candidate.inventory_revision = player.inventory.revision
	candidate.currency = player.inventory.currency
	candidate.achievements = player.achievements.to_dictionary()
	candidate.vehicle_health = player.vehicle.health
	candidate.vehicle_max_health = player.vehicle.max_health
	candidate.reserve_energy = player.vehicle.reserve_energy
	candidate.reserve_energy_capacity = player.vehicle.reserve_energy_capacity
	candidate.working_energy = player.vehicle.working_energy
	candidate.working_energy_capacity = player.vehicle.working_energy_capacity
	candidate.output_power = player.vehicle.output_power
	var checked := candidate.validate()
	return DomainResult.ok(candidate) if checked.is_ok else checked
