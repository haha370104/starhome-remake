class_name EquipmentMaintenanceService
extends RefCounted

const COMMANDS := ["query_equipment_maintenance", "maintain_equipment", "quick_repair_equipment", "buy_maintenance_tool", "refill_equipment_ammunition"]
var _items: ItemCatalog
var _progression: Dictionary


## 组装维护目录与共享经验规则。
## [param items] 权威物品目录。
## [param progression] 正式技能经验配置。
func _init(items: ItemCatalog, progression: Dictionary) -> void:
	_items = items
	_progression = progression


## 编排维护与速修事务，裁缝经验进入既有奖励切面。
## [param player] 外层服务隔离的玩家聚合。
## [param command] 不可信操作意图。
## 返回操作结果或未提交错误。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var tool_id := String(command.get("material_id", ""))
	var mode := String(command.get("mode", "regular"))
	var result: DomainResult
	match action:
		"query_equipment_maintenance": result = DomainResult.ok({})
		"maintain_equipment":
			mode = "regular"
			result = PlayerEquipmentMaintenanceActions.maintain(player, id, int(command.get("inventory_revision", -1)), _items.maintenance_rules)
			if result.is_ok and int(result.value.experience) > 0:
				var reward := player.grant_skill_experience(result.value.skill_id, result.value.experience, _progression, "equipment_maintenance")
				if not reward.is_ok: return reward
		"quick_repair_equipment":
			mode = "quick"
			result = PlayerEquipmentMaintenanceActions.quick_repair(player, id, tool_id, int(command.get("inventory_revision", -1)), _items.maintenance_rules)
		"refill_equipment_ammunition":
			mode = "ammunition"
			result = PlayerAmmunitionActions.refill(player, id, int(command.get("inventory_revision", -1)), _items.maintenance_rules)
		"buy_maintenance_tool":
			var definition_id := String(command.get("definition_id", ""))
			var quantity := int(command.get("quantity", 1))
			if _items.maintenance_rules.repair_tool(definition_id) == null or quantity < 1 or quantity > 99:
				return DomainResult.failure(&"maintenance.offer", "速修工具或数量无效")
			var created := _items.create(definition_id, {"instance_id": "maintenance." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": quantity})
			if not created.is_ok: return created
			result = PlayerWorkshopPurchases.purchase(player, created.value, int(_items.definition(definition_id).get("workshop_unit_price", 0)), int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"maintenance.unknown_command", "未知维护操作")
	if result.is_ok:
		result.value.merge({"action": action, "instance_id": id, "material_id": tool_id, "mode": mode}, true)
	return result


## 输出装备当前耐久、工具与同版本操作报价。
## [param player] 当前权威玩家。
## [param operation] 当前选项与结果。
## 返回维护窗口快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for definition_id: String in _items.definition_ids():
		if _items.maintenance_rules.repair_tool(definition_id) != null:
			offers.append({"definition_id": definition_id, "display_name": _items.display_name(definition_id), "unit_price": _items.definition(definition_id).workshop_unit_price})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	all_items.append_array(player.character_equipment.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is Equipment:
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["attribute_summary"] = "耐久：%d / %d" % [item.durability, item.max_durability]
			if item.ammunition_capacity() > 0:
				row.attribute_summary += "\n弹药：%d / %d" % [item.magazine.remaining, item.ammunition_capacity()]
			equipment.append(row)
		elif _items.maintenance_rules.repair_tool(item.definition_id) != null:
			materials.append(row)
	var id := String(operation.get("instance_id", ""))
	var quick := String(operation.get("mode", "regular")) == "quick"
	var quote := PlayerEquipmentMaintenanceActions.quick_preview(player, id, String(operation.get("material_id", "")), _items.maintenance_rules) if quick else PlayerEquipmentMaintenanceActions.regular_preview(player, id, _items.maintenance_rules)
	if String(operation.get("mode", "regular")) == "ammunition":
		quote = PlayerAmmunitionActions.preview(player, id, _items.maintenance_rules)
		return {"equipment": equipment, "materials": [], "preview": quote.value if quote.is_ok else {"can_execute": false, "text": quote.error_message},
			"offers": offers, "currency": player.inventory.currency, "operation": operation.duplicate(true)}
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		var lines := PackedStringArray()
		if quick:
			lines.append("消耗 %s ×1\n耐久上限保持不变。\n" % _items.display_name(preview.tool_definition))
			for target: Dictionary in preview.targets:
				lines.append("%s：%d → %d / %d" % [target.display_name, target.before, target.after, target.maximum_after])
		else:
			lines.append("耐久：%d → %d\n耐久上限：%d → %d\n" % [preview.before, preview.after, preview.maximum_before, preview.maximum_after])
			for cost: Dictionary in preview.costs:
				lines.append("%s ×%d（持有 %d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
			lines.append("星际币：%d" % preview.currency)
			if not String(preview.skill_id).is_empty():
				lines.append("裁缝等级：%d / %d\n基础经验：%d" % [preview.skill_level, preview.required_skill_level, preview.experience])
			if preview.maximum_after < preview.maximum_before:
				lines.append("\n本次常规维护永久降低耐久上限。")
			if not preview.can_execute: lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "preview": preview, "offers": offers,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
