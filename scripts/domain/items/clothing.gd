class_name Clothing
extends Equipment

var character_slot: String
var required_sex: String
var clothing_effects: Dictionary


## 初始化固定人物槽位上的服装实例。
## [param definition] 服装定义与表现配置。
## [param state] 存档中的服装实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	character_slot = String(definition.get("character_slot", ""))
	required_sex = String(definition.get("required_sex", "any"))
	var raw_effects: Variant = stat("skill_modifiers", {})
	clothing_effects = (raw_effects as Dictionary).duplicate(true) \
		if raw_effects is Dictionary else {}


## 判断当前服装能否穿到指定人物槽位。
## [param slot_id] 人物固定槽位标识。
## [param character_sex] 人物性别标识。
## 返回槽位和性别规则都满足时为 true。
func can_equip(slot_id: String, character_sex: String) -> bool:
	return character_slot == slot_id \
		and (required_sex == "any" or required_sex == character_sex)


## 导出包含人物槽位的服装视图。
## 返回通用装备 DTO 加服装槽位信息。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["character_slot"] = character_slot
	view["equipment_location"] = -1
	return view
