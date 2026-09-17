class_name Equipment
extends GameItem

var durability: int
var max_durability: int
var upgrade_level: int
var purchase_value: int
var sell_value: int
var required_skill_level: int
var _stats: Dictionary
var processing := EquipmentProcessing.new()
var processing_rules: EquipmentProcessingRules


## 初始化具有耐久和数值配置的装备实例。
## [param definition] 配置表中的装备定义。
## [param state] 存档中的装备实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	var raw_stats: Variant = definition.get("stats", {})
	_stats = (raw_stats as Dictionary).duplicate(true) if raw_stats is Dictionary else {}
	max_durability = maxi(1, int(state.get(
		"max_durability", _stats.get("max_durability", 1)
	)))
	durability = clampi(int(state.get("durability", max_durability)), 0, max_durability)
	upgrade_level = maxi(0, int(state.get("upgrade_level", 0)))
	purchase_value = maxi(0, int(_stats.get("purchase_value", 0)))
	sell_value = maxi(0, int(_stats.get("sell_value", 0)))
	required_skill_level = maxi(0, int(_stats.get("required_skill_level", 0)))
	var restored := EquipmentProcessing.restore(state.get("processing", {}))
	if restored.is_ok:
		processing = restored.value


## 让装备承受磨损并保证耐久不小于零。
## [param amount] 本次损失的耐久值。
func wear(amount: int) -> void:
	durability = maxi(0, durability - maxi(0, amount))


## 修复装备，并按规则永久降低耐久上限。
## [param max_decrease] 本次修复造成的耐久上限损失。
func repair(max_decrease: int) -> void:
	max_durability = maxi(1, max_durability - maxi(0, max_decrease))
	durability = max_durability


## 查询配置表中的单项装备数值。
## [param stat_id] stats 中的字段名。
## [param fallback] 字段不存在时采用的默认值。
## 返回配置基数与该实例的加工增量。
func stat(stat_id: String, fallback: Variant = 0) -> Variant:
	var base: Variant = _stats.get(stat_id, fallback)
	return base + processing.bonus(stat_id) if base is int or base is float else base


## 在成功加工后同步子类缓存，供装配与战斗使用同一组数值。
func refresh_processed_stats() -> void:
	pass


## 导出装备提示框所需的完整安全视图。
## 返回在通用物品字段上追加耐久与配置数值的 DTO。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["durability"] = durability
	view["max_durability"] = max_durability
	view["upgrade_level"] = upgrade_level
	view["stats"] = _stats.duplicate(true)
	for attribute: String in EquipmentProcessing.ATTRIBUTES:
		if processing.bonus(attribute) > 0:
			view.stats[attribute] = stat(attribute)
	view["processing"] = processing.to_dictionary()
	view["processing_eligible"] = processing_rules != null and processing_rules.profile(definition_id) != null
	return view
