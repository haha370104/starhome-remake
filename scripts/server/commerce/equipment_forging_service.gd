class_name EquipmentForgingService
extends RefCounted

const COMMANDS := ["query_equipment_forging", "forge_equipment", "buy_equipment_forging_material"]
const SUPPLIES := ["forging_zirconium_scandium_alloy", "forging_nickel_iridium_alloy"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 装配独立锻造用例及权威随机源。
## [param items] 只读物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 仅接受选择意图、数量和确认，不接受客户端的概率与扩展值。
## [param player] 事务内隔离玩家。
## [param command] 网络边界意图。
## 返回操作摘要或无副作用的拒绝。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var quantity := int(command.get("material_quantity", 1))
	var result: DomainResult
	match action:
		"query_equipment_forging": result = DomainResult.ok({})
		"forge_equipment":
			result = PlayerEquipmentForgingActions.execute(player, _items, id, material_id, quantity, int(command.get("inventory_revision", -1)), command.get("confirm_processing_loss", false) == true, _random.randf())
		"buy_equipment_forging_material":
			var definition_id := String(command.get("definition_id", ""))
			var definition := _items.definition(definition_id)
			var count := int(command.get("quantity", 1))
			if (definition.get("kind", "") != "equipment_forging_material" and definition_id not in SUPPLIES) or count < 1 or count > 999:
				return DomainResult.failure(&"forging.offer", "锻造商品或数量无效")
			var product := _items.create(definition_id, {"instance_id": "forging." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": count})
			if not product.is_ok: return product
			result = PlayerWorkshopPurchases.purchase(player, product.value, int(definition.workshop_unit_price), int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"forging.command", "未知锻造操作")
	if result.is_ok: result.value.merge({"action": action, "instance_id": id, "material_id": material_id, "material_quantity": quantity}, true)
	return result


## 投影锻造扩展、原版概率、加工清除和全部费用；候选对象不会跨网络。
## [param player] 当前玩家。
## [param operation] 当前操作或选择。
## 返回加工窗口快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for id: String in _items.definition_ids():
		var definition := _items.definition(id)
		if definition.get("kind", "") == "equipment_forging_material" or id in SUPPLIES:
			offers.append({"definition_id": id, "display_name": definition.display_name, "unit_price": definition.workshop_unit_price, "max_quantity": 999})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is Equipment and item.forging_profile != null:
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["attribute_summary"] = EquipmentForgingDescription.describe(item, _items.forging_rules)
			equipment.append(row)
		elif _items.forging_rules.material(item.definition_id) != null: materials.append(row)
	var quote := PlayerEquipmentForgingActions.preview(player, _items, String(operation.get("instance_id", "")), String(operation.get("material_id", "")), int(operation.get("material_quantity", 1)))
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		preview.erase("success_candidate")
		preview.erase("failure_candidate")
		var lines := PackedStringArray(["%s扩展：+%d → +%d（最高+%d）" % [preview.label, preview.before, preview.after, preview.maximum],
			"成功率：%d%%\n失败：回退至+%d，材料和费用消耗。" % [roundi(float(preview.chance) * 100), preview.failed_after],
			"\n注意：成功或失败均清除全部普通加工！\n可先用升级机记忆模块提取加工值。"])
		if not preview.cleared_processing.get("increments", {}).is_empty(): lines.append("将清除：" + EquipmentForgingDescription.processing(preview.cleared_processing))
		if preview.discarded_rounds > 0: lines.append("弹仓缩小，超出容量的%d发弹药会丢弃。" % preview.discarded_rounds)
		lines.append("\n本次消耗：")
		for cost: Dictionary in preview.costs:
			lines.append("%s ×%d（持有%d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
		lines.append("星际币：%d\n扩展步长与失败回退量为复刻配置。" % preview.currency)
		if not preview.can_execute: lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "offers": offers, "preview": preview,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
