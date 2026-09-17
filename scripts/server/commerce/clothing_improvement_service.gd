class_name ClothingImprovementService
extends RefCounted

const COMMANDS := ["query_clothing_improvement", "improve_clothing", "buy_clothing_improvement_item"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 注入同一权威目录与独立随机源。
## [param items] 受控物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 分派服装改良与材料购买，不接受客户端概率、价格或结果。
## [param player] 待提交的隔离玩家。
## [param command] 不可信选择意图。
## 返回领域结果或拒绝原因。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var quantity := int(command.get("material_quantity", 1))
	var result: DomainResult
	match action:
		"query_clothing_improvement": result = DomainResult.ok({})
		"improve_clothing":
			result = PlayerClothingImprovementActions.execute(player, id, material_id, quantity, int(command.get("inventory_revision", -1)), _random.randf())
		"buy_clothing_improvement_item":
			var definition_id := String(command.get("definition_id", ""))
			var count := int(command.get("quantity", 1))
			var price := _offer_price(definition_id, player.sex)
			var limit := int(_items.definition(definition_id).get("max_stack", 1))
			if price <= 0 or count < 1 or count > mini(9999, limit):
				return DomainResult.failure(&"clothing_improvement.offer", "请选择本角色可穿时装或仿生纤维；时装限购1件，纤维1～9999份")
			var created := _items.create(definition_id, {"instance_id": "clothing_improvement." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": count})
			if not created.is_ok: return created
			result = PlayerWorkshopPurchases.purchase(player, created.value, price, int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"clothing_improvement.command", "未知服装改良操作")
	if result.is_ok: result.value.merge({"action": action, "instance_id": id, "material_id": material_id, "material_quantity": quantity}, true)
	return result


## 为原版时装建立可用获取链，纤维使用原购买价，时装统一复刻定价。
## [param id] 商品定义。
## [param sex] 角色性别。
## 返回允许出售的单价；零表示不在售。
func _offer_price(id: String, sex: String) -> int:
	var definition := _items.definition(id)
	if definition.get("kind", "") == "clothing_improvement_material": return int(definition.workshop_unit_price)
	if _items.clothing_improvement_rules.slots.has(id) and definition.get("required_sex", "any") in [sex, "any"]: return 10000
	return 0


## 投影同一方向的改良、材料总量、整数概率和明确的失败规则。
## [param player] 已提交玩家。
## [param operation] 当前选择及操作摘要。
## 返回可序列化的加工界面快照。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for id: String in _items.definition_ids():
		var price := _offer_price(id, player.sex)
		if price > 0: offers.append({"definition_id": id, "display_name": _items.display_name(id), "unit_price": price, "max_quantity": int(_items.definition(id).get("max_stack", 1))})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.character_equipment.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is Clothing and _items.clothing_improvement_rules.slots.has(item.definition_id):
			row["installed"] = player.inventory.find(item.instance_id) == null
			var channel: ClothingImprovementRules.Channel = _items.clothing_improvement_rules.channels.get(item.improvement.attribute)
			row["attribute_summary"] = "改良 %d / 100\n%s" % [item.improvement.level, "尚未选定方向" if channel == null else "%s +%s" % [channel.label, str(channel.increment * item.improvement.level)]]
			equipment.append(row)
		elif item is ClothingImprovementMaterial: materials.append(row)
	var quote := PlayerClothingImprovementActions.preview(player, String(operation.get("instance_id", "")), String(operation.get("material_id", "")), int(operation.get("material_quantity", 1)))
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		var lines := PackedStringArray(["改良 %d → %d / 100\n%s：+%s → +%s\n成功率：%d%%\n本级100%%所需纤维：%d份\n\n失败消耗纤维，保留改良等级。\n首次成功后，只能继续同类改良。\n以上失败处理为复刻规则。\n\n本次消耗：" % [preview.before, preview.after, preview.attribute_label, str(preview.bonus_before), str(preview.bonus_after), roundi(float(preview.chance) * 100), preview.guaranteed_quantity]])
		for cost: Dictionary in preview.costs:
			lines.append("%s ×%d（持有 %d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
		if not preview.can_execute: lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "offers": offers, "preview": preview,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
