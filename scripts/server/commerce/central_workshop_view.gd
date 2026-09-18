class_name CentralWorkshopView
extends RefCounted


## 展示芯片状态、六件装配和实际背包操作目标，并为未拥有装备的玩家提供起步供给。
## [param player] 玩家。[param catalog] 目录。[param operation] 当前选择。
## 返回无领域引用的JSON视图。
static func build(player: Player, catalog: ItemCatalog, operation: Dictionary) -> Dictionary:
	var rules := catalog.central_rules
	var chips: Array[Dictionary] = []
	var equipment: Array[Dictionary] = []
	var offers: Array[Dictionary] = []
	for id: String in CentralRules.CHIP_IDS:
		var grade := player.central.grade(id)
		var chip := rules.chips[id]
		var active := player.central.active(id, player.vehicle.loadout)
		var status := "未激活" if grade == 0 else "%d级 · %s" % [grade, "已生效" if active else "缺少完好对应部件"]
		var summary := "%s\n%s" % [chip.display_name, status]
		if grade > 0:
			var bonus: Dictionary = chip.bonuses[grade - 1]
			summary += "\n生命 +%d　炮攻 +%d　防御 +%d" % [bonus.max_health, bonus.energy_cannon_attack, bonus.defense]
		if id == "gun": summary += "\n致命一击3%/5%/7%；90%当前生命，上限本次普通伤害5倍。"
		else: summary += "\n原版战斗特效：本轮PVE范围暂缓。"
		chips.append({"id":id, "display_name":chip.display_name, "grade":grade, "active":active, "icon":chip.icon, "summary":summary})
	var owned: Array = player.inventory.items()
	owned.append_array(player.vehicle.loadout.items())
	for item: GameItem in owned:
		if not rules.modules.has(item.definition_id) and item.definition_id != rules.evolution_material and not rules.profiles.has(item.definition_id): continue
		var row := item.to_view_dictionary()
		row.presentation = item.presentation_for("inventory")
		row.installed = player.inventory.find(item.instance_id) == null
		row.attribute_summary = row.description
		equipment.append(row)
	for id: String in rules.offers:
		offers.append({"definition_id":id, "display_name":catalog.display_name(id), "unit_price":rules.offers[id], "max_quantity":int(catalog.definition(id).get("max_stack", 1))})
	var preview := PlayerCentralActions.quote(player, catalog, String(operation.get("instance_id", "")))
	var view := {"can_execute":false, "text":preview.error_message}
	if preview.is_ok:
		view = {"can_execute":preview.value.can_execute, "text":preview.value.text, "costs":preview.value.costs}
		for cost: Dictionary in preview.value.costs:
			view.text += "\n%s ×%d（持有%d）" % [catalog.display_name(cost.definition_id), cost.quantity, cost.available]
		if not preview.value.can_execute: view.text += "\n材料不足。"
	return {"chips":chips, "core_grade":player.central.core_grade(), "evolved":player.central.evolved,
		"equipment":equipment, "materials":[], "offers":offers, "currency":player.inventory.currency,
		"preview":view, "operation":operation.duplicate(true)}
