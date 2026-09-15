class_name AttachmentUpgradeService
extends RefCounted

var _pricing: AttachmentUpgradePricing
var _items: ItemCatalog


## 复用商城已校验的材料方案和物品身份，不另维护消耗表。
## [param pricing] 权威定价目录。
## [param items] 权威物品目录。
func _init(pricing: AttachmentUpgradePricing, items: ItemCatalog) -> void:
	_pricing = pricing
	_items = items


## 根据玩家自有实例确定唯一配方，再交由玩家聚合完成支付与属性变更。
## [param player] 外层事务创建的隔离聚合。
## [param command] 不可信客户端意图；只使用实例和版本。
## 返回强化结果或拒绝原因。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var id := String(command.get("instance_id", ""))
	var equipment := player.attachment_item(id)
	if equipment == null:
		return DomainResult.failure(&"upgrade.item_missing", "未找到该接合器")
	return player.upgrade_attachment(id, _pricing.plan_for(equipment.definition_id, equipment.upgrade_level),
		int(command.get("inventory_revision", -1)), int(command.get("loadout_revision", -1)))


## 汇总背包和已装配接合器的当前阶段、缺料和效果预览。
## [param player] 当前权威聚合。
## [param operation] 最近操作结果。
## 返回可用于窗口的独立投影。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = []
	var equipment_items: Array = player.inventory.items()
	equipment_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in equipment_items:
		if not item is VehicleEquipment or (item as VehicleEquipment).attachment_family not in ["old_joint", "new_joint"]:
			continue
		var equipment := item as VehicleEquipment
		var row := equipment.to_view_dictionary()
		row["presentation"] = equipment.presentation_for("inventory")
		row["installed"] = player.inventory.find(equipment.instance_id) == null
		row["requirements"] = []
		row["can_upgrade"] = false
		row["reason"] = "已达强化上限或未开放该型号"
		var plan := _pricing.plan_for(equipment.definition_id, equipment.upgrade_level)
		if plan != null:
			var checked := plan.validate(equipment)
			row["can_upgrade"] = checked.is_ok and player.inventory.currency >= plan.currency
			row["reason"] = checked.error_message if not checked.is_ok else ("星际币不足" if player.inventory.currency < plan.currency else "")
			row["target_level"] = plan.target_level
			row["currency_cost"] = plan.currency
			row["premium_cost"] = plan.premium_cost
			var values: Array = equipment.stat("attachment_values", [])
			row["effect_before"] = int(values[equipment.upgrade_level])
			row["effect_after"] = int(values[plan.target_level])
			for requirement: Dictionary in plan.requirements:
				var owned := player.inventory.count_consumable_definition(requirement.definition_id)
				row.requirements.append({"display_name": _items.display_name(requirement.definition_id),
					"quantity": requirement.quantity, "owned": owned})
				if owned < int(requirement.quantity):
					row["can_upgrade"] = false
					if String(row.reason).is_empty():
						row["reason"] = "材料不足（锁定材料不计入）"
		rows.append(row)
	return {"items": rows, "currency": player.inventory.currency, "operation": operation.duplicate(true)}
