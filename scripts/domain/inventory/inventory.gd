class_name Inventory
extends RefCounted

const InventoryLayoutScript := preload("res://scripts/domain/inventory/inventory_layout.gd")

var capacity: int
var revision: int
var currency: int
var _items: Array[GameItem] = []


## 检查余额后扣除正整数金币，失败不改变余额或版本。
## [param amount] 由权威业务规则确定的金币数量。
## 返回扣款结果；成功推进背包版本以拒绝旧交易。
func spend_currency(amount: int) -> DomainResult:
	if amount <= 0 or currency < amount:
		return DomainResult.failure(&"inventory.insufficient_currency", "星际币余额不足或扣款数量无效")
	currency -= amount
	revision += 1
	return DomainResult.ok()


## 初始化拥有容量、货币与独立乐观锁版本的背包。
## [param initial_capacity] 最大物品实例数量。
## [param initial_revision] 当前背包 revision。
## [param initial_currency] 当前货币数量。
func _init(
	initial_capacity: int = InventoryLayoutScript.ITEM_LIMIT,
	initial_revision: int = 0,
	initial_currency: int = 0,
) -> void:
	capacity = maxi(1, initial_capacity)
	revision = maxi(0, initial_revision)
	currency = maxi(0, initial_currency)


## 装载来自可信映射边界的物品，并验证整体布局。
## [param loaded_items] 已从配置目录还原类型的物品实例。
## 返回成功或布局、容量错误。
func restore_items(loaded_items: Array[GameItem]) -> DomainResult:
	if loaded_items.size() > capacity:
		return DomainResult.failure(&"inventory.capacity_exceeded", "inventory exceeds configured capacity")
	_items = loaded_items.duplicate()
	return InventoryLayoutScript.validate(layout_items())


## 查询物品实例，但不暴露内部数组的可变引用。
## 返回按当前布局顺序排列的浅副本。
func items() -> Array[GameItem]:
	return _items.duplicate()


## 按稳定实例标识查询物品。
## [param instance_id] 物品实例标识。
## 返回物品；不存在时返回 null。
func find(instance_id: String) -> GameItem:
	for item: GameItem in _items:
		if item.instance_id == instance_id:
			return item
	return null


## 校验 revision 后移动物品并推进背包版本。
## [param instance_id] 待移动物品实例标识。
## [param requested_position] 请求的容器局部像素坐标。
## [param expected_revision] 客户端读取到的背包 revision。
## 返回成功或版本、锁定、越界错误；允许与其他物品重叠。
func move_item(
	instance_id: String,
	requested_position: Vector2i,
	expected_revision: int,
) -> DomainResult:
	var revision_result := require_revision(expected_revision)
	if not revision_result.is_ok:
		return revision_result
	var moved := InventoryLayoutScript.move_item(layout_items(), instance_id, requested_position)
	if not moved.is_ok:
		return moved
	_apply_layouts(moved.value)
	revision += 1
	return DomainResult.ok()


## 校验 revision 后紧凑排列所有背包物品。
## [param expected_revision] 客户端读取到的背包 revision。
## 返回成功或版本、容量错误。
func arrange(expected_revision: int) -> DomainResult:
	var revision_result := require_revision(expected_revision)
	if not revision_result.is_ok:
		return revision_result
	var arranged := InventoryLayoutScript.arrange(layout_items())
	if not arranged.is_ok:
		return arranged
	_apply_layouts(arranged.value)
	revision += 1
	return DomainResult.ok()


## 为聚合内装备转移移除指定物品，不单独推进 revision。
## [param instance_id] 待移除物品实例标识。
## 返回被移除物品或不存在、锁定错误。
## 设计：该方法只供 Player 的原子换装流程调用，revision 由完整事务统一推进。
func remove_for_transfer(instance_id: String) -> DomainResult:
	for index in _items.size():
		var item: GameItem = _items[index]
		if item.instance_id != instance_id:
			continue
		if item.locked:
			return DomainResult.failure(&"inventory.item_locked", "locked inventory item cannot be equipped")
		_items.remove_at(index)
		return DomainResult.ok(item)
	return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")


