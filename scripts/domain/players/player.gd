class_name Player
extends MovableEntity

const DomainResult := preload("res://scripts/core/domain_result.gd")

var account_id: String
var account_name: String
var account_status: String
var display_name: String
var sex: String
var level: int
var profession: String
var faction: String
var residence: String
var description: String
var max_health: int
var health: int
var experience: int
var revision: int
var map_id: String
var map_instance_id: String
var checkpoint_id: String
var inventory: Inventory
var character_equipment: CharacterEquipment
var vehicle: PlayerVehicle
var skills: SkillBook


## 初始化完整玩家聚合及其固定子对象。
## [param state] 来自持久化映射器或客户端快照的纯状态。
## 设计：Player 是背包、人物穿着、战车和技能的一致性边界；权威服务只调用其用例方法。
func _init(state: Dictionary = {}) -> void:
	super(
		String(state.get("character_id", "")),
		state.get("position", Vector2.ZERO),
		float(state.get("movement_speed", 0.0)),
		int(state.get("facing_direction", 0)),
	)
	account_id = String(state.get("account_id", ""))
	account_name = String(state.get("account_name", ""))
	account_status = String(state.get("account_status", "active"))
	display_name = String(state.get("display_name", ""))
	sex = String(state.get("sex", "male"))
	level = maxi(1, int(state.get("level", 1)))
	profession = String(state.get("profession", "新兵"))
	faction = String(state.get("faction", "易安港"))
	residence = String(state.get("residence", "易安港基地"))
	description = String(state.get("description", ""))
	max_health = maxi(1, int(state.get("max_health", 1)))
	health = clampi(int(state.get("health", max_health)), 0, max_health)
	experience = maxi(0, int(state.get("experience", 0)))
	revision = maxi(0, int(state.get("revision", 0)))
	map_id = String(state.get("map_id", ""))
	map_instance_id = String(state.get("map_instance_id", ""))
	checkpoint_id = String(state.get("checkpoint_id", ""))
	inventory = Inventory.new(
		int(state.get("inventory_capacity", 40)),
		int(state.get("inventory_revision", 0)),
		int(state.get("currency", 0)),
	)
	character_equipment = CharacterEquipment.new()
	vehicle = PlayerVehicle.new(state.get("vehicle", {}))
	skills = SkillBook.new(state.get("skills", {}))


## 移动背包物品并由背包维护自身 revision。
## [param instance_id] 物品实例标识。
## [param requested_position] 请求的像素坐标。
## [param expected_inventory_revision] 客户端背包 revision。
## 返回领域操作结果。
func move_inventory_item(
	instance_id: String,
	requested_position: Vector2i,
	expected_inventory_revision: int,
) -> DomainResult:
	return inventory.move_item(instance_id, requested_position, expected_inventory_revision)


## 自动整理背包并由背包维护自身 revision。
## [param expected_inventory_revision] 客户端背包 revision。
## 返回领域操作结果。
func arrange_inventory(expected_inventory_revision: int) -> DomainResult:
	return inventory.arrange(expected_inventory_revision)


## 将背包内战车装备安装到固定 Location。
## [param instance_id] 背包物品实例标识。
## [param location] 目标战车 Location。
## [param expected_inventory_revision] 客户端背包 revision。
## [param expected_loadout_revision] 客户端装配 revision。
## 返回成功或类型、槽位、容量与版本错误。
func equip_vehicle_item(
	instance_id: String,
	location: int,
	expected_inventory_revision: int,
	expected_loadout_revision: int,
) -> DomainResult:
	var inventory_revision_result := inventory.require_revision(expected_inventory_revision)
	if not inventory_revision_result.is_ok:
		return inventory_revision_result
	var loadout_revision_result := vehicle.loadout.require_revision(expected_loadout_revision)
	if not loadout_revision_result.is_ok:
		return loadout_revision_result
	var item := inventory.find(instance_id)
	if not item is VehicleEquipment:
		return DomainResult.failure(&"equipment.location_rejected", "inventory item is not vehicle equipment")
	if not (item as VehicleEquipment).accepts_location(location):
		return DomainResult.failure(&"equipment.location_rejected", "item cannot be installed in requested location")
	var replaced := vehicle.loadout.at(location)
	if replaced != null:
		var position_result := inventory.transfer_position(replaced, instance_id)
		if not position_result.is_ok:
			return position_result
	var removed := inventory.remove_for_transfer(instance_id)
	if not removed.is_ok:
		return removed
	var equipped := vehicle.loadout.equip(removed.value, location, expected_loadout_revision)
	if not equipped.is_ok:
		return equipped
	if equipped.value != null:
		var returned := inventory.add_from_transfer(equipped.value)
		if not returned.is_ok:
			return returned
	inventory.commit_transfer()
	vehicle.loadout.commit_transfer()
	return DomainResult.ok()


