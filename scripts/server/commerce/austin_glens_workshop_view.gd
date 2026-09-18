class_name AustinGlensWorkshopView
extends RefCounted

const LABELS := {"color": "品质颜色", "stage": "成长阶段", "base": "基础属性", "additional": "附加能力", "blessing": "祝福", "unlock": "开启符文槽", "inlay": "永久镶入符文"}


## 汇总实际背包、已装配状态和唯一供给目录。
## [param player] 权威玩家。[param catalog] 目录。[param operation] 当前选择。
## 返回列表和操作预览，不包含领域候选。
static func build(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	var items: Array = player.inventory.items()
	items.append_array(player.vehicle.loadout.items())
	for item: GameItem in items:
		if not catalog.austin_rules.runes.has(item.definition_id) and not (item is VehicleEquipment and item.austin_profile != null): continue
		var row := item.to_view_dictionary()
		row.presentation = item.presentation_for("inventory")
		if catalog.austin_rules.runes.has(item.definition_id):
			materials.append(row)
		else:
			row.installed = player.inventory.find(item.instance_id) == null
			row.attribute_summary = description(item, catalog)
			equipment.append(row)
	for id: String in catalog.austin_rules.offers:
		var definition := catalog.definition(id)
		offers.append({"definition_id": id, "display_name": definition.display_name, "unit_price": catalog.austin_rules.offers[id], "max_quantity": int(definition.get("max_stack", 1))})
	return {"equipment": equipment, "materials": materials, "offers": offers, "currency": player.inventory.currency,
		"preview": _preview(player, catalog, operation), "operation": operation.duplicate(true)}


## 在物品属性后注明两孔的开启、固定许可符文及当前内容。
## [param item] 目标装备。[param catalog] 名称与规则目录。
## 返回完整详情。
static func description(item: VehicleEquipment, catalog: ItemCatalog) -> String:
	var text := String(item.to_view_dictionary().description)
	for index in 2:
		var slot := item.austin_glens.slots[index]
		var rune := catalog.austin_rules.rune_at(item.austin_profile.location, index)
		text += "\n%s槽：%s；限%s" % ["左" if index == 0 else "右", "未开启" if not slot.opened else ("空" if slot.rune_id.is_empty() else catalog.display_name(slot.rune_id)), catalog.display_name(rune.definition_id)]
	return text


## 将同一个领域预演转换成费用与确定结果，查询不推进成长。
## [param player] 玩家。[param catalog] 目录。[param operation] 当前选择。
## 返回安全预览。
static func _preview(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var mode := String(operation.get("mode", "color"))
	var quote := PlayerAustinActions.quote(player, catalog, String(operation.get("instance_id", "")), mode, int(operation.get("index", 0)), String(operation.get("material_id", "")))
	if not quote.is_ok: return {"can_execute": false, "text": quote.error_message}
	var lines := PackedStringArray(["%s：100%%成功" % LABELS[mode]])
	if mode in ["color", "stage", "base", "additional"]:
		lines.append("%d → %d" % [int(quote.value.before.get(mode, 0)), int(quote.value.after.get(mode, 0))])
	if mode == "inlay": lines.append("符文为永久安装，镶入后不能摘取；只能放入指定装备和孔位。")
	lines.append("本次消耗：")
	for cost: Dictionary in quote.value.costs:
		lines.append("%s ×%d（持有%d）" % [catalog.display_name(cost.definition_id), cost.quantity, cost.available])
	if (quote.value.candidate as VehicleEquipment).bound: lines.append("完成后装备保持或变为绑定。")
	if not quote.value.can_execute: lines.append("材料不足，请先补齐。")
	quote.value.erase("candidate")
	quote.value.text = "\n".join(lines)
	return quote.value
