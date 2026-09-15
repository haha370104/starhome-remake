class_name AttachmentUpgradePlan
extends RefCounted

var definition_id: String
var current_level: int
var target_level: int
var currency: int
var premium_cost: int
var requirements: Array[Dictionary] = []


## 将已验证的配置转换为单级强化规则，商城预算只作展示，不重复扣紫晶。
## [param id] 接合器定义ID。
## [param row] 已经过材料和预算校验的阶段配置。
func _init(id: String, row: Dictionary) -> void:
	definition_id = id
	current_level = int(row.current_level)
	target_level = int(row.target_level)
	currency = int(row.currency)
	premium_cost = int(row.premium_cost)
	for material: Dictionary in row.premium_materials + row.normal_materials:
		requirements.append({"definition_id": material.definition_id, "quantity": int(material.quantity)})


## 限定方案只能用于对应接合器的当前一级，防止跳级或跨类型套用配方。
## [param equipment] 玩家拥有的接合器实例。
## 返回装备、阶段或锁定校验结果。
func validate(equipment: VehicleEquipment) -> DomainResult:
	if equipment == null or equipment.definition_id != definition_id or equipment.upgrade_level != current_level:
		return DomainResult.failure(&"upgrade.stale", "接合器或强化等级已变化，请刷新后重试")
	return equipment.validate_attachment_upgrade(target_level)
