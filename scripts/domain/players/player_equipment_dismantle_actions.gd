class_name PlayerEquipmentDismantleActions
extends RefCounted

class Quote extends RefCounted:
	var profile: EquipmentDismantleRules.Profile
	var plans: Array[InventoryExchange.Plan] = []
	var currency := 0


## 预检全部随机分支容量，避免通过背包不足筛选掉不喜欢的结果。
## [param player] 当前事务玩家。
## [param catalog] 权威规则目录。
## [param id] 背包中待拆解的实例。
## [param identity_seed] 服务端事务身份。
## 返回无副作用的拆解报价与各分支独立计划。
static func preview(player: Player, catalog: ItemCatalog, id: String, identity_seed: String) -> DomainResult:
	if identity_seed.is_empty(): return DomainResult.failure(&"dismantle.identity", "拆解事务身份不能为空")
	var item := player.inventory.find(id) as VehicleEquipment
	if item == null or item.locked:
		return DomainResult.failure(&"dismantle.target", "请卸下并解锁要拆解的战车装备")
	var profile: EquipmentDismantleRules.Profile = catalog.dismantle_rules.profiles.get(item.definition_id)
	if profile == null or item.quality.grade < profile.minimum_quality:
		return DomainResult.failure(&"dismantle.quality", "原表中的装备至少达到绿色品质才能拆解，可通过制造获得")
	if player.inventory.capacity - player.inventory.items().size() < catalog.dismantle_rules.minimum_free_slots:
		return DomainResult.failure(&"dismantle.capacity", "拆解前至少需要三个空背包位；返还超出单堆上限时还需更多空间")
	var bound := item.bound
	for index in item.sockets.capacity():
		bound = bound or item.sockets.slot_at(index).bound
	var quote := Quote.new()
	quote.profile = profile
	quote.currency = catalog.dismantle_rules.currency_cost
	for index in profile.outcomes.size():
		var prepared := InventoryExchange.prepare(player.inventory, catalog, id, profile.outcomes[index].materials, quote.currency, bound, identity_seed + ".%d" % index)
		if not prepared.is_ok: return prepared
		quote.plans.append(prepared.value)
	return DomainResult.ok(quote)


## 在确认全部销毁后依原表概率原子结算，无返还结果也消耗装备和费用。
## [param player] 当前玩家。
## [param catalog] 权威目录。
## [param id] 待拆实例。
## [param revision] 客户端库存版本。
## [param confirmed] 是否明确确认装备、晶石、全部成长消失。
## [param roll] 服务器0到1随机样本。
## [param identity_seed] 服务器独立随机身份。
## 返回带实际返还清单的操作结果。
static func execute(player: Player, catalog: ItemCatalog, id: String, revision: int, confirmed: bool, roll: float, identity_seed: String) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed or not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"dismantle.confirm", "请确认装备及其中全部晶石、成长将永久消失")
	var prepared := preview(player, catalog, id, identity_seed)
	if not prepared.is_ok: return prepared
	var quote: Quote = prepared.value
	var threshold := 0.0
	for index in quote.profile.outcomes.size():
		threshold += quote.profile.outcomes[index].probability
		if roll < threshold or index == quote.profile.outcomes.size() - 1:
			var result := InventoryExchange.commit(player.inventory, quote.plans[index])
			if result.is_ok: result.value.merge({"outcome_index": index, "currency": quote.currency, "message": "拆解完成，装备及全部成长已消耗" + ("；本次未获得材料" if quote.plans[index].outputs.is_empty() else "；材料已放入背包")})
			return result
	return DomainResult.failure(&"dismantle.rules", "拆解概率未覆盖全部结果")
