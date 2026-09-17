class_name EquipmentMaintenance
extends RefCounted


## 检查装备自身维护资格并计算常规维修后的耐久与上限。
## [param equipment] 待修装备实例。
## 返回耐久前后值与上限损失，或无法维护的理由。
static func regular_preview(equipment: Equipment) -> DomainResult:
	var profile := equipment.maintenance_profile if equipment != null else null
	if equipment == null or equipment.locked or profile == null:
		return DomainResult.failure(&"maintenance.unavailable", "请选择未锁定的可维护装备")
	if not profile.regular_allowed:
		return DomainResult.failure(&"maintenance.forbidden", profile.reason if not profile.reason.is_empty() else "该装备不支持常规维护")
	if equipment.durability >= equipment.max_durability:
		return DomainResult.failure(&"maintenance.full", "装备耐久已满，无需维护")
	var maximum := maxi(1, equipment.max_durability - ceili(equipment.max_durability * profile.maximum_loss_fraction))
	return DomainResult.ok({"before": equipment.durability, "after": maximum,
		"maximum_before": equipment.max_durability, "maximum_after": maximum})


## 检查速修资格并计算恢复，保持耐久上限不变。
## [param equipment] 待修装备。
## [param tool] 已验证的工具规则。
## 返回恢复前后值或禁止原因。
static func quick_preview(equipment: Equipment, tool: EquipmentMaintenanceRules.RepairTool) -> DomainResult:
	if equipment == null or equipment.locked or equipment.maintenance_profile == null \
		or not equipment.maintenance_profile.quick_allowed or tool == null:
		return DomainResult.failure(&"maintenance.forbidden", "该工具不能修复此装备，普通护甲和服装不适用战车速修箱")
	if equipment.durability >= equipment.max_durability:
		return DomainResult.failure(&"maintenance.full", "装备耐久已满，无需速修")
	var amount := tool.amount if tool.kind == "points" else ceili(equipment.max_durability * tool.amount / 100.0)
	return DomainResult.ok({"before": equipment.durability, "after": mini(equipment.max_durability, equipment.durability + amount),
		"maximum_before": equipment.max_durability, "maximum_after": equipment.max_durability})


## 支付完成后应用已验证的维修结果，不改变加工、孔槽或绑定事实。
## [param equipment] 同一事务中的目标装备。
## [param quote] 本模块生成且未经外部修改的报价。
static func settle(equipment: Equipment, quote: Dictionary) -> void:
	equipment.max_durability = int(quote.maximum_after)
	equipment.durability = int(quote.after)
