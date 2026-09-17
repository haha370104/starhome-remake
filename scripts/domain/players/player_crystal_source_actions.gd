class_name PlayerCrystalSourceActions
extends RefCounted


## 仅允许对自有、未锁定、完好的背包晶源体加工。
## [param player] 玩家聚合。[param id] 装备身份。
## 返回可加工装备或拒绝原因。
static func target(player: Player, id: String) -> DomainResult:
	var item := player.inventory.find(id) as VehicleEquipment
	if item == null or item.crystal_source_profile == null or item.locked or item.durability <= 0:
		return DomainResult.failure(&"crystal_source.target", "请选择背包中未锁定的晶源体；已装配的需先卸下，损坏的需先维护")
	return DomainResult.ok(item)


## 生成品质或成长完整报价，成功和失败使用独立候选，不修改库存。
## [param player] 玩家聚合。[param catalog] 物品目录。[param id] 装备身份。
## [param channel] quality或growth。[param protected] 是否使用品质稳定剂。
## 返回费用、概率、两种候选与明确的失败等级。
static func growth_quote(player: Player, catalog: ItemCatalog, id: String, channel: String, protected: bool) -> DomainResult:
	var checked := target(player, id)
	if not checked.is_ok: return checked
	var item: VehicleEquipment = checked.value
	var rules := catalog.crystal_source_rules
	var profile := item.crystal_source_profile
	var value := item.crystal_source
	var before := value.quality if channel == "quality" else value.growth
	var success: CrystalSourceGrowth = CrystalSourceGrowth.restore(value.to_dictionary()).value
	var advanced := success.advance(channel, true, protected, rules)
	if not advanced.is_ok: return advanced
	var failure: CrystalSourceGrowth = CrystalSourceGrowth.restore(value.to_dictionary()).value
	failure.advance(channel, false, protected, rules)
	var requirements: Array[Dictionary] = [{"definition_id": profile.crystal_id, "quantity": rules.crystal_costs[before]}]
	if channel == "quality":
		requirements.append({"definition_id": rules.five_color_id, "quantity": rules.five_color_costs[before]})
		if before >= 10: requirements.append({"definition_id": rules.seven_color_id, "quantity": rules.seven_color_costs[before - 10]})
		if protected: requirements.append({"definition_id": rules.quality_stabilizer_id, "quantity": 1})
	else:
		requirements.append({"definition_id": profile.source_id, "quantity": rules.source_costs[before]})
		if before >= 10: requirements.append({"definition_id": profile.advanced_source_id, "quantity": rules.advanced_source_costs[before - 10]})
	var payment := player.inventory.quote_upgrade_cost(requirements, 0)
	var candidates: Array[VehicleEquipment] = []
	for outcome: CrystalSourceGrowth in [success, failure]:
		var state := item.to_view_dictionary()
		state.crystal_source = outcome.to_dictionary()
		state.bound = item.bound or bool(payment.bound_material)
		var created := catalog.create(item.definition_id, state)
		if not created.is_ok: return created
		candidates.append(created.value)
	return DomainResult.ok({"requirements": requirements, "costs": payment.costs, "can_execute": payment.can_execute,
		"before": before, "after": before + 1, "failed_after": failure.quality if channel == "quality" else failure.growth,
		"chance": rules.quality_chances[before] if channel == "quality" else rules.growth_chance,
		"success_candidate": candidates[0], "failure_candidate": candidates[1], "protected": protected})


