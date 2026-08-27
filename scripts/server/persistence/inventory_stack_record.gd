class_name InventoryStackRecord
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var stack_id := ""
var item_definition_id := ""
var quantity := 0
var slot_index := -1


## Builds a validated inventory stack from persistence-boundary [param raw].
## [param raw] Dictionary containing stable IDs, positive quantity and a non-negative slot.
## Returns a typed record or a stable validation failure.
static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"persistence.invalid_inventory_stack", "inventory stack must be a dictionary")
	var stack := InventoryStackRecord.new()
	stack.stack_id = String(raw.get("stack_id", ""))
	stack.item_definition_id = String(raw.get("item_definition_id", ""))
	stack.quantity = int(raw.get("quantity", 0))
	stack.slot_index = int(raw.get("slot_index", -1))
	if stack.stack_id.is_empty() or stack.item_definition_id.is_empty() \
		or stack.quantity <= 0 or stack.slot_index < 0:
		return DomainResult.failure(&"persistence.invalid_inventory_stack", "inventory stack fields are invalid")
	return DomainResult.ok(stack)


## Serializes this stack for the repository trust boundary.
## Returns a JSON-compatible dictionary.
func to_dictionary() -> Dictionary:
	return {
		"stack_id": stack_id,
		"item_definition_id": item_definition_id,
		"quantity": quantity,
		"slot_index": slot_index,
	}


## Creates an independent copy for transaction isolation.
## Returns a typed stack that shares no mutable state with this record.
func duplicate_record() -> InventoryStackRecord:
	return InventoryStackRecord.from_dictionary(to_dictionary()).value
