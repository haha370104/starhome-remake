class_name InventoryCraftingBatch
extends RefCounted

class Entry extends RefCounted:
	var item: GameItem
	var quantity := 0
	var position := Vector2i.ZERO

	## 为库存预演保存数量与位置，不复制或改写装备自身的成长状态。
	## [param value] 原库存或新产物实例。
	func _init(value: GameItem) -> void:
		item = value
		quantity = value.quantity
		position = value.position_px

class Plan extends RefCounted:
	var owner: Inventory
	var revision := -1
	var entries: Array[Entry] = []


## 预演整轮材料消耗、多堆合并和产物落位，任一步失败均不改写物品引用。
## [param inventory] 本轮唯一目标库存。
## [param requirements] 领域配方生成的整轮耗材。
## [param products] 已由服务端随机并通过目录创建的独立产物。
## 返回仅适用于当前库存版本的提交计划。
static func prepare(inventory: Inventory, requirements: Array[Dictionary], products: Array[GameItem]) -> DomainResult:
	if inventory == null:
		return DomainResult.failure(&"manufacturing.inventory", "生产背包无效")
	var checked := inventory._validate_requirements(requirements)
	if not checked.is_ok: return checked
	var plan := Plan.new()
	plan.owner = inventory
	plan.revision = inventory.revision
	for item: GameItem in inventory.items(): plan.entries.append(Entry.new(item))
	var requested: Dictionary = checked.value
	for definition_id: String in requested:
		var remaining := int(requested[definition_id])
		for index in range(plan.entries.size() - 1, -1, -1):
			var entry := plan.entries[index]
			if entry.item.definition_id != definition_id or entry.item.locked: continue
			var amount := mini(remaining, entry.quantity)
			entry.quantity -= amount
			remaining -= amount
			if remaining == 0: break
	var identities: Dictionary = {}
	for item: GameItem in products:
		if item == null or item.instance_id.is_empty() or item.quantity <= 0 or item.quantity > item.max_stack \
			or inventory.find(item.instance_id) != null or identities.has(item.instance_id):
			return DomainResult.failure(&"manufacturing.product", "生产产物身份或数量无效")
		identities[item.instance_id] = true
		var remaining := item.quantity
		for entry: Entry in plan.entries:
			if entry.quantity <= 0 or not entry.item.can_stack_with(item): continue
			var amount := mini(remaining, maxi(0, entry.item.max_stack - entry.quantity))
			entry.quantity += amount
			remaining -= amount
			if remaining == 0: break
		if remaining == 0: continue
		var layouts: Array[Dictionary] = []
		for entry: Entry in plan.entries:
			if entry.quantity <= 0: continue
			var layout := entry.item.to_layout_dictionary()
			layout.position_px = [entry.position.x, entry.position.y]
			layouts.append(layout)
		if layouts.size() >= inventory.capacity:
			return DomainResult.failure(&"inventory.no_space", "背包空间不足以接收本轮全部产物")
		var position := InventoryLayout.first_available_position(layouts, item.footprint_px)
		if position.x < 0:
			return DomainResult.failure(&"inventory.no_space", "背包空间不足以接收本轮全部产物")
		var entry := Entry.new(item)
		entry.quantity = remaining
		entry.position = position
		plan.entries.append(entry)
	return DomainResult.ok(plan)


## 在同一库存的原版本上一次性提交数量与落位，不通过视图字典重建其他装备。
## [param inventory] 生成计划时的库存。
## [param plan] 可信领域预演结果，不能由网络反序列化。
## 返回是否完成整轮库存提交；旧计划和跨库存计划均拒绝。
static func commit(inventory: Inventory, plan: Plan) -> DomainResult:
	if plan == null or inventory != plan.owner:
		return DomainResult.failure(&"manufacturing.plan_owner", "生产计划不属于当前背包")
	var checked := inventory.require_revision(plan.revision)
	if not checked.is_ok: return checked
	var retained: Array[GameItem] = []
	for entry: Entry in plan.entries:
		entry.item.quantity = entry.quantity
		if entry.quantity <= 0: continue
		entry.item.position_px = entry.position
		entry.item.container_id = InventoryLayout.MAIN_CONTAINER_ID
		retained.append(entry.item)
	inventory._items = retained
	inventory.commit_transfer()
	return DomainResult.ok()
