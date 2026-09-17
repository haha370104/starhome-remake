class_name InventoryExchange
extends RefCounted

class Plan extends RefCounted:
	var items: Array[GameItem] = []
	var currency := 0
	var revision := 0
	var outputs: Array[Dictionary] = []


## 在独立库存副本中预演销毁一个唯一实例并入账多种材料，失败不触碰原引用。
## [param inventory] 当前库存。
## [param catalog] 物品工厂。
## [param removed_id] 待销毁的唯一物品。
## [param outputs] 规则生成的材料及数量。
## [param currency_cost] 原表费用。
## [param bound] 所有产物是否继承绑定。
## [param identity_seed] 服务端生成的事务随机身份前缀。
## 返回可原子提交的独立库存计划。
static func prepare(inventory: Inventory, catalog: ItemCatalog, removed_id: String, outputs: Array[Dictionary], currency_cost: int, bound: bool, identity_seed: String) -> DomainResult:
	var source := inventory.find(removed_id)
	if source == null or source.locked or source.quantity != 1 or source.max_stack != 1:
		return DomainResult.failure(&"dismantle.target", "请卸下并解锁要拆解的单件装备")
	if currency_cost < 0 or inventory.currency < currency_cost or identity_seed.is_empty():
		return DomainResult.failure(&"dismantle.cost", "星际币不足或交易身份无效")
	var candidate := Inventory.new(inventory.capacity, inventory.revision, inventory.currency - currency_cost)
	var copies: Array[GameItem] = []
	for item: GameItem in inventory.items():
		if item.instance_id == removed_id: continue
		var state := item.to_view_dictionary()
		state["quantity"] = item.quantity
		var copied := catalog.create(item.definition_id, state)
		if not copied.is_ok: return copied
		copies.append(copied.value)
	var restored := candidate.restore_items(copies)
	if not restored.is_ok: return restored
	var serial := 0
	for output: Dictionary in outputs:
		var count := int(output.get("quantity", 0))
		if count <= 0: return DomainResult.failure(&"dismantle.output", "返还数量无效")
		while count > 0:
			var identity := "%s.%d" % [identity_seed, serial]
			if inventory.find(identity) != null:
				return DomainResult.failure(&"dismantle.identity", "返还物品身份重复")
			var created := catalog.create(String(output.get("definition_id", "")), {"instance_id": identity, "bound": bound})
			if not created.is_ok: return created
			var item: GameItem = created.value
			item.quantity = mini(item.max_stack, count)
			count -= item.quantity
			serial += 1
			var added := candidate._add_reward_uncommitted(item)
			if not added.is_ok: return DomainResult.failure(&"dismantle.capacity", "背包空间不足以容纳所有可能返还，请先整理背包")
	var plan := Plan.new()
	plan.items = candidate.items()
	plan.currency = candidate.currency
	plan.revision = inventory.revision
	plan.outputs = outputs.duplicate(true)
	return DomainResult.ok(plan)


## 验证版本后一次性替换库存与余额；预演不会产生物品，重复提交不能再执行。
## [param inventory] 原聚合库存。
## [param plan] 同一事务内构造的独立计划，不接受网络反序列化。
## 返回结算材料清单。
static func commit(inventory: Inventory, plan: Plan) -> DomainResult:
	var checked := inventory.require_revision(plan.revision)
	if not checked.is_ok: return checked
	inventory._items = plan.items
	inventory.currency = plan.currency
	inventory.commit_transfer()
	return DomainResult.ok({"outputs": plan.outputs.duplicate(true)})
