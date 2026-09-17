class_name PlayerEquipmentStrengtheningActions
extends RefCounted


## 预检背包装备、强化石和完整合金费用，星级规则由装备负责。
## [param player] 事务内玩家聚合。
## [param id] 背包装备实例。
## [param material_id] 强化石实例。
## [param quantity] 本次使用的强化石颗数。
## 返回完整报价与是否可执行。
static func preview(player: Player, id: String, material_id: String, quantity: int) -> DomainResult:
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id) as EquipmentStrengtheningMaterial
	if item == null or item.locked or item.durability <= 0:
		return DomainResult.failure(&"strengthening.target", "请卸下并解锁装备，损坏装备须先维护")
	if material == null or material.locked:
		return DomainResult.failure(&"strengthening.material", "请选择背包中未锁定的对应强化石")
	var result := item.strengthening.preview(item.strengthening_profile, item.strengthening_rules, material.definition_id, quantity)
	if not result.is_ok: return result
	var payment := player.inventory.quote_upgrade_cost(result.value.requirements, result.value.currency)
	result.value.merge(payment)
	result.value["bound"] = item.bound or bool(payment.bound_material)
	result.value["reason"] = "" if payment.can_execute else "强化材料或星际币不足"
	return result


## 以当前库存版本原子结算强化，失败只按原版策略降低星级。
## [param player] 玩家聚合。
## [param id] 装备实例。
## [param material_id] 强化石实例。
## [param quantity] 投入颗数。
## [param revision] 确认时库存版本。
## [param roll] 权威随机样本。
## 返回实际结果；未通过检查时不扣除任何物品。
static func execute(player: Player, id: String, material_id: String, quantity: int, revision: int, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	var quote := preview(player, id, material_id, quantity)
	if not quote.is_ok: return quote
	if not quote.value.can_execute:
		return DomainResult.failure(&"strengthening.requirements", quote.value.reason)
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id)
	var candidate: EquipmentStrengthening = EquipmentStrengthening.restore(item.strengthening.to_dictionary()).value
	var applied := candidate.apply(item.strengthening_profile, item.strengthening_rules, material.definition_id, quantity, roll)
	if not applied.is_ok: return applied
	var paid := player.inventory.pay_upgrade_cost(quote.value.requirements, quote.value.currency)
	if not paid.is_ok: return paid
	item.strengthening = candidate
	item.bound = quote.value.bound
	item.refresh_processed_stats()
	var result: Dictionary = applied.value
	result["materials"] = paid.value.materials
	result["message"] = "%s：%s，%d → %d 星" % [item.display_name, "强化成功" if result.success else "强化失败，费用已消耗", result.before, result.actual_level]
	return DomainResult.ok(result)
