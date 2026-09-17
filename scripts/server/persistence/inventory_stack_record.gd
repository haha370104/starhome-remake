class_name InventoryStackRecord
extends RefCounted


var stack_id := ""
var item_definition_id := ""
var quantity := 0
var slot_index := -1
var container_id := "main"
var position_px := Vector2i.ZERO
var footprint_px := Vector2i(30, 30)
var locked := false
var bound := false
var max_durability := 0
var durability := 0
var upgrade_level := 0
var enhancement := ClothingEnhancement.new()


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
	stack.container_id = String(raw.get("container_id", "main"))
	var position_value: Variant = raw.get("position_px", [
		(stack.slot_index % 8) * 30,
		floori(float(stack.slot_index) / 8.0) * 30,
	])
	var footprint_value: Variant = raw.get("footprint_px", [30, 30])
	if not position_value is Array or position_value.size() != 2 \
			or not footprint_value is Array or footprint_value.size() != 2:
		return DomainResult.failure(&"persistence.invalid_inventory_stack", "inventory geometry must contain two coordinates")
	stack.position_px = Vector2i(int(position_value[0]), int(position_value[1]))
	stack.footprint_px = Vector2i(int(footprint_value[0]), int(footprint_value[1]))
	stack.locked = bool(raw.get("locked", false))
	stack.bound = bool(raw.get("bound", false))
	stack.max_durability = int(raw.get("max_durability", 0))
	stack.durability = int(raw.get("durability", stack.max_durability))
	stack.upgrade_level = int(raw.get("upgrade_level", 0))
	var enhanced := ClothingEnhancement.restore(raw.get("enhancement", {}))
	if not enhanced.is_ok:
		return enhanced
	stack.enhancement = enhanced.value
	if stack.stack_id.is_empty() or stack.item_definition_id.is_empty() \
			or stack.quantity <= 0 or stack.slot_index < 0 or stack.container_id.is_empty() \
			or stack.position_px.x < 0 or stack.position_px.y < 0 \
			or stack.footprint_px.x <= 0 or stack.footprint_px.y <= 0 \
			or stack.max_durability < 0 or stack.durability < 0 \
			or stack.durability > stack.max_durability or stack.upgrade_level < 0:
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
		"container_id": container_id,
		"position_px": [position_px.x, position_px.y],
		"footprint_px": [footprint_px.x, footprint_px.y],
		"locked": locked,
		"bound": bound,
		"max_durability": max_durability,
		"durability": durability,
		"upgrade_level": upgrade_level,
		"enhancement": enhancement.to_dictionary(),
	}


## 执行 `duplicate_record` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func duplicate_record() -> InventoryStackRecord:
	return InventoryStackRecord.from_dictionary(to_dictionary()).value
