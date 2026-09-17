class_name PlayerClothingImprovementActions
extends RefCounted


## 检查目标时装与所选纤维，跨未锁定同类堆叠计算支付和绑定。
## [param player] 当前玩家聚合。
## [param id] 背包时装实例。
## [param material_id] 背包纤维实例。
## [param quantity] 本次纤维投入量。
## 返回报价及可执行性。
static func preview(player: Player, id: String, material_id: String, quantity: int) -> DomainResult:
	var item := player.inventory.find(id) as Clothing
	var material := player.inventory.find(material_id) as ClothingImprovementMaterial
	if item == null or item.locked or item.durability <= 0 or item.improvement_rules == null:
		return DomainResult.failure(&"clothing_improvement.target", "请卸下并解锁时装；损坏时装不能改良")
	if material == null or material.locked:
		return DomainResult.failure(&"clothing_improvement.material", "请选择未锁定的仿生纤维")
	var result := item.improvement.preview(item.definition_id, item.improvement_rules, material.improvement_attribute, quantity)
	if not result.is_ok: return result
	var payment := player.inventory.quote_upgrade_cost(result.value.requirements, 0)
	result.value.merge(payment)
	result.value["bound"] = item.bound or bool(payment.bound_material)
	result.value["reason"] = "" if payment.can_execute else "同类未锁定纤维不足"
	return result


## 原子结算一次改良；失败只消耗材料，方向和等级不变。
## [param player] 独立事务玩家。
## [param id] 目标时装实例。
## [param material_id] 仿生纤维实例。
## [param quantity] 跨堆叠投入总数。
## [param revision] 预览时库存版本。
## [param roll] 权威随机样本。
## 返回成长结果；校验失败不修改任何状态。
static func execute(player: Player, id: String, material_id: String, quantity: int, revision: int, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	var quote := preview(player, id, material_id, quantity)
	if not quote.is_ok: return quote
	if not quote.value.can_execute: return DomainResult.failure(&"clothing_improvement.requirements", quote.value.reason)
	var item := player.inventory.find(id) as Clothing
	var material := player.inventory.find(material_id) as ClothingImprovementMaterial
	var candidate: ClothingImprovement = ClothingImprovement.restore(item.improvement.to_dictionary()).value
	var applied := candidate.apply(item.definition_id, item.improvement_rules, material.improvement_attribute, quantity, roll)
	if not applied.is_ok: return applied
	var paid := player.inventory.pay_upgrade_cost(quote.value.requirements, 0)
	if not paid.is_ok: return paid
	item.improvement = candidate
	item.bound = quote.value.bound
	applied.value["message"] = "%s：%s，改良等级 %d → %d" % [item.display_name, "改良成功" if applied.value.success else "改良失败，纤维已消耗，等级保留", applied.value.before, applied.value.actual_level]
	return applied
