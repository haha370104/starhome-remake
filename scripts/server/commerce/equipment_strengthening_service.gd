class_name EquipmentStrengtheningService
extends RefCounted

const COMMANDS := ["query_equipment_strengthening", "strengthen_equipment", "buy_equipment_strengthening_material"]
const LABELS := {"max_health": "生命", "base_attack": "攻击", "drive": "推进力"}
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 注入只读目录和服务端随机源。
## [param items] 权威物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 处理独立星级强化及商品购买，不接收客户端计算出的加值。
## [param player] 隔离玩家。
## [param command] 不可信选择意图。
## 返回操作结果或拒绝原因。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var quantity := int(command.get("material_quantity", 1))
	var result: DomainResult
	match action:
		"query_equipment_strengthening": result = DomainResult.ok({})
		"strengthen_equipment":
			result = PlayerEquipmentStrengtheningActions.execute(player, id, material_id, quantity, int(command.get("inventory_revision", -1)), _random.randf())
		"buy_equipment_strengthening_material":
			var definition_id := String(command.get("definition_id", ""))
			var count := int(command.get("quantity", 1))
			if _items.definition(definition_id).get("kind", "") != "equipment_strengthening_material" or count < 1 or count > 99:
				return DomainResult.failure(&"strengthening.offer", "强化石商品或数量无效")
			var product := _items.create(definition_id, {"instance_id": "strengthening." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": count})
			if not product.is_ok: return product
			result = PlayerWorkshopPurchases.purchase(player, product.value, int(_items.definition(definition_id).workshop_unit_price), int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"strengthening.command", "未知星级强化操作")
	if result.is_ok: result.value.merge({"action": action, "instance_id": id, "material_id": material_id, "material_quantity": quantity}, true)
	return result


## 投影装备星级、强化石、全部费用与失败退级，界面不解释原版字段。
## [param player] 当前玩家。
## [param operation] 已验证操作及当前选择。
## 返回独立强化快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for id: String in _items.definition_ids():
		var definition := _items.definition(id)
		if definition.get("kind", "") == "equipment_strengthening_material":
			offers.append({"definition_id": id, "display_name": definition.display_name, "unit_price": definition.workshop_unit_price})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is Equipment and item.strengthening_profile != null:
			row["installed"] = player.inventory.find(item.instance_id) == null
			var attribute: String = item.strengthening_profile.attribute
			row["attribute_summary"] = "独立强化：%d / 10 星\n%s加成：+%d" % [item.strengthening.level, LABELS[attribute], item.strengthening.bonus(attribute, item.strengthening_profile)]
			equipment.append(row)
		elif item is EquipmentStrengtheningMaterial:
			materials.append(row)
	var quote := PlayerEquipmentStrengtheningActions.preview(player, String(operation.get("instance_id", "")), String(operation.get("material_id", "")), int(operation.get("material_quantity", 1)))
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		var lines := PackedStringArray(["星级：%d → %d\n%s加成：+%d → +%d\n成功率：%d%%" % [preview.before, preview.after, LABELS[preview.attribute], preview.bonus_before, preview.bonus_after, roundi(float(preview.chance) * 100)],
			"失败：%d → %d 星；费用和材料消耗。\n\n本次消耗：" % [preview.before, preview.failed_level]])
		for cost: Dictionary in preview.costs:
			lines.append("%s ×%d（持有 %d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
		lines.append("星际币：%d" % preview.currency)
		if not preview.can_execute: lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "offers": offers, "preview": preview,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
