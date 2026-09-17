class_name Clothing
extends Equipment

var character_slot: String
var required_sex: String
var clothing_effects: Dictionary
var enhancement := ClothingEnhancement.new()
var improvement := ClothingImprovement.new()
var improvement_rules: ClothingImprovementRules


## 初始化固定人物槽位上的服装实例。
## [param definition] 服装定义与表现配置。
## [param state] 存档中的服装实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	character_slot = String(definition.get("character_slot", ""))
	var prior_slot := String(state.get("equipped_character_slot", ""))
	if not prior_slot.is_empty() and prior_slot == String(definition.get("legacy_character_slot", "")):
		character_slot = prior_slot
	required_sex = String(definition.get("required_sex", "any"))
	var raw_effects: Variant = stat("skill_modifiers", {})
	clothing_effects = (raw_effects as Dictionary).duplicate(true) \
		if raw_effects is Dictionary else {}
	var restored := ClothingEnhancement.restore(state.get("enhancement", {}))
	if restored.is_ok:
		enhancement = restored.value
	var improved := ClothingImprovement.restore(state.get("clothing_improvement", {}))
	if improved.is_ok: improvement = improved.value


## 判断当前服装能否穿到指定人物槽位。
## [param slot_id] 人物固定槽位标识。
## [param character_sex] 人物性别标识。
## 返回槽位和性别规则都满足时为 true。
func can_equip(slot_id: String, character_sex: String) -> bool:
	return character_slot == slot_id \
		and (required_sex == "any" or required_sex == character_sex)


## 服装离开旧装备槽后恢复正确部位，避免强制迁移挤掉另一件头饰。
func restore_default_slot() -> void:
	character_slot = String(_definition.get("character_slot", ""))


## 导出包含人物槽位的服装视图。
## 返回通用装备 DTO 加服装槽位信息。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["character_slot"] = character_slot
	view["equipped_character_slot"] = character_slot
	view["equipment_location"] = -1
	view["enhancement"] = enhancement.to_dictionary()
	view["clothing_improvement"] = improvement.to_dictionary()
	view["clothing_improvement_eligible"] = improvement_rules != null and improvement_rules.slots.has(definition_id)
	if improvement_rules != null and improvement.level > 0:
		var channel: ClothingImprovementRules.Channel = improvement_rules.channels.get(improvement.attribute)
		if channel != null: view["clothing_improvement_summary"] = "时装改良 %d级：%s +%s" % [improvement.level, channel.label, str(channel.increment * improvement.level)]
	return view
