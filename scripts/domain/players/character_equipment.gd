class_name CharacterEquipment
extends RefCounted


const SLOT_ORDER := ["head", "upper_body", "lower_body", "hands", "shoes"]

var _equipped: Dictionary = {}


## 从持久化边界还原一件已穿服装。
## [param clothing] 已完成类型构造的服装实例。
## 返回成功或非法槽位错误。
func restore(clothing: Clothing) -> DomainResult:
	if clothing == null or clothing.character_slot not in SLOT_ORDER:
		return DomainResult.failure(&"equipment.location_rejected", "clothing slot is not supported")
	if _equipped.has(clothing.character_slot):
		return DomainResult.failure(&"equipment.slot_duplicated", "character clothing slot is duplicated")
	_equipped[clothing.character_slot] = clothing
	return DomainResult.ok()


## 将服装穿到固定人物槽位并返回被替换服装。
## [param clothing] 待穿着服装。
## [param slot_id] 目标固定槽位。
## [param character_sex] 当前人物性别。
## 返回旧服装；空槽时 value 为 null。
func equip(clothing: Clothing, slot_id: String, character_sex: String) -> DomainResult:
	if clothing == null or not clothing.can_equip(slot_id, character_sex):
		return DomainResult.failure(&"equipment.location_rejected", "clothing cannot be equipped in requested slot")
	var replaced: Clothing = _equipped.get(slot_id)
	_equipped[slot_id] = clothing
	return DomainResult.ok(replaced)


## 从人物固定槽位卸下服装。
## [param slot_id] 待卸载的人物槽位。
## 返回被卸下服装或空槽错误。
func unequip(slot_id: String) -> DomainResult:
	if not _equipped.has(slot_id):
		return DomainResult.failure(&"equipment.slot_empty", "character equipment slot is empty")
	var clothing: Clothing = _equipped[slot_id]
	_equipped.erase(slot_id)
	return DomainResult.ok(clothing)


## 查询指定人物槽位的服装。
## [param slot_id] 人物固定槽位。
## 返回服装；空槽返回 null。
func at(slot_id: String) -> Clothing:
	return _equipped.get(slot_id)


## 按稳定槽位顺序导出已穿服装。
## 返回服装数组的防御性副本。
func items() -> Array[Clothing]:
	var result: Array[Clothing] = []
	for slot_id: String in SLOT_ORDER:
		if _equipped.has(slot_id):
			result.append(_equipped[slot_id])
	return result


## 汇总所有服装提供的技能加成。
## 返回技能标识到总加成的映射。
func skill_modifiers() -> Dictionary:
	var result: Dictionary = {}
	for clothing: Clothing in items():
		for skill_id: Variant in clothing.clothing_effects:
			result[String(skill_id)] = int(result.get(String(skill_id), 0)) \
				+ int(clothing.clothing_effects[skill_id])
	return result
