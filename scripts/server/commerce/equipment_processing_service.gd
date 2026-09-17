class_name EquipmentProcessingService
extends RefCounted

const COMMANDS := ["query_equipment_processing", "process_equipment_attribute"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 装配加工领域所需目录与权威随机源。
## [param items] 只读物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 只接受装备、材料与版本意图，忽略客户端提交的增量、价格和概率。
## [param player] 事务内隔离的玩家。
## [param command] 不可信命令。
## 返回待提交操作或拒绝原因。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var result: DomainResult
	match action:
		"query_equipment_processing":
			result = DomainResult.ok({})
		"process_equipment_attribute":
			result = PlayerEquipmentProcessingActions.execute(player, id, material_id, int(command.get("inventory_revision", -1)), _random.randf())
		_:
			return DomainResult.failure(&"processing.unknown_command", "未知基础加工操作")
	if result.is_ok:
		result.value.merge({"action": action, "instance_id": id, "material_id": material_id}, true)
	return result


## 投影装备、加工材料、原版上限以及服务端预检结果。
## [param player] 当前权威玩家。
## [param operation] 当前选择与操作结果。
## 返回只读快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		var profile: EquipmentProcessingRules.Profile = item.processing_profile() if item is Equipment else null
		if item is Equipment and profile != null:
			row["installed"] = player.inventory.find(item.instance_id) == null
			var attributes: PackedStringArray = []
			for rule: EquipmentProcessingRules.AttributeRule in profile.attributes.values():
				if rule.attribute != "ammunition_capacity":
					attributes.append("%s：%d / %d" % [rule.label, item.stat(rule.attribute), rule.limit])
			row["attribute_summary"] = "\n".join(attributes)
			equipment.append(row)
		elif _items.processing_rules.material(item.definition_id) != null:
			materials.append(row)
	var quote := PlayerEquipmentProcessingActions.preview(player, String(operation.get("instance_id", "")), String(operation.get("material_id", "")))
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		var lines := PackedStringArray(["%s：%d → %d（上限 %d）" % [preview.label, preview.before, preview.after, preview.limit],
			"加工技能：%d / %d" % [preview.skill_level, preview.required_skill_level], "", "本次消耗："])
		for cost: Dictionary in preview.costs:
			lines.append("%s ×%d（持有 %d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
		lines.append("星际币：%d\n成功率：%d%%（复刻配置）\n失败：仅消耗上述材料，属性不变。" % [preview.currency, roundi(float(preview.chance) * 100)])
		if not preview.can_execute:
			lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "preview": preview,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
