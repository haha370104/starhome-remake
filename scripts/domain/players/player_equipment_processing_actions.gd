class_name PlayerEquipmentProcessingActions
extends RefCounted


## 预检背包装备、特殊材料、技能及普通材料；查询和执行共用同一套规则。
## [param player] 当前玩家聚合。
## [param id] 自有背包装备实例。
## [param material_id] 选择的加工材料实例。
## 返回可执行的加工报价，或不扣料的拒绝原因。
static func preview(player: Player, id: String, material_id: String) -> DomainResult:
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id)
	if item == null or item.locked or item.durability <= 0 or item.processing_rules == null:
		return DomainResult.failure(&"processing.target_unavailable", "请先卸下装备并解除锁定，损坏装备须先维护")
	if material == null or material.locked:
		return DomainResult.failure(&"processing.material_unavailable", "请选择未锁定的加工材料")
	var rules := item.processing_rules
	var profile := item.processing_profile()
	var special := rules.material(material.definition_id)
	var checked := item.processing.preview(profile, special)
	if not checked.is_ok:
		return checked
	var rule := profile.attributes[special.attribute]
	var requirements: Array[Dictionary] = rule.materials.duplicate(true)
	requirements.append({"definition_id": material.definition_id, "quantity": 1})
	var payment := player.inventory.quote_upgrade_cost(requirements, rule.currency)
	var affordable: bool = payment.can_execute
	var skill := player.skills.base_level(rules.skill_id)
	var enough_skill := skill >= rule.required_skill_level
	var result: Dictionary = checked.value.duplicate()
	result.merge({"requirements": requirements, "costs": payment.costs, "currency": rule.currency,
		"bound": item.bound or bool(payment.bound_material), "required_skill_level": rule.required_skill_level, "skill_level": skill,
		"label": rule.label, "limit": rule.limit, "chance": rules.success_chance,
		"can_execute": affordable and enough_skill,
		"reason": "" if affordable and enough_skill else ("加工技能等级不足" if not enough_skill else "加工材料或星际币不足")})
	return DomainResult.ok(result)


## 在一次背包事务中扣除全部费用并提交加工候选，失败不损坏装备。
## [param player] 当前玩家聚合。
## [param id] 装备实例。
## [param material_id] 材料实例。
## [param revision] 用户确认时背包版本。
## [param roll] 服务端生成的随机值。
## 返回本次成功、实际前后值与扣费摘要。
static func execute(player: Player, id: String, material_id: String, revision: int, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok:
		return checked
	if not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"processing.invalid_roll", "加工随机参数无效")
	var quote := preview(player, id, material_id)
	if not quote.is_ok:
		return quote
	if not quote.value.can_execute:
		return DomainResult.failure(&"processing.requirements", quote.value.reason)
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id)
	var candidate: EquipmentProcessing = EquipmentProcessing.restore(item.processing.to_dictionary()).value
	var applied := candidate.apply(item.processing_profile(), item.processing_rules.material(material.definition_id))
	if not applied.is_ok:
		return applied
	var paid := player.inventory.pay_upgrade_cost(quote.value.requirements, quote.value.currency)
	if not paid.is_ok:
		return paid
	var success := roll < float(quote.value.chance)
	item.bound = quote.value.bound
	if success:
		item.processing = candidate
		item.refresh_processed_stats()
	return DomainResult.ok({"success": success, "before": quote.value.before,
		"after": quote.value.after if success else quote.value.before, "materials": paid.value.materials,
		"message": "%s加工成功：%d → %d" % [quote.value.label, quote.value.before, quote.value.after] if success else "加工失败，材料已消耗，装备属性保持不变"})
