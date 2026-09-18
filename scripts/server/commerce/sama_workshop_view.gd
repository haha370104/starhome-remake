class_name SamaWorkshopView
extends RefCounted


## 汇总目标、转出来源及按原版颜色区分的工坊供给。
## [param player] 权威玩家。[param catalog] 目录。[param operation] 操作选择。
## 返回无领域对象引用的窗口视图。
static func build(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	var items: Array = player.inventory.items()
	items.append_array(player.vehicle.loadout.items())
	for item: GameItem in items:
		if not item is VehicleEquipment or item.sama_profile == null: continue
		var row := item.to_view_dictionary()
		row.presentation = item.presentation_for("inventory")
		row.installed = player.inventory.find(item.instance_id) == null
		row.attribute_summary = row.description
		equipment.append(row)
		if not row.installed and String(operation.get("mode", "growth")) == "transfer": materials.append(row.duplicate(true))
	for id: String in catalog.sama_rules.offers:
		var offer := catalog.sama_rules.offers[id]
		var prefix := "[%s] " % ["白色", "绿色", "蓝色", "紫色"][offer.color] if catalog.sama_rules.profiles.has(offer.definition_id) else ""
		offers.append({"definition_id": id, "display_name": prefix + catalog.display_name(offer.definition_id), "unit_price": offer.unit_price, "max_quantity": int(catalog.definition(offer.definition_id).get("max_stack", 1))})
	return {"equipment": equipment, "materials": materials, "offers": offers, "currency": player.inventory.currency,
		"amethyst": player.amethyst.balance(), "preview": _preview(player, catalog, operation), "operation": operation.duplicate(true)}


## 展示与提交共享的实际费用、结果及转移销毁后果。
## [param player] 玩家。[param catalog] 目录。[param operation] 操作。
## 返回安全报价，不包含独立成长候选。
static func _preview(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var mode := String(operation.get("mode", "growth"))
	var quote := PlayerSamaActions.quote(player, catalog, String(operation.get("instance_id", "")), mode, String(operation.get("material_id", "")))
	if not quote.is_ok: return {"can_execute": false, "text": quote.error_message}
	var lines := PackedStringArray(["100%成功；目标颜色不变。"])
	lines.append("阶段 %d → %d；品质 %d → %d" % [quote.value.before.get("growth", 0), quote.value.after.get("growth", 0), quote.value.before.get("quality", 0), quote.value.after.get("quality", 0)])
	if mode == "transfer": lines.append("转出装备「%s」将消失！\n目标原阶段和品质将被覆盖（可能降低）。\n消耗紫晶 %d（持有 %d）。" % [quote.value.donor_name, quote.value.amethyst, player.amethyst.balance()])
	for cost: Dictionary in quote.value.costs:
		lines.append("%s ×%d（持有%d）" % [catalog.display_name(cost.definition_id), cost.quantity, cost.available])
	if (quote.value.candidate as VehicleEquipment).bound: lines.append("完成后装备绑定。")
	if not quote.value.can_execute: lines.append("材料或紫晶不足。")
	quote.value.erase("candidate")
	quote.value.text = "\n".join(lines)
	return quote.value
