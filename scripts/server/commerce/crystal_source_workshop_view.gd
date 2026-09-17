class_name CrystalSourceWorkshopView
extends RefCounted


## 投影真实物品、供给和当前操作预览，隐藏领域候选与库存计划。
## [param player] 玩家聚合。[param catalog] 权威目录。[param operation] 最近选择与结算摘要。
## 返回纯JSON兼容窗口快照。
static func build(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var equipment: Array[Dictionary] = []
	var materials: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	var all_items: Array = player.inventory.items()
	all_items.append_array(player.vehicle.loadout.items())
	for item: GameItem in all_items:
		if not item is CrystalSourceCore and not (item is VehicleEquipment and item.crystal_source_profile != null): continue
		var row := item.to_view_dictionary()
		row["presentation"] = item.presentation_for("inventory")
		if item is CrystalSourceCore:
			materials.append(row)
		else:
			row["installed"] = player.inventory.find(item.instance_id) == null
			row["attribute_summary"] = String(row.description) + "\n" + _slots(item, catalog)
			equipment.append(row)
	for id: String in catalog.crystal_source_rules.offers:
		var definition := catalog.definition(id)
		offers.append({"definition_id": id, "display_name": definition.display_name,
			"unit_price": catalog.crystal_source_rules.offers[id], "max_quantity": int(definition.get("max_stack", 1))})
	return {"equipment": equipment, "materials": materials, "offers": offers, "currency": player.inventory.currency,
		"preview": _preview(player, catalog, operation), "operation": operation.duplicate(true)}


## 显示独立三个槽的内容与真实裂纹，不借用普通晶石孔的状态。
## [param item] 晶源体装备。[param catalog] 名称目录。
## 返回三行孔位说明。
static func _slots(item: VehicleEquipment, catalog: ItemCatalog) -> String:
	var lines := PackedStringArray()
	for index in 3:
		var slot := item.crystal_source.slots[index]
		lines.append("核槽%d：%s" % [index + 1, "空" if slot.definition_id.is_empty() else "%s（%d裂%s）" % [catalog.display_name(slot.definition_id), slot.cracks, "，绑定" if slot.bound else ""]])
	return "\n".join(lines)


## 将具体操作的领域预检转换成可确认的说明和可执行性。
## [param player] 玩家聚合。[param catalog] 规则目录。[param operation] 当前选项。
## 返回费用、概率与完整后果，不含可变领域引用。
static func _preview(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var id := String(operation.get("instance_id", ""))
	var material_id := String(operation.get("material_id", ""))
	var mode := String(operation.get("mode", "quality"))
	var quote: DomainResult
	var lines := PackedStringArray()
	if mode in ["quality", "growth"]:
		quote = PlayerCrystalSourceActions.growth_quote(player, catalog, id, mode, bool(operation.get("protected", false)))
		if not quote.is_ok: return _rejected(quote.error_message)
		lines.append("%s：%d → %d（最高15）" % ["品质" if mode == "quality" else "成长", quote.value.before, quote.value.after])
		lines.append("成功率：%.0f%%（复刻配置）" % (quote.value.chance * 100))
		lines.append("失败后等级：%d；仍消耗本次材料。" % quote.value.failed_after)
		if quote.value.protected: lines.append("已使用水晶稳定剂防止品质退级。")
		quote.value.erase("success_candidate")
		quote.value.erase("failure_candidate")
	elif mode == "compose":
		quote = PlayerCrystalSourceActions.composition_quote(player, catalog, material_id, int(operation.get("stabilizers", 0)), CrystalSourceService.new_id())
		if not quote.is_ok: return _rejected(quote.error_message)
		lines.append("晶源核五合一：%d → %d级\n成功率：%.0f%%\n失败消耗五枚核心与本次稳定剂。" % [quote.value.before, quote.value.after, quote.value.chance * 100])
		lines.append("同色同级核心从背包末尾开始选料：")
		for input: Dictionary in quote.value.inputs:
			lines.append("×%d，%d裂%s" % [input.quantity, input.cracks, "，绑定" if input.bound else ""])
		lines.append("成品保留%d裂%s；最高合成5级。" % [quote.value.cracks, "，绑定" if quote.value.bound else ""])
		quote.value.erase("success_plan")
		quote.value.erase("failure_plan")
	else:
		return _core_preview(player, catalog, operation)
	lines.append("\n本次消耗：")
	for cost: Dictionary in quote.value.costs:
		lines.append("%s ×%d（持有%d）" % [catalog.display_name(cost.definition_id), cost.quantity, cost.available])
	if not quote.value.can_execute: lines.append("\n" + String(quote.value.get("reason", "材料不足，请先补齐上方材料")))
	quote.value["text"] = "\n".join(lines)
	return quote.value


## 检查镶嵌或摘取并展示毁损后果；查询不执行支付。
## [param player] 玩家。[param catalog] 目录。[param operation] 核心与槽位选择。
## 返回操作预览。
static func _core_preview(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var checked := PlayerCrystalSourceActions.target(player, String(operation.get("instance_id", "")))
	if not checked.is_ok: return _rejected(checked.error_message)
	var item: VehicleEquipment = checked.value
	var index := int(operation.get("index", 0))
	if index < 0 or index >= 3: return _rejected("请选择一个晶源核槽")
	if operation.get("mode") == "inlay":
		var core := player.inventory.find(String(operation.get("material_id", ""))) as CrystalSourceCore
		var candidate: CrystalSourceGrowth = CrystalSourceGrowth.restore(item.crystal_source.to_dictionary()).value
		checked = candidate.inlay(index, core, catalog.crystal_source_rules)
		if not checked.is_ok: return _rejected(checked.error_message)
		return {"can_execute": true, "text": "核槽%d镶嵌：%s ×1\n裂纹保留%d道，绑定核心会绑定装备。\n每件同色限一枚，已存在其他两色不会被覆盖。" % [index + 1, core.display_name, core.cracks]}
	var slot := item.crystal_source.slots[index]
	if slot.definition_id.is_empty(): return _rejected("此晶源核槽为空")
	return {"can_execute": true, "text": "摘取核槽%d：%s\n%s\n不使用普通晶石的精密锤；核心槽保留。" % [index + 1, catalog.display_name(slot.definition_id),
		"已有三裂，本次摘取将销毁该晶源核！" if slot.cracks >= 3 else "摘取后裂纹：%d → %d；需有可用背包空间。" % [slot.cracks, slot.cracks + 1]]}


## 为不可执行的选择保留明确原因。
## [param message] 领域拒绝说明。
## 返回窗口安全预览。
static func _rejected(message: String) -> Dictionary:
	return {"can_execute": false, "text": message}
