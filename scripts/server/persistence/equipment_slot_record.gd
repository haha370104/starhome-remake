class_name EquipmentSlotRecord
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var owner_kind := ""
var slot_id := ""
var item_instance_id := ""
var item_definition_id := ""
var max_durability := 0
var durability := 0
var upgrade_level := 0


## Builds a validated equipped-item record from persistence-boundary [param raw].
## [param raw] Dictionary identifying the character/vehicle slot and concrete item instance.
## Returns a typed record or a stable validation failure.
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
	if slot.owner_kind not in ["character", "vehicle"] or slot.slot_id.is_empty() \
		or slot.item_instance_id.is_empty() or slot.item_definition_id.is_empty():
		return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment identity fields are invalid")
	if slot.max_durability <= 0 or slot.durability < 0 \
		or slot.durability > slot.max_durability or slot.upgrade_level < 0:
		return DomainResult.failure(&"persistence.invalid_equipment_slot", "equipment state is invalid")
	return DomainResult.ok(slot)


## Serializes this equipped item for the repository trust boundary.
## Returns a JSON-compatible dictionary.
func to_dictionary() -> Dictionary:
	return {
		"owner_kind": owner_kind,
		"slot_id": slot_id,
		"item_instance_id": item_instance_id,
		"item_definition_id": item_definition_id,
		"max_durability": max_durability,
		"durability": durability,
		"upgrade_level": upgrade_level,
	}


## Creates an independent copy for transaction isolation.
## Returns a typed slot that shares no mutable state with this record.
func duplicate_record() -> EquipmentSlotRecord:
	return EquipmentSlotRecord.from_dictionary(to_dictionary()).value