## 为聚合内装备转移寻找位置并放回物品，不单独推进 revision。
## [param item] 待放回背包的物品实例。
## 返回成功或容量、空间错误。
## 设计：该方法与 remove_for_transfer 配对，由 Player 保证整个换装命令的事务边界。
func add_from_transfer(item: GameItem) -> DomainResult:
	var position_result := transfer_position(item)
	if not position_result.is_ok:
		return position_result
	item.container_id = InventoryLayoutScript.MAIN_CONTAINER_ID
	item.position_px = position_result.value
	_items.append(item)
	return DomainResult.ok()


## 将权威奖励物品合并到已有堆叠或放入首个可用背包位置。
## [param item] 已由受控物品目录创建且带唯一实例标识的奖励物品。
## 返回合并后的实例或容量、布局、数量错误。
## 设计：一次调用要么完整接收数量并推进 revision，要么完全不修改背包。
func add_reward(item: GameItem) -> DomainResult:
	var added := _add_reward_uncommitted(item)
	if added.is_ok:
		revision += 1
	return added


## 原子消耗一组配方材料，并只推进一次背包 revision。
## [param requirements] 含 definition_id 与 quantity 的材料要求数组。
## 返回各材料的消费摘要，或在任一材料不足时保持背包完全不变。
func consume_requirements(requirements: Array[Dictionary]) -> DomainResult:
	var checked := _validate_requirements(requirements)
	if not checked.is_ok:
		return checked
	var consumed := _consume_requirements_uncommitted(requirements)
	revision += 1
	return DomainResult.ok(consumed)


## 原子支付强化材料和金币；任一不足时保留背包全部状态。
## [param requirements] 权威规则中的材料及数量。
## [param currency_cost] 非负金币消耗，允许无金币配方。
## 返回支付摘要或拒绝原因。
func pay_upgrade_cost(requirements: Array[Dictionary], currency_cost: int) -> DomainResult:
	if currency_cost < 0 or currency < currency_cost:
		return DomainResult.failure(&"upgrade.currency_missing", "强化所需星际币不足")
	var checked := _validate_requirements(requirements)
	if not checked.is_ok:
		return checked
	var consumed := _consume_requirements_uncommitted(requirements)
	currency -= currency_cost
	revision += 1
	return DomainResult.ok({"materials": consumed, "currency": currency_cost})


## 为一次材料/金币交易报价，使用与支付相同的锁定和重复定义校验。
## [param requirements] 规则生成的材料要求。
## [param currency_cost] 非负金币报价。
## 返回各材料现有量、是否可支付及保守绑定传播标志，不改变库存。
func quote_upgrade_cost(requirements: Array[Dictionary], currency_cost: int) -> Dictionary:
	var costs: Array[Dictionary] = []
	var bound_material := false
	for requirement: Dictionary in requirements:
		var id := ItemDefinitionAliases.canonical(String(requirement.get("definition_id", "")))
		var available := 0
		for item: GameItem in _items:
			if item.definition_id == id and not item.locked:
				available += item.quantity
				bound_material = bound_material or item.bound
		costs.append({"definition_id": id, "quantity": int(requirement.get("quantity", 0)), "available": available})
	return {"costs": costs, "requirements": requirements.duplicate(true), "currency": currency_cost,
		"bound_material": bound_material, "can_execute": currency_cost >= 0 and currency >= currency_cost and _validate_requirements(requirements).is_ok}


## 在一个背包事务中消耗材料并加入制作产物。
## [param requirements] 含 definition_id 与 quantity 的材料要求数组。
## [param product] 已由物品目录创建的产物实例。
## 返回产物实例；材料不足、背包无空间或实例冲突时回滚全部变化。
## 设计：配方结算不能暴露“材料已扣但产物未入包”的中间状态。
func craft_product(requirements: Array[Dictionary], product: GameItem) -> DomainResult:
	var checked := _validate_requirements(requirements)
	if not checked.is_ok:
		return checked
	var previous_items := _items.duplicate()
	var previous_quantities: Dictionary = {}
	for item: GameItem in previous_items:
		previous_quantities[item.instance_id] = item.quantity
	_consume_requirements_uncommitted(requirements)
	var added := _add_reward_uncommitted(product)
	if not added.is_ok:
		_items = previous_items
		for item: GameItem in _items:
			item.quantity = int(previous_quantities[item.instance_id])
		return added
	revision += 1
	return added


