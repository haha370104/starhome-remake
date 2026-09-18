class_name PlayerCentralActions
extends RefCounted


## 从实际持有物品推导操作，不接受客户端指定升级等级或材料成本。
## [param player] 玩家聚合。[param catalog] 目录。[param instance_id] 背包目标身份。
## 返回独立候选和消费报价，查询不改变状态。
static func quote(player: Player, catalog: ItemCatalog, instance_id: String) -> DomainResult:
	var item := player.inventory.find(instance_id)
	if item == null or item.locked or item.quantity != 1 or item.max_stack != 1:
		return DomainResult.failure(&"central.target", "请选择背包内未锁定的桥接模块、进化晶体或圣焱装备；已装配装备须先卸下")
	var next: PlayerCentralController = PlayerCentralController.restore(player.central.to_dictionary()).value
	var requirements: Array[Dictionary] = []
	var replacements: Array[GameItem] = []
	var removed := PackedStringArray()
	var message := ""
	var detail := ""
	var module: CentralRules.Module = catalog.central_rules.modules.get(item.definition_id)
	if module != null:
		var previous := next.grade(module.chip_id)
		var advanced := next.use_module(module)
		if not advanced.is_ok: return advanced
		message = "%s已%s" % [catalog.central_rules.chips[module.chip_id].display_name, "激活" if previous == 0 else "升级"]
		detail = "%s：%s → %d级\n消耗选中的%s ×1。" % [catalog.central_rules.chips[module.chip_id].display_name, "未激活" if previous == 0 else "%d级" % previous, module.target_grade, item.display_name]
		removed.append(item.instance_id)
	elif item.definition_id == catalog.central_rules.evolution_material:
		var evolved := next.evolve()
		if not evolved.is_ok: return evolved
		message = "中枢已进化为圣焱型"
		detail = "中枢核心：3级 → 圣焱型\n消耗%s ×1，永久解锁六个圣焱附属装备槽。" % item.display_name
		removed.append(item.instance_id)
	elif item is VehicleEquipment and item.central_profile != null:
		var growth: CentralGrowth = CentralGrowth.restore(item.central_growth.to_dictionary()).value
		var advanced := growth.advance(catalog.central_rules)
		if not advanced.is_ok: return advanced
		requirements.assign(advanced.value)
		var state := item.to_view_dictionary()
		state.central_growth = growth.to_dictionary()
		state.bound = item.bound or bool(player.inventory.quote_upgrade_cost(requirements, 0).bound_material)
		var created := catalog.create(item.definition_id, state)
		if not created.is_ok: return created
		replacements.append(created.value)
		message = "%s已升至%d阶" % [item.display_name, growth.grade]
		detail = "%s：%d → %d阶\n100%%成功。" % [item.display_name, item.central_growth.grade, growth.grade]
		for attribute: String in ["max_health", "energy_cannon_attack", "missile_attack"]:
			detail += "\n%s：%d → %d" % [{"max_health":"生命", "energy_cannon_attack":"能量炮", "missile_attack":"导弹"}[attribute], item.special_bonus(attribute), created.value.special_bonus(attribute)]
		if created.value.bound: detail += "\n完成后装备绑定。"
	else:
		return DomainResult.failure(&"central.target", "该物品不属于中枢系统")
	var payment := player.inventory.quote_upgrade_cost(requirements, 0)
	return DomainResult.ok({"controller":next, "replacements":replacements, "removed_ids":removed,
		"requirements":requirements, "costs":payment.costs, "can_execute":payment.can_execute,
		"message":message, "text":detail})


## 原子消费实际选中模块或成长材料，再提交对应永久事实。
## [param player] 玩家。[param catalog] 目录。[param id] 唯一物品。[param revision] 库存版本。[param confirmed] 消耗确认。
## 返回成功说明或完全无副作用的失败。
static func execute(player: Player, catalog: ItemCatalog, id: String, revision: int, confirmed: bool) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed: return DomainResult.failure(&"central.confirm", "请确认本次中枢操作及材料消耗")
	var preview := quote(player, catalog, id)
	if not preview.is_ok: return preview
	var paid := InventoryTransformation.apply(player.inventory, preview.value.replacements, preview.value.removed_ids, preview.value.requirements, 0)
	if not paid.is_ok: return paid
	player.central = preview.value.controller
	player.vehicle.central = player.central
	player.vehicle.central_rules = catalog.central_rules
	player.vehicle.reconcile_loadout_state(false)
	return DomainResult.ok({"message":preview.value.message})
