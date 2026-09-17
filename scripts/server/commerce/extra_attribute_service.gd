class_name ExtraAttributeService
extends RefCounted

const COMMANDS := ["query_extra_attributes", "process_extra_attribute", "buy_extra_attribute_material"]
const LABELS := {"base_attack": "攻击", "double_damage_chance": "双倍伤害概率", "max_health": "生命",
	"armor": "防御", "movement_speed": "移动速度", "ammunition_capacity": "弹药容量"}
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 为额外属性加工组装原版目录和权威随机源。
## [param items] 只读物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 分派查询、加工和材料购买，价格与通道始终由目录决定。
## [param player] 外层事务隔离的玩家。
## [param command] 不可信用户意图。
## 返回操作结果或不提交的错误。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var result: DomainResult
	match action:
		"query_extra_attributes": result = DomainResult.ok({})
		"process_extra_attribute":
			result = PlayerExtraAttributeActions.execute(player, id, material_id, int(command.get("inventory_revision", -1)), _random.randf())
		"buy_extra_attribute_material":
			var definition_id := String(command.get("definition_id", ""))
			var quantity := int(command.get("quantity", 1))
			if _items.extra_attribute_rules.material(definition_id) == null or quantity < 1 or quantity > 99:
				return DomainResult.failure(&"extra.offer_invalid", "额外属性材料或数量无效")
			var created := _items.create(definition_id, {"instance_id": "extra." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": quantity})
			if not created.is_ok: return created
			result = PlayerWorkshopPurchases.purchase(player, created.value, int(_items.definition(definition_id).workshop_unit_price), int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"extra.unknown_command", "未知额外属性操作")
	if result.is_ok:
		result.value.merge({"action": action, "instance_id": id, "material_id": material_id}, true)
	return result


## 投影原图、各独立通道、金币商品及操作前后果，不在 UI 重算成功率。
## [param player] 当前聚合。
## [param operation] 已验证操作与选择。
## 返回额外加工窗口快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for channel: ExtraAttributeRules.Channel in _items.extra_attribute_rules.channels.values():
		offers.append({"definition_id": channel.material_id, "display_name": _items.display_name(channel.material_id),
			"unit_price": _items.definition(channel.material_id).workshop_unit_price})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is Equipment and not _items.extra_attribute_rules.allowed(item.definition_id).is_empty():
			row["installed"] = player.inventory.find(item.instance_id) == null
			var lines := PackedStringArray()
			for id: String in _items.extra_attribute_rules.allowed(item.definition_id):
				var channel: ExtraAttributeRules.Channel = _items.extra_attribute_rules.channels[id]
				lines.append("%s：%d / %d 颗" % [_items.display_name(channel.material_id), item.extra_attributes.level(id), channel.maximum])
			row["attribute_summary"] = "\n".join(lines)
			equipment.append(row)
		elif item is ExtraAttributeMaterial:
			materials.append(row)
	var quote := PlayerExtraAttributeActions.preview(player, String(operation.get("instance_id", "")), String(operation.get("material_id", "")))
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		var percent: bool = preview.attribute == "double_damage_chance"
		var points := float(preview.points) * (100 if percent else 1)
		var before := "%.2f%%" % (points * int(preview.before)) if percent else str(roundi(points * int(preview.before)))
		var after := "%.2f%%" % (points * int(preview.after)) if percent else str(roundi(points * int(preview.after)))
		var lines := PackedStringArray(["%s加成：%s → %s" % [LABELS[preview.attribute], before, after],
			"成功率：%d%%\n失败：%d → %d 颗；材料与费用均消耗。\n\n本次消耗：" % [roundi(float(preview.chance) * 100), preview.before, preview.failed_level]])
		for cost: Dictionary in preview.costs:
			lines.append("%s ×%d（持有 %d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
		lines.append("星际币：%d" % preview.currency)
		if not preview.can_execute: lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "preview": preview, "offers": offers,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
