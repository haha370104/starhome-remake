class_name PlayerEnhancementActions
extends RefCounted


## 在玩家所有权边界查询背包或已穿着服装。
## [param player] 当前玩家聚合。
## [param id] 装备实例标识。
## 返回自有服装，其他物品或其他玩家实例返回空。
static func clothing(player: Player, id: String) -> Clothing:
	var carried := player.inventory.find(id)
	if carried is Clothing:
		return carried as Clothing
	for item: Clothing in player.character_equipment.items():
		if item.instance_id == id:
			return item
	return null


## 强化前完整预检所有权、耐久、锁定、材料、版本和金币，再提交原子变更。
## [param player] 同一玩家一致性聚合。
## [param clothing_id] 自有人物装备实例。
## [param stone_id] 背包中具体材料实例。
## [param inventory_revision] 预期背包版本。
## [param state_revision] 预期玩家版本。
## 返回实际前后状态及消费结果。
static func enhance(player: Player, clothing_id: String, stone_id: String, inventory_revision: int, state_revision: int) -> DomainResult:
	var checked := _revision(player, inventory_revision, state_revision)
	if not checked.is_ok:
		return checked
	var item := clothing(player, clothing_id)
	checked = _usable(item)
	if not checked.is_ok:
		return checked
	var stone := player.inventory.find(stone_id) as EnhancementStone
	var preview := item.enhancement.preview(stone)
	if not preview.is_ok:
		return preview
	var price := enhancement_price(stone, item)
	if player.inventory.currency < price:
		return DomainResult.failure(&"enhancement.currency", "星际币不足")
	var consumed := player.inventory.remove_quantity(stone_id, 1)
	if not consumed.is_ok:
		return consumed
	item.enhancement.apply_stone(stone)
	item.bound = item.bound or stone.bound
	player.inventory.currency -= price
	return DomainResult.ok({"action": "enhance_clothing", "instance_id": clothing_id,
		"before": preview.value.before, "after": preview.value.after, "currency_cost": price})


## 合成同类材料，背包空间不足时由既有制作事务回滚材料，成功后才扣金币。
## [param player] 当前玩家聚合。
## [param stone] 玩家背包中用于选择配方的材料。
## [param product] 权威目录创建的下一档材料。
## [param inventory_revision] 预期背包版本。
## [param state_revision] 预期玩家版本。
## 返回产物信息及实际消耗。
static func synthesize(player: Player, stone: EnhancementStone, product: EnhancementStone, inventory_revision: int, state_revision: int) -> DomainResult:
	var checked := _revision(player, inventory_revision, state_revision)
	if not checked.is_ok:
		return checked
	if stone == null or stone.locked or player.inventory.find(stone.instance_id) != stone \
		or product == null or stone.next_definition_id() != product.definition_id or product.quantity != 1:
		return DomainResult.failure(&"enhancement.synthesis", "材料不可合成或已达上限")
	var price := synthesis_price(stone)
	if player.inventory.currency < price:
		return DomainResult.failure(&"enhancement.currency", "星际币不足")
	# 混入任何绑定原料时，产物继续绑定，不能借合成洗掉绑定状态。
	for input: GameItem in player.inventory.items():
		if input.definition_id == stone.definition_id and not input.locked:
			product.bound = product.bound or input.bound
	var crafted := player.inventory.craft_product([{"definition_id": stone.definition_id,
		"quantity": stone.synthesis_count()}], product)
	if not crafted.is_ok:
		return crafted
	player.inventory.currency -= price
	return DomainResult.ok({"action": "synthesize_enhancement", "definition_id": product.definition_id,
		"quantity": 1, "currency_cost": price, "consumed": stone.synthesis_count()})


