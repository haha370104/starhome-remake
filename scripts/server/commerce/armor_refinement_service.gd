class_name ArmorRefinementService
extends RefCounted

const COMMANDS := ["query_armor_refinement", "refine_armor", "buy_armor_refinement_item"]
var _items: ItemCatalog
var _random := RandomNumberGenerator.new()


## 注入受控目录与服务端随机源，客户端只提交选择。
## [param items] 同一权威物品目录。
func _init(items: ItemCatalog) -> void:
	_items = items
	_random.randomize()


## 分派护甲精工及材料购买，明确要求确认销毁后果。
## [param player] 隔离玩家候选。
## [param command] 不可信命令。
## 返回实际结算结果或明确拒绝原因。
func execute(player: Player, command: Dictionary) -> DomainResult:
	var action := String(command.get("type", ""))
	var id := String(command.get("instance_id", ""))
	var material_id := String(command.get("material_id", ""))
	var quantity := int(command.get("material_quantity", 1))
	var result: DomainResult
	match action:
		"query_armor_refinement": result = DomainResult.ok({})
		"refine_armor":
			result = PlayerArmorRefinementActions.execute(player, _items, id, material_id, quantity,
				int(command.get("inventory_revision", -1)), command.get("confirm_destruction", false) == true, _random.randf())
		"buy_armor_refinement_item":
			var definition_id := String(command.get("definition_id", ""))
			var count := int(command.get("quantity", 1))
			var price := _offer_price(definition_id)
			var definition := _items.definition(definition_id)
			if price <= 0 or count < 1 or count > mini(99, int(definition.get("max_stack", 1))):
				return DomainResult.failure(&"armor_refinement.offer", "商品不在精工目录内，护甲每次限购一件")
			var created := _items.create(definition_id, {"instance_id": "armor_refinement." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": count})
			if not created.is_ok: return created
			result = PlayerWorkshopPurchases.purchase(player, created.value, price, int(command.get("inventory_revision", -1)))
		_:
			return DomainResult.failure(&"armor_refinement.command", "未知护甲精工操作")
	if result.is_ok: result.value.merge({"action": action, "instance_id": id, "material_id": material_id, "material_quantity": quantity}, true)
	return result


## 只为精工材料及第一阶普通护甲提供完整获取链，赠品与高阶护甲不直接出售。
## [param id] 商品定义。
## 返回金币单价，零表示未在售。
func _offer_price(id: String) -> int:
	var definition := _items.definition(id)
	if definition.get("kind", "") == "armor_refinement_material": return int(definition.workshop_unit_price)
	var profile: ArmorRefinementRules.Profile = _items.armor_refinement_rules.profiles.get(id)
	if profile != null and profile.level == 1 and not profile.gift_bound:
		return int(definition.stats.purchase_value)
	return 0


## 展示阶级转换的实际防御、重量、耐久和孔数，失败销毁包括所有已嵌晶石。
## [param player] 当前已提交玩家。
## [param operation] 当前选择及操作摘要。
## 返回可安全序列化的窗口快照，不暴露候选领域对象。
func snapshot(player: Player, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for id: String in _items.definition_ids():
		var price := _offer_price(id)
		if price > 0: offers.append({"definition_id": id, "display_name": _items.display_name(id), "unit_price": price})
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is VehicleEquipment and item.armor_refinement_profile != null:
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["attribute_summary"] = "第%d阶 / 最高8阶\n防御：%d · 重量：%d · 孔位：%d" % [item.armor_refinement_profile.level, item.stat("armor"), item.weight, item.sockets.capacity()]
			equipment.append(row)
		elif item is ArmorRefinementMaterial:
			materials.append(row)
	var id := String(operation.get("instance_id", ""))
	var quote := PlayerArmorRefinementActions.preview(player, _items, id, String(operation.get("material_id", "")), int(operation.get("material_quantity", 1)))
	var preview := {"can_execute": false, "text": quote.error_message}
	if quote.is_ok:
		preview = quote.value.duplicate(true)
		var candidate: VehicleEquipment = preview.candidate
		preview.erase("candidate")
		var current: VehicleEquipment = player.inventory.find(id)
		var lines := PackedStringArray(["第%d阶 → 第%d阶\n%s\n防御：%d → %d\n重量：%d → %d\n孔位：%d → %d\n耐久：%d/%d → %d/%d\n成功率：%d%%" % [preview.before, preview.after, candidate.display_name,
			current.stat("armor"), candidate.stat("armor"), current.weight, candidate.weight, current.sockets.capacity(), candidate.sockets.capacity(),
			current.durability, current.max_durability, candidate.durability, candidate.max_durability, roundi(float(preview.chance) * 100)],
			"失败：护甲和其中所有晶石永久销毁；材料消耗。\n成功：保留已有孔槽、晶石及磨损。\n\n本次消耗："])
		for cost: Dictionary in preview.costs:
			lines.append("%s ×%d（持有 %d）" % [_items.display_name(cost.definition_id), cost.quantity, cost.available])
		if int(preview.currency) > 0: lines.append("星际币：%d" % preview.currency)
		if not preview.can_execute: lines.append("\n" + String(preview.reason))
		preview["text"] = "\n".join(lines)
	return {"equipment": equipment, "materials": materials, "offers": offers, "preview": preview,
		"currency": player.inventory.currency, "operation": operation.duplicate(true)}
