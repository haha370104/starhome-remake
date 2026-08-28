class_name FixedInventory
extends RefCounted

const DomainResult = preload("res://scripts/core/domain_result.gd")
const InventoryItem = preload("res://scripts/domain/inventory/inventory_item.gd")

var capacity: int
var _slots: Array[InventoryItem] = []


## 使用调用方参数初始化当前实例。
## [param slot_capacity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func _init(slot_capacity: int) -> void:
	capacity = slot_capacity
	_slots.resize(maxi(0, capacity))


## 执行 `add_item` 对应的模块操作。
## [param item] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func add_item(item: InventoryItem) -> DomainResult:
	var state_result := validate_state()
	if not state_result.is_ok:
		return state_result
	var item_result := _validate_incoming_item(item)
	if not item_result.is_ok:
		return item_result
	if find_instance_slot(item.instance_id) >= 0:
		return DomainResult.failure(&"duplicate_instance_id", "Item instance already exists in inventory")

	var remaining := item.quantity
	var merge_plan: Array[Dictionary] = []
	for slot_index: int in range(capacity):
		var existing := _slots[slot_index]
		if existing == null or not existing.can_stack_with(item):
			continue
		var available := existing.max_stack - existing.quantity
		if available <= 0:
			continue
		var amount := mini(available, remaining)
		merge_plan.append({"slot": slot_index, "amount": amount})
		remaining -= amount
		if remaining == 0:
			break

	var empty_slot := -1
	if remaining > 0:
		for slot_index: int in range(capacity):
			if _slots[slot_index] == null:
				empty_slot = slot_index
				break
		if empty_slot < 0:
			return DomainResult.failure(&"inventory_full", "Inventory has no room for the complete item stack")

	var touched_slots: Array[int] = []
	for operation: Dictionary in merge_plan:
		var slot_index: int = int(operation["slot"])
		_slots[slot_index].quantity += int(operation["amount"])
		touched_slots.append(slot_index)
	if remaining > 0:
		var inserted: InventoryItem = item.duplicate_item()
		inserted.quantity = remaining
		inserted.slot = empty_slot
		_slots[empty_slot] = inserted
		touched_slots.append(empty_slot)
	return DomainResult.ok({"added_quantity": item.quantity, "touched_slots": touched_slots})


## 移除并清理 `remove_instance` 对应的模块状态。
## [param instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param quantity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func remove_instance(instance_id: String, quantity: int) -> DomainResult:
	var state_result := validate_state()
	if not state_result.is_ok:
		return state_result
	if instance_id.is_empty() or quantity <= 0:
		return DomainResult.failure(&"invalid_removal", "Instance ID and positive quantity are required")
	var slot_index := find_instance_slot(instance_id)
	if slot_index < 0:
		return DomainResult.failure(&"item_not_found", "Item instance does not exist")
	var item := _slots[slot_index]
	if item.quantity < quantity:
		return DomainResult.failure(&"insufficient_quantity", "Item instance has insufficient quantity")
	item.quantity -= quantity
	if item.quantity == 0:
		_slots[slot_index] = null
	return DomainResult.ok({"removed_quantity": quantity, "slot": slot_index})


## 移除并清理 `remove_template` 对应的模块状态。
## [param template_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param quantity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func remove_template(template_id: StringName, quantity: int) -> DomainResult:
	var state_result := validate_state()
	if not state_result.is_ok:
		return state_result
	if String(template_id).is_empty() or quantity <= 0:
		return DomainResult.failure(&"invalid_removal", "Template ID and positive quantity are required")
	var available := 0
	for item: InventoryItem in _slots:
		if item != null and item.template_id == template_id:
			available += item.quantity
	if available < quantity:
		return DomainResult.failure(&"insufficient_quantity", "Inventory has insufficient template quantity")

	var remaining := quantity
	var touched_slots: Array[int] = []
	for slot_index: int in range(capacity):
		var item := _slots[slot_index]
		if item == null or item.template_id != template_id:
			continue
		var amount := mini(item.quantity, remaining)
		item.quantity -= amount
		remaining -= amount
		touched_slots.append(slot_index)
		if item.quantity == 0:
			_slots[slot_index] = null
		if remaining == 0:
			break
	return DomainResult.ok({"removed_quantity": quantity, "touched_slots": touched_slots})


## 执行 `item_at` 对应的模块操作。
## [param slot_index] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func item_at(slot_index: int) -> InventoryItem:
	if slot_index < 0 or slot_index >= capacity:
		return null
	return _slots[slot_index]


## 查询并返回 `find_instance_slot` 对应的模块状态。
## [param instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func find_instance_slot(instance_id: String) -> int:
	for slot_index: int in range(capacity):
		var item := _slots[slot_index]
		if item != null and item.instance_id == instance_id:
			return slot_index
	return -1


## 执行 `count_template` 对应的模块操作。
## [param template_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func count_template(template_id: StringName) -> int:
	var total := 0
	for item: InventoryItem in _slots:
		if item != null and item.template_id == template_id:
			total += item.quantity
	return total


## 执行 `occupied_slots` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func occupied_slots() -> int:
	var count := 0
	for item: InventoryItem in _slots:
		if item != null:
			count += 1
	return count


## 校验 `validate_state` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func validate_state() -> DomainResult:
	if capacity <= 0 or _slots.size() != capacity:
		return DomainResult.failure(&"invalid_inventory_capacity", "Inventory capacity must be positive and stable")
	var instance_ids := {}
	for slot_index: int in range(capacity):
		var item := _slots[slot_index]
		if item == null:
			continue
		if not item.is_valid() or item.slot != slot_index:
			return DomainResult.failure(&"invalid_inventory_item", "Inventory item or slot metadata is invalid")
		if instance_ids.has(item.instance_id):
			return DomainResult.failure(&"duplicate_instance_id", "Inventory contains duplicate instance IDs")
		instance_ids[item.instance_id] = true
	return DomainResult.ok()


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func to_dictionary() -> Dictionary:
	var serialized_slots: Array[Variant] = []
	serialized_slots.resize(capacity)
	for slot_index: int in range(capacity):
		var item := _slots[slot_index]
		serialized_slots[slot_index] = null if item == null else item.to_dictionary()
	return {"capacity": capacity, "slots": serialized_slots}


## 校验 `validate_incoming_item` 对应的模块状态。
## [param item] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func _validate_incoming_item(item: InventoryItem) -> DomainResult:
	if item == null or not item.is_valid():
		return DomainResult.failure(&"invalid_inventory_item", "Incoming item is invalid")
	if item.slot != -1:
		return DomainResult.failure(&"item_already_slotted", "Incoming item must not already belong to an inventory slot")
	return DomainResult.ok()
