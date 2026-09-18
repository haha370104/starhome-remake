class_name EquipmentSlotRecord
extends RefCounted


var owner_kind := ""
var slot_id := ""
var item_instance_id := ""
var item_definition_id := ""
var max_durability := 0
var durability := 0
var upgrade_level := 0
var enhancement := ClothingEnhancement.new()
var clothing_improvement := ClothingImprovement.new()
var vehicle_sockets := VehicleSockets.new()
var crystal_source := CrystalSourceGrowth.new()
var austin_glens := AustinGlensGrowth.new()
var central_growth := CentralGrowth.new()
var sama := SamaGrowth.new()
var processing := EquipmentProcessing.new()
var extra_attributes := ExtraAttributes.new()
var strengthening := EquipmentStrengthening.new()
var equipment_quality := EquipmentQuality.new()
var forging := EquipmentForging.new()
var usage := EquipmentUsage.new()
var magazine := WeaponMagazine.new()
var locked := false
var bound := false
var slot_location := -1
var equip_kind := -1


## 执行 `from_dictionary` 对应的模块操作。
## [param raw] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func from_dictionary(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment slot must be a dictionary")
	var slot := EquipmentSlotRecord.new()
	slot.owner_kind = String(raw.get("owner_kind", ""))
	slot.slot_id = String(raw.get("slot_id", ""))
	slot.item_instance_id = String(raw.get("item_instance_id", ""))
	slot.item_definition_id = String(raw.get("item_definition_id", ""))
	slot.max_durability = int(raw.get("max_durability", 0))
	slot.durability = int(raw.get("durability", -1))
	slot.upgrade_level = int(raw.get("upgrade_level", 0))
	var enhanced := ClothingEnhancement.restore(raw.get("enhancement", {}))
	if not enhanced.is_ok:
		return enhanced
	slot.enhancement = enhanced.value
	var improved := ClothingImprovement.restore(raw.get("clothing_improvement", {}))
	if not improved.is_ok: return improved
	slot.clothing_improvement = improved.value
	var processed := EquipmentProcessing.restore(raw.get("processing", {}))
	if not processed.is_ok:
		return processed
	slot.processing = processed.value
	var extra := ExtraAttributes.restore(raw.get("extra_attributes", {}))
	if not extra.is_ok: return extra
	slot.extra_attributes = extra.value
	var forged := EquipmentForging.restore(raw.get("forging", {}))
	if not forged.is_ok: return forged
	slot.forging = forged.value
	var quality := EquipmentQuality.restore(raw.get("equipment_quality", {}))
	if not quality.is_ok: return quality
	slot.equipment_quality = quality.value
	var stars := EquipmentStrengthening.restore(raw.get("strengthening", {}))
	if not stars.is_ok: return stars
	slot.strengthening = stars.value
	var used := EquipmentUsage.restore(raw.get("usage", {}))
	if not used.is_ok:
		return used
	slot.usage = used.value
	var rounds := WeaponMagazine.restore(raw.get("magazine", {}))
	if not rounds.is_ok: return rounds
	slot.magazine = rounds.value
	var source := CrystalSourceGrowth.restore(raw.get("crystal_source", {}))
	if not source.is_ok: return source
	slot.crystal_source = source.value
	var austin := AustinGlensGrowth.restore(raw.get("austin_glens", {}))
	if not austin.is_ok: return austin
	slot.austin_glens = austin.value
	var central_result := CentralGrowth.restore(raw.get("central_growth", {}))
	if not central_result.is_ok: return central_result
	slot.central_growth = central_result.value
	var sama_result := SamaGrowth.restore(raw.get("sama", {}))
	if not sama_result.is_ok: return sama_result
	slot.sama = sama_result.value
	var sockets := VehicleSockets.restore(raw.get("vehicle_sockets", {}))
	if not sockets.is_ok:
		return sockets
	slot.vehicle_sockets = sockets.value
	if not raw.get("locked", false) is bool or not raw.get("bound", false) is bool:
		return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment flags must be booleans")
	slot.locked = raw.get("locked", false)
	slot.bound = raw.get("bound", false)
	slot.slot_location = int(raw.get("slot_location", _legacy_location(slot.slot_id)))
	slot.equip_kind = int(raw.get("equip_kind", -1))
	if slot.owner_kind not in ["character", "vehicle"] or slot.slot_id.is_empty() \
		or slot.item_instance_id.is_empty() or slot.item_definition_id.is_empty():
		return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment identity fields are invalid")
	if slot.max_durability <= 0 or slot.durability < 0 \
			or slot.durability > slot.max_durability or slot.upgrade_level < 0 \
			or slot.slot_location < 0:
		return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment state is invalid")
	return DomainResult.ok(slot)


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func to_dictionary() -> Dictionary:
	return {
		"owner_kind": owner_kind,
		"slot_id": slot_id,
		"item_instance_id": item_instance_id,
		"item_definition_id": item_definition_id,
		"max_durability": max_durability,
		"durability": durability,
		"upgrade_level": upgrade_level,
		"enhancement": enhancement.to_dictionary(),
		"clothing_improvement": clothing_improvement.to_dictionary(),
		"vehicle_sockets": vehicle_sockets.to_dictionary(),
		"crystal_source": crystal_source.to_dictionary(),
		"austin_glens": austin_glens.to_dictionary(),
		"central_growth": central_growth.to_dictionary(),
		"sama": sama.to_dictionary(),
		"processing": processing.to_dictionary(),
		"extra_attributes": extra_attributes.to_dictionary(),
		"strengthening": strengthening.to_dictionary(),
		"equipment_quality": equipment_quality.to_dictionary(),
		"forging": forging.to_dictionary(),
		"usage": usage.to_dictionary(),
		"magazine": magazine.to_dictionary(),
		"locked": locked,
		"bound": bound,
		"slot_location": slot_location,
		"equip_kind": equip_kind,
	}


## 将旧存档中的字符串槽位映射为稳定的客户端 Location 编号。
## [param slot_name] 旧存档槽位名称。
## 返回荣耀客户端使用的 Location 编号；未知槽位保留在扩展区 100。
static func _legacy_location(slot_name: String) -> int:
	return {
		"chassis": 0,
		"primary_weapon": 1,
		"defense": 2,
		"propulsion": 3,
		"front_armor": 5,
		"rear_armor": 6,
		"left_armor": 7,
		"right_armor": 8,
		"tactical": 13,
		"secondary_power": 14,
		"control": 16,
		"amplifier": 17,
		"energy_core": 18,
	}.get(slot_name, 100)


## 执行 `duplicate_record` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func duplicate_record() -> EquipmentSlotRecord:
	return EquipmentSlotRecord.from_dictionary(to_dictionary()).value