## 将战车固定 Location 的装备卸回背包。
## [param location] 待卸载 Location。
## [param expected_inventory_revision] 客户端背包 revision。
## [param expected_loadout_revision] 客户端装配 revision。
## 返回成功或空槽、容量与版本错误。
func unequip_vehicle_item(
	location: int,
	expected_inventory_revision: int,
	expected_loadout_revision: int,
) -> DomainResult:
	var inventory_revision_result := inventory.require_revision(expected_inventory_revision)
	if not inventory_revision_result.is_ok:
		return inventory_revision_result
	var equipped := vehicle.loadout.at(location)
	if equipped == null:
		return DomainResult.failure(&"equipment.slot_empty", "vehicle equipment slot is empty")
	var position_result := inventory.transfer_position(equipped)
	if not position_result.is_ok:
		return position_result
	var unloaded := vehicle.loadout.unequip(location, expected_loadout_revision)
	if not unloaded.is_ok:
		return unloaded
	var returned := inventory.add_from_transfer(unloaded.value)
	if not returned.is_ok:
		return returned
	inventory.commit_transfer()
	vehicle.loadout.commit_transfer()
	return DomainResult.ok()


## 将背包服装穿到人物固定槽位。
## [param instance_id] 背包服装实例标识。
## [param slot_id] 目标人物槽位。
## [param expected_inventory_revision] 客户端背包 revision。
## [param expected_state_revision] 客户端玩家聚合 revision。
## 返回成功或类型、性别、槽位、容量与版本错误。
func equip_character_item(
	instance_id: String,
	slot_id: String,
	expected_inventory_revision: int,
	expected_state_revision: int,
) -> DomainResult:
	var revision_result := _require_character_revisions(
		expected_inventory_revision, expected_state_revision
	)
	if not revision_result.is_ok:
		return revision_result
	var item := inventory.find(instance_id)
	if not item is Clothing:
		return DomainResult.failure(&"equipment.location_rejected", "inventory item is not clothing")
	if not (item as Clothing).can_equip(slot_id, sex):
		return DomainResult.failure(&"equipment.location_rejected", "clothing cannot be equipped in requested slot")
	var replaced := character_equipment.at(slot_id)
	if replaced != null:
		var position_result := inventory.transfer_position(replaced, instance_id)
		if not position_result.is_ok:
			return position_result
	var removed := inventory.remove_for_transfer(instance_id)
	if not removed.is_ok:
		return removed
	var equipped := character_equipment.equip(removed.value, slot_id, sex)
	if not equipped.is_ok:
		return equipped
	if equipped.value != null:
		var returned := inventory.add_from_transfer(equipped.value)
		if not returned.is_ok:
			return returned
	inventory.commit_transfer()
	return DomainResult.ok()


## 将人物固定槽位服装卸回背包。
## [param slot_id] 待卸载人物槽位。
## [param expected_inventory_revision] 客户端背包 revision。
## [param expected_state_revision] 客户端玩家聚合 revision。
## 返回成功或空槽、容量与版本错误。
func unequip_character_item(
	slot_id: String,
	expected_inventory_revision: int,
	expected_state_revision: int,
) -> DomainResult:
	var revision_result := _require_character_revisions(
		expected_inventory_revision, expected_state_revision
	)
	if not revision_result.is_ok:
		return revision_result
	var equipped := character_equipment.at(slot_id)
	if equipped == null:
		return DomainResult.failure(&"equipment.slot_empty", "character equipment slot is empty")
	var position_result := inventory.transfer_position(equipped)
	if not position_result.is_ok:
		return position_result
	var unloaded := character_equipment.unequip(slot_id)
	if not unloaded.is_ok:
		return unloaded
	var returned := inventory.add_from_transfer(unloaded.value)
	if not returned.is_ok:
		return returned
	inventory.commit_transfer()
	return DomainResult.ok()


## 校验人物换装需要的背包和玩家聚合 revision。
## [param expected_inventory_revision] 客户端背包 revision。
## [param expected_state_revision] 客户端玩家聚合 revision。
## 返回成功或版本冲突。
func _require_character_revisions(
	expected_inventory_revision: int,
	expected_state_revision: int,
) -> DomainResult:
	var inventory_result := inventory.require_revision(expected_inventory_revision)
	if not inventory_result.is_ok:
		return inventory_result
	if expected_state_revision != revision:
		return DomainResult.failure(&"equipment.revision_conflict", "character state revision changed")
	return DomainResult.ok()
