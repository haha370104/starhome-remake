class_name PlayerAustinActions
extends RefCounted


## 对自有背包装备建立独立成长候选和材料报价，不修改原物品。
## [param player] 玩家聚合。[param catalog] 目录。[param id] 装备身份。[param mode] 成长操作。
## [param index] 左右孔位。[param rune_id] 已选符文堆叠身份。
## 返回候选与可支付报价或前置失败。
static func quote(player: Player, catalog: ItemCatalog, id: String, mode: String, index: int, rune_id: String) -> DomainResult:
	var item := player.inventory.find(id) as VehicleEquipment
	if item == null or item.austin_profile == null or item.locked or item.durability <= 0:
		return DomainResult.failure(&"austin.target", "请选择背包中未锁定且完好的奥斯格兰装备；已穿戴的需先卸下")
	var rune: GameItem
	if mode == "inlay":
		rune = player.inventory.find(rune_id)
		if rune == null or rune.locked or not catalog.austin_rules.runes.has(rune.definition_id):
			return DomainResult.failure(&"austin.rune", "请选择背包中未锁定的专属符文")
	var growth: AustinGlensGrowth = AustinGlensGrowth.restore(item.austin_glens.to_dictionary()).value
	var changed := growth.change(mode, item.austin_profile, catalog.austin_rules, index, rune.definition_id if rune != null else "", rune.bound if rune != null else false)
	if not changed.is_ok: return changed
	var requirements: Array[Dictionary] = changed.value
	var payment := player.inventory.quote_upgrade_cost(requirements, 0)
	var state := item.to_view_dictionary()
	state.austin_glens = growth.to_dictionary()
	state.bound = item.bound or bool(payment.bound_material)
	var candidate := catalog.create(item.definition_id, state)
	if not candidate.is_ok: return candidate
	return DomainResult.ok({"candidate": candidate.value, "requirements": requirements, "costs": payment.costs,
		"can_execute": payment.can_execute, "before": item.austin_glens.to_dictionary(), "after": growth.to_dictionary()})


## 经明确确认后将支付与同身份成长替换合为一次库存事务。
## [param player] 玩家聚合。[param catalog] 目录。[param id] 装备身份。[param mode] 操作。
## [param index] 孔位。[param rune_id] 符文身份。[param revision] 背包版本。[param confirmed] 费用及永久镶嵌确认。
## 返回成功摘要或完全未扣费的失败。
static func execute(player: Player, catalog: ItemCatalog, id: String, mode: String, index: int, rune_id: String, revision: int, confirmed: bool) -> DomainResult:
	var checked := player.inventory.require_revision(revision)
	if not checked.is_ok: return checked
	if not confirmed: return DomainResult.failure(&"austin.confirm", "请确认本次消耗；符文镶入后不能摘取")
	var preview := quote(player, catalog, id, mode, index, rune_id)
	if not preview.is_ok: return preview
	var paid := player.inventory.transform_item(id, preview.value.candidate, preview.value.requirements, 0)
	if not paid.is_ok: return paid
	return DomainResult.ok({"message": "奥斯格兰%s完成" % {"color": "品质提升", "stage": "阶段成长", "base": "基础提升", "additional": "附加提升", "blessing": "祝福", "unlock": "开槽", "inlay": "符文镶嵌"}[mode]})