## 在不推进 revision 的前提下合并或放置奖励；仅供复合背包事务调用。
## [param item] 已通过目录创建的待入包实例。
## 返回合并后的物品或容量、布局、实例错误。
func _add_reward_uncommitted(item: GameItem) -> DomainResult:
	if item == null or item.instance_id.is_empty() or item.quantity <= 0 \
		or item.quantity > item.max_stack:
		return DomainResult.failure(&"inventory.invalid_reward", "reward item identity or quantity is invalid")
	if find(item.instance_id) != null:
		return DomainResult.failure(&"inventory.duplicate_item", "reward item identity already exists")
	for current: GameItem in _items:
		if not current.can_stack_with(item) or current.quantity + item.quantity > current.max_stack:
			continue
		current.quantity += item.quantity
		return DomainResult.ok(current)
	var position_result := transfer_position(item)
	if not position_result.is_ok:
		return position_result
	item.container_id = InventoryLayoutScript.MAIN_CONTAINER_ID
	item.position_px = position_result.value
	_items.append(item)
	return DomainResult.ok(item)


## 预检配方材料格式、非锁定数量及重复定义。
## [param requirements] 待消费的配方材料数组。
## 返回规范化检查结果；失败不修改背包。
func _validate_requirements(requirements: Array[Dictionary]) -> DomainResult:
	var requested: Dictionary = {}
	for requirement: Dictionary in requirements:
		var definition_id := ItemDefinitionAliases.canonical(String(requirement.get("definition_id", "")))
		var quantity := int(requirement.get("quantity", 0))
		if definition_id.is_empty() or quantity <= 0 or requested.has(definition_id):
			return DomainResult.failure(&"manufacturing.invalid_requirements", "recipe requirements are invalid")
		requested[definition_id] = quantity
	for definition_id: String in requested:
		var available := 0
		for item: GameItem in _items:
			if item.definition_id == definition_id and not item.locked:
				available += item.quantity
		if available < int(requested[definition_id]):
			return DomainResult.failure(&"manufacturing.material_missing", "required material quantity is insufficient")
	return DomainResult.ok(requested)


## 扣除已经整体预检通过的材料，不推进 revision。
## [param requirements] 已通过 _validate_requirements 的材料数组。
## 返回各定义的实际扣除数量。
func _consume_requirements_uncommitted(requirements: Array[Dictionary]) -> Array[Dictionary]:
	var consumed: Array[Dictionary] = []
	for requirement: Dictionary in requirements:
		var definition_id := ItemDefinitionAliases.canonical(String(requirement["definition_id"]))
		var remaining := int(requirement["quantity"])
		for index: int in range(_items.size() - 1, -1, -1):
			var item: GameItem = _items[index]
			if item.definition_id != definition_id or item.locked:
				continue
			var amount := mini(item.quantity, remaining)
			item.quantity -= amount
			remaining -= amount
			if item.quantity == 0:
				_items.remove_at(index)
			if remaining == 0:
				break
		consumed.append({"definition_id": definition_id, "quantity": int(requirement["quantity"])})
	return consumed


## 按实例移除可交易物品，并推进背包 revision。
## [param instance_id] 待移除实例标识。
## [param quantity] 移除数量；装备通常为 1。
## 返回被移除的定义、数量和实例，供权威交易服务结算。
func remove_quantity(instance_id: String, quantity: int) -> DomainResult:
	if instance_id.is_empty() or quantity <= 0:
		return DomainResult.failure(&"inventory.invalid_quantity", "positive quantity is required")
	for index: int in _items.size():
		var item: GameItem = _items[index]
		if item.instance_id != instance_id:
			continue
		if item.locked:
			return DomainResult.failure(&"inventory.item_not_tradeable", "locked item cannot be sold")
		if item.quantity < quantity:
			return DomainResult.failure(&"inventory.insufficient_quantity", "item quantity is insufficient")
		var result := {
			"instance_id": item.instance_id,
			"definition_id": item.definition_id,
			"quantity": quantity,
		}
		item.quantity -= quantity
		if item.quantity == 0:
			_items.remove_at(index)
		revision += 1
		return DomainResult.ok(result)
	return DomainResult.failure(&"inventory.item_not_found", "inventory item does not exist")