## 在两个同部位人物装备之间移动整条宝石路线，目标须为空且均可操作。
## [param player] 当前玩家聚合。
## [param source_id] 已有宝石的自有装备。
## [param target_id] 空路线的自有同部位装备。
## [param inventory_revision] 预期背包版本。
## [param state_revision] 预期玩家版本。
## 返回迁移结果；失败不扣金币或清空宝石。
static func transfer(player: Player, source_id: String, target_id: String, inventory_revision: int, state_revision: int) -> DomainResult:
	var checked := _revision(player, inventory_revision, state_revision)
	if not checked.is_ok:
		return checked
	var source := clothing(player, source_id)
	var target := clothing(player, target_id)
	if not _usable(source).is_ok or not _usable(target).is_ok or source == target \
		or source.character_slot != target.character_slot or source.enhancement.gem_stage == 0 or target.enhancement.gem_stage != 0:
		return DomainResult.failure(&"enhancement.transfer_rejected", "请选择可用的同部位装备，来源须有宝石且目标路线为空")
	var price := source.enhancement.gem_stage * 500
	if player.inventory.currency < price:
		return DomainResult.failure(&"enhancement.currency", "星际币不足")
	source.enhancement.transfer_gem_to(target.enhancement)
	target.bound = target.bound or source.bound
	player.inventory.currency -= price
	player.inventory.commit_transfer()
	return DomainResult.ok({"action": "transfer_clothing_gems", "source_id": source_id,
		"instance_id": target_id, "currency_cost": price})


## 明确重置宝石路线，保留两种词条且不返还已消耗宝石。
## [param player] 当前玩家聚合。
## [param id] 自有人物装备。
## [param inventory_revision] 预期背包版本。
## [param state_revision] 预期玩家版本。
## 返回重置结果；空路线或资金不足不扣费。
static func reset(player: Player, id: String, inventory_revision: int, state_revision: int) -> DomainResult:
	var checked := _revision(player, inventory_revision, state_revision)
	if not checked.is_ok:
		return checked
	var item := clothing(player, id)
	if not _usable(item).is_ok or item.enhancement.gem_stage == 0:
		return DomainResult.failure(&"enhancement.reset_rejected", "该装备没有可重置的宝石路线")
	if player.inventory.currency < 1000:
		return DomainResult.failure(&"enhancement.currency", "星际币不足")
	item.enhancement.reset_gem()
	player.inventory.currency -= 1000
	player.inventory.commit_transfer()
	return DomainResult.ok({"action": "reset_clothing_gems", "instance_id": id, "currency_cost": 1000})


## 查询本次单件镶嵌或词条刻印费用。
## [param stone] 已选择的材料。
## [param item] 待强化服装。
## 返回星际币费用，宝石按目标段数计价。
static func enhancement_price(stone: EnhancementStone, item: Clothing) -> int:
	return (item.enhancement.gem_stage + 1) * 100 if stone.family == "gem" else stone.rank * (200 if stone.family == "prefix" else 300)


## 查询一次材料合成的星际币费用。
## [param stone] 原料类型和当前等级。
## 返回按当前等级平方计价的费用。
static func synthesis_price(stone: EnhancementStone) -> int:
	return 100 * stone.rank * stone.rank


## 统一限制可操作的人物装备。
## [param item] 当前玩家拥有的服装。
## 返回非空、未锁定且有耐久的验证结果。
static func _usable(item: Clothing) -> DomainResult:
	if item == null or item.locked or item.durability <= 0:
		return DomainResult.failure(&"enhancement.clothing_unavailable", "请选择未锁定且有耐久的人物装备")
	return DomainResult.ok()


## 防止强化、合成、重置及迁移命令重放。
## [param player] 权威玩家聚合。
## [param inventory_revision] 客户端背包版本。
## [param state_revision] 客户端玩家版本。
## 返回两个版本均匹配时成功。
static func _revision(player: Player, inventory_revision: int, state_revision: int) -> DomainResult:
	if player.revision != state_revision:
		return DomainResult.failure(&"player.revision_conflict", "玩家状态已变化，请刷新后重试")
	return player.inventory.require_revision(inventory_revision)
