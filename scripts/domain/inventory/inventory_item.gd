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


## 使用调用方参数初始化当前实例。
## [param item_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param item_template_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param item_quantity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param item_max_stack] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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


## 执行 `duplicate_item` 对应的模块操作。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func duplicate_item():
	var copy = get_script().new(instance_id, template_id, quantity, max_stack)
	copy.durability = durability
	copy.remaining_charges = remaining_charges
	copy.is_bound = is_bound
	copy.random_attributes = random_attributes.duplicate(true)
	copy.enhancement = enhancement.duplicate(true)
	copy.slot = slot
	return copy


## 判断 `is_valid` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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


## 判断 `can_stack_with` 对应的模块状态。
## [param other] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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
