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
var clothing_improvement := ClothingImprovement.new()
var equipment_memory := EquipmentMemory.new()
var vehicle_sockets := VehicleSockets.new()
var crystal_source := CrystalSourceGrowth.new()
var austin_glens := AustinGlensGrowth.new()
var sama := SamaGrowth.new()
var processing := EquipmentProcessing.new()
var extra_attributes := ExtraAttributes.new()
var strengthening := EquipmentStrengthening.new()
var equipment_quality := EquipmentQuality.new()
var forging := EquipmentForging.new()
var usage := EquipmentUsage.new()
var magazine := WeaponMagazine.new()
var crystal_cracks: int = 0
var crystal_source_cracks: int = 0


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
	var improved := ClothingImprovement.restore(raw.get("clothing_improvement", {}))
	if not improved.is_ok: return improved
	stack.clothing_improvement = improved.value
	var memory := EquipmentMemory.restore(raw.get("equipment_memory", {}))
	if not memory.is_ok: return memory
	stack.equipment_memory = memory.value
	var processed := EquipmentProcessing.restore(raw.get("processing", {}))
	if not processed.is_ok:
		return processed
	stack.processing = processed.value
	var extra := ExtraAttributes.restore(raw.get("extra_attributes", {}))
	if not extra.is_ok: return extra
	stack.extra_attributes = extra.value
	var forged := EquipmentForging.restore(raw.get("forging", {}))
	if not forged.is_ok: return forged
	stack.forging = forged.value
	var quality := EquipmentQuality.restore(raw.get("equipment_quality", {}))
	if not quality.is_ok: return quality
	stack.equipment_quality = quality.value
	var stars := EquipmentStrengthening.restore(raw.get("strengthening", {}))
	if not stars.is_ok: return stars
	stack.strengthening = stars.value
	var used := EquipmentUsage.restore(raw.get("usage", {}))
	if not used.is_ok:
		return used
	stack.usage = used.value
	var rounds := WeaponMagazine.restore(raw.get("magazine", {}))
	if not rounds.is_ok: return rounds
	stack.magazine = rounds.value
	var source := CrystalSourceGrowth.restore(raw.get("crystal_source", {}))
	if not source.is_ok: return source
	stack.crystal_source = source.value
	var austin := AustinGlensGrowth.restore(raw.get("austin_glens", {}))
	if not austin.is_ok: return austin
	stack.austin_glens = austin.value
	var sama := SamaGrowth.restore(raw.get("sama", {}))
	if not sama.is_ok: return sama
	stack.sama = sama.value
	var sockets := VehicleSockets.restore(raw.get("vehicle_sockets", {}))
	var cracks := VehicleCrystal.restore_cracks(raw.get("crystal_cracks", 0))
	if not sockets.is_ok:
		return sockets
	if not cracks.is_ok:
		return cracks
	stack.vehicle_sockets = sockets.value
	stack.crystal_cracks = cracks.value
	if not CrystalSourceRules.integer(raw.get("crystal_source_cracks", 0), 0, 3):
		return DomainResult.failure(&"crystal_source.cracks", "晶源核裂纹无效")
	stack.crystal_source_cracks = int(raw.get("crystal_source_cracks", 0))
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
		"clothing_improvement": clothing_improvement.to_dictionary(),
		"equipment_memory": equipment_memory.to_dictionary(),
		"vehicle_sockets": vehicle_sockets.to_dictionary(),
		"crystal_source": crystal_source.to_dictionary(),
		"austin_glens": austin_glens.to_dictionary(),
		"sama": sama.to_dictionary(),
		"processing": processing.to_dictionary(),
		"extra_attributes": extra_attributes.to_dictionary(),
		"strengthening": strengthening.to_dictionary(),
		"equipment_quality": equipment_quality.to_dictionary(),
		"forging": forging.to_dictionary(),
		"usage": usage.to_dictionary(),
		"magazine": magazine.to_dictionary(),
		"crystal_cracks": crystal_cracks,
		"crystal_source_cracks": crystal_source_cracks,
	}


## 执行 `duplicate_record` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func duplicate_record() -> InventoryStackRecord:
	return InventoryStackRecord.from_dictionary(to_dictionary()).value


## 从具体物品提取全部原始实例状态，背包和仓库使用同一套保存字段。
## [param item] 已经通过目录校验的领域物品。
## [param stack_index] 所在容器内的稳定排列序号。
## 返回经过校验的持久化记录，不使用可能省略字段的UI投影。
static func from_item(item: GameItem, stack_index: int) -> DomainResult:
	var saved_durability := 0
	var saved_max_durability := 0
	if item is Equipment:
		saved_durability = (item as Equipment).durability
		saved_max_durability = (item as Equipment).max_durability
	return from_dictionary({
		"stack_id": item.instance_id,
		"item_definition_id": item.definition_id,
		"quantity": item.quantity,
		"slot_index": stack_index,
		"container_id": item.container_id,
		"position_px": [item.position_px.x, item.position_px.y],
		"footprint_px": [item.footprint_px.x, item.footprint_px.y],
		"locked": item.locked,
		"bound": item.bound,
		"max_durability": saved_max_durability,
		"durability": saved_durability,
		"upgrade_level": (item as Equipment).upgrade_level if item is Equipment else 0,
		"enhancement": (item as Clothing).enhancement.to_dictionary() if item is Clothing else {},
		"clothing_improvement": (item as Clothing).improvement.to_dictionary() if item is Clothing else {},
		"equipment_memory": (item as EquipmentMemoryModule).memory.to_dictionary() if item is EquipmentMemoryModule else {},
		"vehicle_sockets": (item as VehicleEquipment).sockets.to_dictionary() if item is VehicleEquipment else {},
		"processing": (item as Equipment).processing.to_dictionary() if item is Equipment else {},
		"extra_attributes": (item as Equipment).extra_attributes.to_dictionary() if item is Equipment else {},
		"strengthening": (item as Equipment).strengthening.to_dictionary() if item is Equipment else {},
		"equipment_quality": (item as Equipment).quality.to_dictionary() if item is Equipment else {},
		"forging": (item as Equipment).forging.to_dictionary() if item is Equipment else {},
		"usage": (item as Equipment).usage.to_dictionary() if item is Equipment else {},
		"magazine": (item as Equipment).magazine.to_dictionary() if item is Equipment else {},
		"crystal_cracks": (item as VehicleCrystal).cracks if item is VehicleCrystal else 0,
		"crystal_source": (item as VehicleEquipment).crystal_source.to_dictionary() if item is VehicleEquipment else {},
		"austin_glens": (item as VehicleEquipment).austin_glens.to_dictionary() if item is VehicleEquipment else {},
		"sama": (item as VehicleEquipment).sama.to_dictionary() if item is VehicleEquipment else {},
		"crystal_source_cracks": (item as CrystalSourceCore).cracks if item is CrystalSourceCore else 0,
	})


## 把持久化记录转换成物品工厂接收的实例事实。
## 返回独立状态，字段名转换只发生在持久化边界。
func item_state() -> Dictionary:
	var state := to_dictionary()
	state["instance_id"] = stack_id
	return state
