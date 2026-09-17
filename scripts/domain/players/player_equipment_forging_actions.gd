class_name PlayerEquipmentForgingActions
extends RefCounted


## 预检锻造方向、全部费用和成功失败两种候选，不改变当前装备。
## [param player] 事务玩家。
## [param catalog] 权威目录。
## [param id] 未装配装备身份。
## [param material_id] 已选芯片身份。
## [param quantity] 一至三份同类芯片。
## 返回完整报价、独立候选和加工清除说明。
static func preview(player: Player, catalog: ItemCatalog, id: String, material_id: String, quantity: int) -> DomainResult:
	var item := player.inventory.find(id) as Equipment
	var material := player.inventory.find(material_id)
	if item == null or item.locked or item.durability <= 0 or item.forging_profile == null:
		return DomainResult.failure(&"forging.target", "请选择可锻造的背包装备，先卸装、解锁并维护")
	if material == null or material.locked or quantity < 1 or quantity > 3:
		return DomainResult.failure(&"forging.material", "请选择未锁定的锻造芯片，每次投入1～3个")
	var rules := catalog.forging_rules
	var channel := rules.material(material.definition_id)
	if channel == null: return DomainResult.failure(&"forging.material", "所选物品不是锻造芯片")
	var success := _candidate(item, catalog, channel, true)
	if not success.is_ok: return success
	var failure := _candidate(item, catalog, channel, false)
	if not failure.is_ok: return failure
	var requirements: Array[Dictionary] = channel.requirements.duplicate(true)
	requirements.append({"definition_id": material.definition_id, "quantity": quantity})
	var payment := player.inventory.quote_upgrade_cost(requirements, rules.currency_cost)
	var succeeded: Equipment = success.value
	var failed: Equipment = failure.value
	succeeded.bound = item.bound or bool(payment.bound_material)
	failed.bound = succeeded.bound
	return DomainResult.ok({"success_candidate": succeeded, "failure_candidate": failed,
		"label": channel.label, "before": item.forging.extensions.get(channel.type, 0),
		"after": succeeded.forging.extensions.get(channel.type, 0), "failed_after": failed.forging.extensions.get(channel.type, 0),
		"maximum": item.forging_profile.limits[channel.type], "direct_bonus": channel.direct_bonus,
		"chance": rules.chances[quantity - 1], "requirements": requirements, "currency": rules.currency_cost,
		"costs": payment.costs, "can_execute": payment.can_execute,
		"cleared_processing": item.processing.to_dictionary(), "discarded_rounds": item.magazine.remaining - succeeded.magazine.remaining,
		"reason": "" if payment.can_execute else "锻造芯片、合金或星际币不足"})


## 确认加工清除后原子扣费并替换装备，随机失败同样清除普通加工。
## [param player] 玩家聚合。
## [param catalog] 权威目录。
## [param id] 装备身份。
## [param material_id] 芯片身份。
## [param quantity] 投入份数。
## [param revision] 确认时库存版本。
## [param confirmed] 是否确认原版加工清除后果。
## [param roll] 服务端随机样本。
## 返回实际锻造变化和费用，预检失败不扣费。
static func execute(player: Player, catalog: ItemCatalog, id: String, material_id: String, quantity: int, revision: int, confirmed: bool, roll: float) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed or not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"forging.confirm", "请确认锻造将清除普通加工值及失败后果")
	var quote := preview(player, catalog, id, material_id, quantity)
	if not quote.is_ok: return quote
	if not quote.value.can_execute: return DomainResult.failure(&"forging.requirements", quote.value.reason)
	var success := roll < float(quote.value.chance)
	var candidate: Equipment = quote.value.success_candidate if success else quote.value.failure_candidate
	var replacements: Array[GameItem] = [candidate]
	var paid := InventoryTransformation.apply(player.inventory, replacements, PackedStringArray(), quote.value.requirements, quote.value.currency)
	if not paid.is_ok: return paid
	var after: int = quote.value.after if success else quote.value.failed_after
	paid.value.merge({"success": success, "before": quote.value.before, "after": after,
		"message": "%s锻造%s：+%d → +%d；普通加工已清除" % [quote.value.label, "成功" if success else "失败", quote.value.before, after]})
	return paid


## 通过物品工厂验证独立锻造候选，缩小弹仓时只裁去超出数量。
## [param item] 未修改的原装备。
## [param catalog] 同一权威目录。
## [param channel] 锻造方向。
## [param success] 本次候选结果。
## 返回完整候选或越界错误。
static func _candidate(item: Equipment, catalog: ItemCatalog, channel: EquipmentForgingRules.Channel, success: bool) -> DomainResult:
	var forging: EquipmentForging = EquipmentForging.restore(item.forging.to_dictionary()).value
	var applied := forging.apply(channel, item.forging_profile, success)
	if not applied.is_ok: return applied
	var state := item.to_view_dictionary()
	state.forging = forging.to_dictionary()
	state.processing = {}
	state.magazine = {"remaining": 0}
	var created := catalog.create(item.definition_id, state)
	if not created.is_ok: return created
	var candidate: Equipment = created.value
	candidate.magazine.remaining = mini(item.magazine.remaining, candidate.ammunition_capacity())
	return created