## 统计背包内指定定义的总数量。
## [param definition_id] 稳定物品定义标识。
## 返回跨堆叠合计数量。
func count_definition(definition_id: String) -> int:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	var total := 0
	for item: GameItem in _items:
		if item.definition_id == definition_id:
			total += item.quantity
	return total


## 统计背包内能够被生产事务消耗的指定物品数量。
## [param definition_id] 稳定物品定义标识。
## 返回所有未锁定堆叠的合计数量。
func count_consumable_definition(definition_id: String) -> int:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	var total := 0
	for item: GameItem in _items:
		if item.definition_id == definition_id and not item.locked:
			total += item.quantity
	return total


## 消耗任务要求的指定定义，预检不足时不改变背包。
## [param definition_id] 稳定物品定义标识。
## [param quantity] 需要消耗的总量。
## 返回消耗数量和受影响实例；成功只推进一次 revision。
func consume_definition(definition_id: String, quantity: int) -> DomainResult:
	definition_id = ItemDefinitionAliases.canonical(definition_id)
	if definition_id.is_empty() or quantity <= 0:
		return DomainResult.failure(&"inventory.invalid_quantity", "positive quantity is required")
	if count_consumable_definition(definition_id) < quantity:
		return DomainResult.failure(&"inventory.insufficient_quantity", "required item quantity is insufficient")
	var remaining := quantity
	var consumed_instances := PackedStringArray()
	for index: int in range(_items.size() - 1, -1, -1):
		var item: GameItem = _items[index]
		if item.definition_id != definition_id or item.locked:
			continue
		var amount := mini(item.quantity, remaining)
		item.quantity -= amount
		remaining -= amount
		consumed_instances.append(item.instance_id)
		if item.quantity == 0:
			_items.remove_at(index)
		if remaining == 0:
			break
	revision += 1
	return DomainResult.ok({
		"definition_id": definition_id,
		"quantity": quantity,
		"instance_ids": consumed_instances,
	})


## 预检一次装备转移后可使用的背包位置。
## [param item] 即将放入背包的物品。
## [param excluding_instance_id] 同一事务中将先移出的背包物品标识。
## 返回可用位置或容量、空间错误。
func transfer_position(item: GameItem, excluding_instance_id: String = "") -> DomainResult:
	if item == null:
		return DomainResult.failure(&"inventory.no_space", "inventory transfer item is missing")
	var layouts: Array[Dictionary] = []
	var retained_count := 0
	for current: GameItem in _items:
		if current.instance_id == excluding_instance_id:
			continue
		retained_count += 1
		layouts.append(current.to_layout_dictionary())
	if retained_count >= capacity:
		return DomainResult.failure(&"inventory.no_space", "inventory has no room for equipment")
	var position := InventoryLayoutScript.first_available_position(layouts, item.footprint_px)
	if position.x < 0:
		return DomainResult.failure(&"inventory.no_space", "inventory has no room for equipment")
	return DomainResult.ok(position)


## 推进一次由玩家聚合完成的背包事务版本。
func commit_transfer() -> void:
	revision += 1


## 校验客户端背包 revision。
## [param expected_revision] 客户端命令携带的 revision。
## 返回成功或版本冲突。
func require_revision(expected_revision: int) -> DomainResult:
	if expected_revision != revision:
		return DomainResult.failure(&"inventory.revision_conflict", "inventory revision changed")
	return DomainResult.ok()


## 导出共享布局器需要的物品字典数组。
## 返回不包含业务数值的布局记录。
func layout_items() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item: GameItem in _items:
		result.append(item.to_layout_dictionary())
	return result


## 将布局器返回的位置写回对应物品。
## [param layouts] 已校验的布局记录数组。
func _apply_layouts(layouts: Array) -> void:
	var by_id: Dictionary = {}
	for layout: Dictionary in layouts:
		by_id[String(layout.get("instance_id", ""))] = layout
	for item: GameItem in _items:
		if by_id.has(item.instance_id):
			item.apply_layout(by_id[item.instance_id])