## 确认风险后原子消费成长材料并替换同一身份的装备。
## [param player] 玩家聚合。[param catalog] 目录。[param id] 装备身份。[param channel] 成长方向。
## [param protected] 品质保护。[param confirmed] 是否确认费用与失败风险。[param revision] 库存版本。[param roll] 服务端随机数。
## 返回成长结果，前置失败完全不扣费。
static func grow(player: Player, catalog: ItemCatalog, id: String, channel: String, protected: bool, confirmed: bool, revision: int, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed or not CrystalSourceRules.probability(roll) or roll >= 1:
		return DomainResult.failure(&"crystal_source.confirm", "请确认本次成长费用与失败风险")
	var quote := growth_quote(player, catalog, id, channel, protected)
	if not quote.is_ok: return quote
	var success := roll < float(quote.value.chance)
	var candidate: VehicleEquipment = quote.value.success_candidate if success else quote.value.failure_candidate
	var paid := player.inventory.transform_item(id, candidate, quote.value.requirements, 0)
	if not paid.is_ok: return paid
	var after: int = quote.value.after if success else quote.value.failed_after
	return DomainResult.ok({"success": success, "before": quote.value.before, "after": after,
		"message": "%s%s：%d → %d；已消耗本次材料" % ["品质" if channel == "quality" else "成长", "提升成功" if success else "提升失败", quote.value.before, after]})


## 一次性消费指定核心并在候选中完成镶嵌，失败不修改装备。
## [param player] 玩家聚合。[param catalog] 目录。[param id] 晶源体身份。
## [param core_id] 核心堆叠身份。[param index] 孔位。[param revision] 库存版本。
## 返回镶嵌结果。
static func inlay(player: Player, catalog: ItemCatalog, id: String, core_id: String, index: int, revision: int) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	checked = target(player, id)
	if not checked.is_ok: return checked
	var item: VehicleEquipment = checked.value
	var core := player.inventory.find(core_id) as CrystalSourceCore
	var candidate: CrystalSourceGrowth = CrystalSourceGrowth.restore(item.crystal_source.to_dictionary()).value
	var preview := candidate.inlay(index, core, catalog.crystal_source_rules)
	if not preview.is_ok: return preview
	var paid := player.inventory.remove_quantity(core_id, 1)
	if not paid.is_ok: return paid
	item.crystal_source = candidate
	item.bound = item.bound or core.bound
	return DomainResult.ok({"message": "晶源核镶嵌成功，装配后生效"})


## 预演摘取产物容量；已有三裂再次摘取须确认损毁，孔位始终保留。
## [param player] 玩家聚合。[param catalog] 目录。[param id] 装备身份。[param index] 孔位。
## [param confirmed] 三裂损毁确认。[param revision] 背包版本。[param product_id] 服务端生成的产物身份。
## 返回摘取结果，满包失败不清孔。
static func extract(player: Player, catalog: ItemCatalog, id: String, index: int, confirmed: bool, revision: int, product_id: String) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	checked = target(player, id)
	if not checked.is_ok: return checked
	var item: VehicleEquipment = checked.value
	if index < 0 or index >= 3 or item.crystal_source.slots[index].definition_id.is_empty():
		return DomainResult.failure(&"crystal_source.slot", "请选择已镶嵌的晶源核槽")
	var slot := item.crystal_source.slots[index]
	var destroyed := slot.cracks >= 3
	if destroyed and not confirmed: return DomainResult.failure(&"crystal_source.confirm", "该晶源核已有三裂，再次摘取将损毁，请确认")
	var products: Array[GameItem] = []
	if not destroyed:
		var created := catalog.create(slot.definition_id, {"instance_id": product_id, "quantity": 1,
			"bound": item.bound or slot.bound, "crystal_source_cracks": slot.cracks + 1})
		if not created.is_ok: return created
		products.append(created.value)
	var plan := InventoryCraftingBatch.prepare(player.inventory, [], products)
	if not plan.is_ok: return plan
	var paid := InventoryCraftingBatch.commit(player.inventory, plan.value)
	if not paid.is_ok: return paid
	item.crystal_source.slots[index] = CrystalSourceGrowth.Slot.new()
	return DomainResult.ok({"destroyed": destroyed, "message": "三裂晶源核已损毁，孔位保留" if destroyed else "晶源核已摘取到背包，裂纹增加一道"})


## 报价五合一，明确实际消耗的堆叠、继承裂纹和两种库存候选。
## [param player] 玩家聚合。[param catalog] 目录。[param core_id] 选定颜色等级的核心身份。
## [param stabilizers] 稳定剂数量。[param product_id] 服务端新产物身份。
## 返回概率、实际输入与库存预演计划；不修改库存。
static func composition_quote(player: Player, catalog: ItemCatalog, core_id: String, stabilizers: int, product_id: String) -> DomainResult:
	var core := player.inventory.find(core_id) as CrystalSourceCore
	if core == null or core.locked or core.profile.level >= 5:
		return DomainResult.failure(&"crystal_source.core", "请选择未锁定的1～4级晶源核；5级已到上限")
	var rules := catalog.crystal_source_rules
	var chance := rules.core_chances[core.profile.level - 1]
	var maximum_stabilizers := roundi((1.0 - chance) * 10)
	if stabilizers < 0 or stabilizers > maximum_stabilizers:
		return DomainResult.failure(&"crystal_source.stabilizers", "本次最多使用%d个晶源核稳定剂，成功率不超过100%%" % maximum_stabilizers)
	var requirements: Array[Dictionary] = [{"definition_id": core.definition_id, "quantity": 5}]
	if stabilizers > 0: requirements.append({"definition_id": rules.core_stabilizer_id, "quantity": stabilizers})
	var payment := player.inventory.quote_upgrade_cost(requirements, 0)
	var cracks := 0
	var remaining := 5
	var inputs: Array[Dictionary] = []
	var items := player.inventory.items()
	for index in range(items.size() - 1, -1, -1):
		var item := items[index] as CrystalSourceCore
		if item == null or item.locked or item.definition_id != core.definition_id: continue
		var amount := mini(remaining, item.quantity)
		inputs.append({"instance_id": item.instance_id, "quantity": amount, "cracks": item.cracks, "bound": item.bound})
		cracks = maxi(cracks, item.cracks)
		remaining -= amount
		if remaining == 0: break
	var next := rules.core_at(core.profile.color, core.profile.level + 1)
	var created := catalog.create(next.definition_id, {"instance_id": product_id, "quantity": 1, "crystal_source_cracks": cracks, "bound": payment.bound_material})
	if not created.is_ok: return created
	var success := InventoryCraftingBatch.prepare(player.inventory, requirements, [created.value])
	var failure := InventoryCraftingBatch.prepare(player.inventory, requirements, [])
	var executable: bool = payment.can_execute and success.is_ok and failure.is_ok
	return DomainResult.ok({"can_execute": executable, "reason": "" if executable else (success.error_message if not success.is_ok else "核心或稳定剂不足"),
		"requirements": requirements, "costs": payment.costs, "inputs": inputs, "cracks": cracks, "bound": payment.bound_material,
		"before": core.profile.level, "after": next.level, "chance": minf(1, chance + stabilizers * 0.1), "maximum_stabilizers": maximum_stabilizers,
		"success_plan": success.value, "failure_plan": failure.value})


## 在已完成成功容量预检后按权威随机结果提交五合一；失败同样消耗本轮材料。
## [param player] 玩家聚合。[param catalog] 目录。[param core_id] 核心身份。[param stabilizers] 稳定剂数量。
## [param revision] 库存版本。[param confirmed] 费用与失败确认。[param product_id] 新产物身份。[param roll] 权威随机数。
## 返回实际合成结果，旧请求、满包、缺料或未确认均不消耗。
static func compose(player: Player, catalog: ItemCatalog, core_id: String, stabilizers: int, revision: int, confirmed: bool, product_id: String, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed or not CrystalSourceRules.probability(roll) or roll >= 1:
		return DomainResult.failure(&"crystal_source.confirm", "请确认五合一失败也会消耗五枚核心与稳定剂")
	var quote := composition_quote(player, catalog, core_id, stabilizers, product_id)
	if not quote.is_ok: return quote
	if not quote.value.can_execute: return DomainResult.failure(&"crystal_source.materials", quote.value.reason)
	var success := roll < float(quote.value.chance)
	var paid := InventoryCraftingBatch.commit(player.inventory, quote.value.success_plan if success else quote.value.failure_plan)
	if not paid.is_ok: return paid
	return DomainResult.ok({"success": success, "message": "晶源核合成成功：%d级 → %d级；保留输入中的最高裂纹" % [quote.value.before, quote.value.after] if success else "合成失败，已消耗五枚核心和本次稳定剂"})
