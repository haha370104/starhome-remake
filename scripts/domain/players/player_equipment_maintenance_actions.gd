class_name PlayerEquipmentMaintenanceActions
extends RefCounted


## 预检常规维护的地点、背包装备与材料，维修报价由装备自身给出。
## [param player] 玩家聚合。
## [param id] 背包装备实例。
## [param rules] 权威维护目录。
## 返回报价、消耗和技能条件，或拒绝原因。
static func regular_preview(player: Player, id: String, rules: EquipmentMaintenanceRules) -> DomainResult:
	if player.map_id not in rules.maintenance_maps:
		return DomainResult.failure(&"maintenance.location", "常规维护请返回基地、城区或生产设施地图")
	var item := player.inventory.find(id) as Equipment
	if item == null:
		return DomainResult.failure(&"maintenance.backpack_required", "常规维护请先将装备卸到背包")
	var quote := item.maintenance_preview()
	if not quote.is_ok:
		return quote
	var profile := item.maintenance_profile
	var costs: Array[Dictionary] = []
	var affordable := player.inventory.currency >= profile.currency
	for cost: Dictionary in profile.materials:
		var available := player.inventory.count_consumable_definition(cost.definition_id)
		costs.append({"definition_id": cost.definition_id, "quantity": cost.quantity, "available": available})
		affordable = affordable and available >= int(cost.quantity)
	var level := player.skills.base_level(profile.skill_id) if not profile.skill_id.is_empty() else 0
	var enough_skill := level >= profile.required_skill_level
	quote.value.merge({"costs": costs, "currency": profile.currency, "skill_id": profile.skill_id,
		"required_skill_level": profile.required_skill_level, "skill_level": level, "experience": profile.experience,
		"can_execute": affordable and enough_skill, "reason": "" if affordable and enough_skill else ("裁缝等级不足" if not enough_skill else "维护材料或星际币不足")})
	return quote


## 原子扣除维护费用，再由装备提交预检过的状态变化。
## [param player] 玩家聚合。
## [param id] 背包装备实例。
## [param revision] 确认时背包版本。
## [param rules] 权威维护目录。
## 返回真实维修前后值及待发经验。
static func maintain(player: Player, id: String, revision: int, rules: EquipmentMaintenanceRules) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok:
		return checked
	var quote := regular_preview(player, id, rules)
	if not quote.is_ok:
		return quote
	if not quote.value.can_execute:
		return DomainResult.failure(&"maintenance.requirements", quote.value.reason)
	var item := player.inventory.find(id) as Equipment
	var bound := item.bound
	for cost: Dictionary in item.maintenance_profile.materials:
		for owned: GameItem in player.inventory.items():
			if owned.definition_id == ItemDefinitionAliases.canonical(cost.definition_id) and not owned.locked:
				bound = bound or owned.bound
	var paid := player.inventory.pay_upgrade_cost(item.maintenance_profile.materials, item.maintenance_profile.currency)
	if not paid.is_ok:
		return paid
	item.maintain()
	item.bound = bound
	quote.value["message"] = "维护完成：耐久 %d / %d" % [item.durability, item.max_durability]
	return quote


## 根据速修箱的单体、全装配或背包范围预检全部目标。
## [param player] 玩家聚合。
## [param id] 单体目标实例。
## [param tool_id] 背包中的速修箱实例。
## [param rules] 维护目录。
## 返回全部可修目标与预览，不把无目标的群修计作成功。
static func quick_preview(player: Player, id: String, tool_id: String, rules: EquipmentMaintenanceRules) -> DomainResult:
	var material := player.inventory.find(tool_id)
	var tool := rules.repair_tool(material.definition_id) if material != null else null
	if material == null or material.locked or tool == null:
		return DomainResult.failure(&"maintenance.tool_missing", "请选择背包中未锁定的速修箱")
	var candidates: Array[Equipment] = []
	if tool.scope == "backpack_one":
		var item := player.inventory.find(id) as Equipment
		if item != null: candidates.append(item)
	else:
		for item: VehicleEquipment in player.vehicle.loadout.items():
			if tool.scope == "installed_all" or item.instance_id == id:
				candidates.append(item)
	var targets: Array[Dictionary] = []
	for item: Equipment in candidates:
		var quote := item.maintenance_preview(tool)
		if quote.is_ok:
			quote.value.merge({"instance_id": item.instance_id, "display_name": item.display_name})
			targets.append(quote.value)
		elif tool.scope != "installed_all":
			return quote
	if targets.is_empty():
		return DomainResult.failure(&"maintenance.no_target", "没有可修复目标；电磁/光导箱用于已装配装备，离子箱用于背包装备")
	return DomainResult.ok({"targets": targets, "can_execute": true, "tool_definition": material.definition_id,
		"quantity": 1, "scope": tool.scope})


## 一只速修箱在一个事务内修复预检通过的目标，群体效果也只消费一次。
## [param player] 玩家聚合。
## [param id] 单体装备实例。
## [param tool_id] 速修箱实例。
## [param revision] 确认时背包版本。
## [param rules] 权威维护目录。
## 返回实际目标列表或不扣箱的拒绝。
static func quick_repair(player: Player, id: String, tool_id: String, revision: int, rules: EquipmentMaintenanceRules) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok:
		return checked
	var quote := quick_preview(player, id, tool_id, rules)
	if not quote.is_ok:
		return quote
	var material := player.inventory.find(tool_id)
	var tool := rules.repair_tool(material.definition_id)
	var paid := player.inventory.remove_quantity(tool_id, 1)
	if not paid.is_ok:
		return paid
	for target: Dictionary in quote.value.targets:
		var item := player.attachment_item(target.instance_id)
		item.maintain(tool)
		item.bound = item.bound or material.bound
	player.vehicle.reconcile_loadout_state(false)
	quote.value["message"] = "已速修 %d 件装备，耐久上限保持不变" % quote.value.targets.size()
	return quote
