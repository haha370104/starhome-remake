class_name InventoryItem
extends RefCounted

var instance_id: String
var template_id: StringName
var quantity: int
var max_stack: int
var durability: int
var remaining_charges: int
var is_bound: bool
var random_attributes: Dictionary
var enhancement: Dictionary
var slot: int = -1


## Initializes a new instance with its required state.
## [param item_instance_id] Stable identifier of the target value.
## [param item_template_id] Stable identifier of the target value.
## [param item_quantity] Input value consumed by the operation.
## [param item_max_stack] Input value consumed by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func _init(
	item_instance_id: String,
	item_template_id: StringName,
	item_quantity: int = 1,
	item_max_stack: int = 1,
) -> void:
	instance_id = item_instance_id
	template_id = item_template_id
	quantity = item_quantity
	max_stack = item_max_stack
	durability = 0
	remaining_charges = 0
	is_bound = false
	random_attributes = {}
	enhancement = {}


## Performs the `duplicate_item` operation.
## Returns the result produced by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func duplicate_item():
	var copy = get_script().new(instance_id, template_id, quantity, max_stack)
	copy.durability = durability
	copy.remaining_charges = remaining_charges
	copy.is_bound = is_bound
	copy.random_attributes = random_attributes.duplicate(true)
	copy.enhancement = enhancement.duplicate(true)
	copy.slot = slot
	return copy


## Reports whether the requested condition is satisfied.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps deterministic game rules independent from scene and UI state.
func is_valid() -> bool:
	return (
		not instance_id.is_empty()
		and not String(template_id).is_empty()
		and max_stack > 0
		and quantity > 0
		and quantity <= max_stack
		and durability >= 0
		and remaining_charges >= 0
	)


## Reports whether the requested condition is satisfied.
## [param other] Input value consumed by the operation.
## Returns Whether the operation completed or the queried condition is satisfied.
## Design: Keeps deterministic game rules independent from scene and UI state.
func can_stack_with(other) -> bool:
	return (
		other != null
		and template_id == other.template_id
		and max_stack == other.max_stack
		and max_stack > 1
		and durability == other.durability
		and remaining_charges == other.remaining_charges
		and is_bound == other.is_bound
		and random_attributes == other.random_attributes
		and enhancement == other.enhancement
	)


## Serializes the current state into a transport-safe dictionary.
## Returns Structured result data produced by the operation.
## Design: Keeps deterministic game rules independent from scene and UI state.
func to_dictionary() -> Dictionary:
	return {
		"instance_id": instance_id,
		"template_id": String(template_id),
		"quantity": quantity,
		"max_stack": max_stack,
		"durability": durability,
		"remaining_charges": remaining_charges,
		"is_bound": is_bound,
		"random_attributes": random_attributes.duplicate(true),
		"enhancement": enhancement.duplicate(true),
		"slot": slot,
	}
