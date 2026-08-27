class_name FixedInventory
extends RefCounted

const DomainResult = preload("res://scripts/core/domain_result.gd")
const InventoryItem = preload("res://scripts/domain/inventory/inventory_item.gd")

var capacity: int
var _slots: Array[InventoryItem] = []


## Initializes a new instance with its required state.
## [param slot_capacity] Input value consumed by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func _init(slot_capacity: int) -> void:
	capacity = slot_capacity
	_slots.resize(maxi(0, capacity))


## Mutates the managed collection for the requested value.
## [param item] Input value consumed by the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
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


## Mutates the managed collection for the requested value.
## [param instance_id] Stable identifier of the target value.
## [param quantity] Input value consumed by the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
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


## Mutates the managed collection for the requested value.
## [param template_id] Stable identifier of the target value.
## [param quantity] Input value consumed by the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
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


## Retrieves the requested value from the managed state.
## [param slot_index] Sequence, tick, or index value used by the operation.
## Returns the result produced by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func item_at(slot_index: int) -> InventoryItem:
	if slot_index < 0 or slot_index >= capacity:
		return null
	return _slots[slot_index]


## Resolves the best matching value for the supplied query.
## [param instance_id] Stable identifier of the target value.
## Returns the computed integer value.
## Design: Keeps deterministic game rules independent from scene and UI state.
func find_instance_slot(instance_id: String) -> int:
	for slot_index: int in range(capacity):
		var item := _slots[slot_index]
		if item != null and item.instance_id == instance_id:
			return slot_index
	return -1


## Calculates the requested domain value.
## [param template_id] Stable identifier of the target value.
## Returns the computed integer value.
## Design: Keeps deterministic game rules independent from scene and UI state.
func count_template(template_id: StringName) -> int:
	var total := 0
	for item: InventoryItem in _slots:
		if item != null and item.template_id == template_id:
			total += item.quantity
	return total


## Performs the `occupied_slots` operation.
## Returns the computed integer value.
## Design: Keeps deterministic game rules independent from scene and UI state.
func occupied_slots() -> int:
	var count := 0
	for item: InventoryItem in _slots:
		if item != null:
			count += 1
	return count


## Validates the supplied state against the domain invariants.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
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


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func to_dictionary() -> Dictionary:
	var serialized_slots: Array[Variant] = []
	serialized_slots.resize(capacity)
	for slot_index: int in range(capacity):
		var item := _slots[slot_index]
		serialized_slots[slot_index] = null if item == null else item.to_dictionary()
	return {"capacity": capacity, "slots": serialized_slots}


## Validates the supplied state against the domain invariants.
## [param item] Input value consumed by the operation.
## Returns A domain result containing either the computed value or a validation error.
## Design: Keeps deterministic game rules independent from scene and UI state.
func _validate_incoming_item(item: InventoryItem) -> DomainResult:
	if item == null or not item.is_valid():
		return DomainResult.failure(&"invalid_inventory_item", "Incoming item is invalid")
	if item.slot != -1:
		return DomainResult.failure(&"item_already_slotted", "Incoming item must not already belong to an inventory slot")
	return DomainResult.ok()
