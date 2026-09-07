class_name VehicleLoadout
extends RefCounted

const EquipmentSlotRegistryScript := preload("res://scripts/domain/equipment/equipment_slot_registry.gd")

var revision: int
var _equipped: Dictionary = {}


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
func has_chassis() -> bool:
	return _equipped.get(0) is VehicleChassis


## 除底盘外是否仍安装了任意战车装备。
## 更换或卸下底盘前必须先清空这些槽位，避免产生悬空装配。
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
