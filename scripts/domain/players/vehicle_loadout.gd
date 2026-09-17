class_name VehicleLoadout
extends RefCounted


const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

var revision: int
var _equipped: Dictionary = {}


## 汇总当前穿戴的独立特殊装备加值，供战车与战斗共同使用。
## [param attribute] 战车统一属性。
## 返回所有有效装备的固定加值。
func special_bonus(attribute: String) -> int:
	var total := 0
	for equipment: VehicleEquipment in _equipped.values(): total += equipment.special_bonus(attribute)
	return total



## 按实际装配汇总发生器常驻属性，不受是否剩余触发弹药影响。
## [param attribute] 统一战车属性名。
## 返回所有健全发生器的基础加值。
func generator_bonus(attribute: String) -> int:
	var total := 0
	for equipment: VehicleEquipment in _equipped.values(): total += equipment.generator_bonus(attribute)
	return total


## 汇总全身同类数值最高四颗普通晶石，瑕疵和明亮共用名额，损坏装备不提供效果。
## [param attribute] 规范化战车属性。
## 返回固定加值或暴击概率。
func socket_bonus(attribute: String) -> float:
	var effect := String({"energy_cannon_attack": "firepower", "max_health": "health",
		"defense": "defense", "missile_attack": "guidance", "rocket_attack": "rocket",
		"critical_chance": "critical"}.get(attribute, ""))
	if effect.is_empty():
		return 0.0
	var values: Array[float] = []
	var limit := 4
	for item: VehicleEquipment in _equipped.values():
		if item.durability <= 0 or item.socket_rules == null:
			continue
		limit = item.socket_rules.maximum_effective
		for index: int in item.sockets.capacity():
			var slot := item.sockets.slot_at(index)
			var crystal := item.socket_rules.crystal(slot.crystal_id)
			if crystal != null and crystal.effect == effect:
				values.append(crystal.value)
	values.sort()
	var total := 0.0
	for index: int in mini(limit, values.size()):
		total += values[values.size() - index - 1]
	return total


## 汇总已装配且有耐久的接合器，背包中的物品不参与计算。
## [param effect] 领域效果标识。
## 返回各独立槽位的加值总和。
func attachment_bonus(effect: String) -> int:
	var total := 0
	for equipment: VehicleEquipment in _equipped.values():
		total += equipment.attachment_bonus(effect)
	return total


## 自动分配同类别空位，两个位置均满时要求先卸装，避免双击误替换。
## [param equipment] 待安装装备。
## [param requested] 客户端请求的位置；只能位于该装备的白名单中。
## 返回合法目标位置或类别已满错误。
func resolve_install_location(equipment: VehicleEquipment, requested: int) -> DomainResult:
	if not equipment.accepts_location(requested):
		return DomainResult.failure(&"equipment.location_rejected", "invalid attachment slot")
	if equipment.attachment_family.is_empty():
		return DomainResult.ok(requested)
	if not _equipped.has(requested):
		return DomainResult.ok(requested)
	for location: int in equipment.allowed_locations:
		if not _equipped.has(location):
			return DomainResult.ok(location)
	return DomainResult.failure(&"equipment.attachment_slots_full", "attachment family already has two items")


## 初始化战车固定 Location 装配集合。
## [param initial_revision] 当前装配 revision。
func _init(initial_revision: int = 0) -> void:
	revision = maxi(0, initial_revision)


## 从持久化边界还原一件已安装战车装备。
## [param equipment] 已完成类型构造的战车装备。
## 返回成功或重复、非法 Location 错误。
func restore(equipment: VehicleEquipment) -> DomainResult:
	if equipment == null or equipment.equipment_location < 0:
		return DomainResult.failure(&"equipment.location_rejected", "vehicle equipment location is invalid")
	if _equipped.has(equipment.equipment_location):
		return DomainResult.failure(&"equipment.slot_duplicated", "vehicle equipment location is duplicated")
	_equipped[equipment.equipment_location] = equipment
	return DomainResult.ok()


## 校验 revision 后安装战车装备并返回被替换装备。
## [param equipment] 待安装装备。
## [param location] 目标稳定 Location。
## [param expected_revision] 客户端读取到的装配 revision。
## 返回旧装备；空槽时 value 为 null。
func equip(
	equipment: VehicleEquipment,
	location: int,
	expected_revision: int,
) -> DomainResult:
	var revision_result := require_revision(expected_revision)
	if not revision_result.is_ok:
		return revision_result
	if equipment == null or not equipment.accepts_location(location):
		return DomainResult.failure(&"equipment.location_rejected", "item cannot be installed in requested location")
	var replaced: VehicleEquipment = _equipped.get(location)
	equipment.equipment_location = location
	_equipped[location] = equipment
	return DomainResult.ok(replaced)


## 校验 revision 后卸下指定 Location 装备。
## [param location] 待卸载稳定 Location。
## [param expected_revision] 客户端读取到的装配 revision。
## 返回被卸下装备或空槽、版本错误。
func unequip(location: int, expected_revision: int) -> DomainResult:
	var revision_result := require_revision(expected_revision)
	if not revision_result.is_ok:
		return revision_result
	if not _equipped.has(location):
		return DomainResult.failure(&"equipment.slot_empty", "vehicle equipment slot is empty")
	var equipment: VehicleEquipment = _equipped[location]
	_equipped.erase(location)
	return DomainResult.ok(equipment)


## 查询指定 Location 的装备。
## [param location] 稳定 Location。
## 返回装备；空槽返回 null。
func at(location: int) -> VehicleEquipment:
	return _equipped.get(location)


## 当前装配是否包含战车底盘。
## 返回底盘槽装有战车底盘实例时为真。
func has_chassis() -> bool:
	return _equipped.get(0) is VehicleChassis


## 校验固定主装置槽内的采掘臂，背包持有或其他槽位装备不算安装。
## [param mining_level] 角色当前采矿技能等级。
## 返回可采矿或明确的装备/技能错误。
func validate_mining(mining_level: int) -> DomainResult:
	if not has_chassis():
		return DomainResult.failure(&"equipment.chassis_required", "mining requires a vehicle chassis")
	var arm := at(1) as VehicleMiningArm
	if arm == null:
		return DomainResult.failure(&"mining.arm_required", "a mining arm must be installed in the primary slot")
	return arm.validate_collection(mining_level)


## 除底盘外是否仍安装了任意战车装备。
## 更换或卸下底盘前必须先清空这些槽位，避免产生悬空装配。
## 返回至少一个非底盘槽位仍有装备时为真。
func has_non_chassis_equipment() -> bool:
	for location: int in _equipped:
		if location != 0:
			return true
	return false


## 按稳定 Location 顺序导出全部已安装装备。
## 返回装备数组的防御性副本。
func items() -> Array[VehicleEquipment]:
	var locations: Array = _equipped.keys()
	locations.sort()
	var result: Array[VehicleEquipment] = []
	for location: int in locations:
		result.append(_equipped[location])
	return result


## 推进一次由玩家聚合完成的装配事务版本。
func commit_transfer() -> void:
	revision += 1


## 校验客户端装配 revision。
## [param expected_revision] 客户端命令携带的 revision。
## 返回成功或版本冲突。
func require_revision(expected_revision: int) -> DomainResult:
	if expected_revision != revision:
		return DomainResult.failure(&"equipment.revision_conflict", "vehicle loadout revision changed")
	return DomainResult.ok()


## 查询 Location 的中文业务名称。
## [param location] 稳定 Location。
## 返回面板显示名称。
func location_name(location: int) -> String:
	return EquipmentSlotRegistryScript.display_name(location)
