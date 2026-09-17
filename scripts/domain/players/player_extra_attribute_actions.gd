class_name PlayerExtraAttributeActions
extends RefCounted


## 根据装备自己的通道资格报价，不接受客户端提供的价格、增量或成功率。
## [param player] 隔离玩家聚合。
## [param id] 背包装备实例。
## [param material_id] 萤石或耀石实例。
## 返回可执行性、完整消耗及成功/失败结果。
static func preview(player: Player, id: String, material_id: String) -> DomainResult:
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id) as ExtraAttributeMaterial
	if item == null or item.locked or item.durability <= 0 or item.extra_attribute_rules == null:
		return DomainResult.failure(&"extra.target_unavailable", "请先卸下装备并解除锁定，损坏装备须先维护")
	if material == null or material.locked:
		return DomainResult.failure(&"extra.material_unavailable", "请选择背包中未锁定的萤石或耀石")
	var rules := item.extra_attribute_rules
	var channel := rules.material(material.definition_id)
	var result := item.extra_attributes.preview(item.definition_id, channel, rules)
	if not result.is_ok: return result
	var requirements: Array[Dictionary] = channel.materials.duplicate(true)
	requirements.append({"definition_id": material.definition_id, "quantity": 1})
	var bound := item.bound
	var costs: Array[Dictionary] = []
	var affordable := player.inventory.currency >= channel.currency
	for requirement: Dictionary in requirements:
		var available := 0
		for owned: GameItem in player.inventory.items():
			if owned.definition_id == ItemDefinitionAliases.canonical(requirement.definition_id) and not owned.locked:
				available += owned.quantity
				bound = bound or owned.bound
		costs.append({"definition_id": requirement.definition_id, "quantity": requirement.quantity, "available": available})
		affordable = affordable and available >= int(requirement.quantity)
	result.value.merge({"requirements": requirements, "costs": costs, "currency": channel.currency,
		"bound": bound, "can_execute": affordable, "reason": "" if affordable else "加工材料或星际币不足"})
	return result


## 先生成独立成长候选，再一次扣完费用，成功或失败只结算一次。
## [param player] 玩家聚合。
## [param id] 背包装备实例。
## [param material_id] 材料实例。
## [param revision] 确认时库存版本。
## [param roll] 权威随机样本。
## 返回实际成长和消耗；无效操作不改变装备、金币或材料。
static func execute(player: Player, id: String, material_id: String, revision: int, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	var quote := preview(player, id, material_id)
	if not quote.is_ok: return quote
	if not quote.value.can_execute:
		return DomainResult.failure(&"extra.requirements", quote.value.reason)
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id) as ExtraAttributeMaterial
	var candidate: ExtraAttributes = ExtraAttributes.restore(item.extra_attributes.to_dictionary()).value
	var applied := candidate.apply(item.definition_id, item.extra_attribute_rules.material(material.definition_id), item.extra_attribute_rules, roll)
	if not applied.is_ok: return applied
	var paid := player.inventory.pay_upgrade_cost(quote.value.requirements, quote.value.currency)
	if not paid.is_ok: return paid
	item.extra_attributes = candidate
	item.bound = quote.value.bound
	item.refresh_processed_stats()
	var outcome: Dictionary = applied.value
	outcome["materials"] = paid.value.materials
	outcome["message"] = "%s：%s，%d → %d 颗" % [material.display_name, "加工成功" if outcome.success else "加工失败，材料已消耗", outcome.before, outcome.actual_level]
	return DomainResult.ok(outcome)
