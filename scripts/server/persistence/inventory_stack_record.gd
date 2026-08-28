class_name InventoryStackRecord
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var stack_id := ""
var item_definition_id := ""
var quantity := 0
var slot_index := -1


## 执行 `from_dictionary` 对应的模块操作。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
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


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func to_dictionary() -> Dictionary:
	return {
		"stack_id": stack_id,
		"item_definition_id": item_definition_id,
		"quantity": quantity,
		"slot_index": slot_index,
	}


## 执行 `duplicate_record` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func duplicate_record() -> InventoryStackRecord:
	return InventoryStackRecord.from_dictionary(to_dictionary()).value
