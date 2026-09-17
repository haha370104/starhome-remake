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
var maintenance_profile: EquipmentMaintenanceRules.Profile
var usage := EquipmentUsage.new()
var magazine := WeaponMagazine.new()
var extra_attributes := ExtraAttributes.new()
var extra_attribute_rules: ExtraAttributeRules
var strengthening := EquipmentStrengthening.new()
var strengthening_profile: EquipmentStrengtheningRules.Profile
var strengthening_rules: EquipmentStrengtheningRules
var armor_refinement_profile: ArmorRefinementRules.Profile
var memory_profile: EquipmentMemoryRules.Profile


## 初始化具有耐久和数值配置的装备实例。
## [param definition] 配置表中的装备定义。
## [param state] 存档中的装备实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	var raw_stats: Variant = definition.get("stats", {})
	_stats = (raw_stats as Dictionary).duplicate(true) if raw_stats is Dictionary else {}
	max_durability = maxi(1, int(state.get(
		"max_durability", _stats.get("max_durability", _stats.get("wear_degree", 1))
	)))
	durability = clampi(int(state.get("durability", max_durability)), 0, max_durability)
	upgrade_level = maxi(0, int(state.get("upgrade_level", 0)))
	purchase_value = maxi(0, int(_stats.get("purchase_value", 0)))
	sell_value = maxi(0, int(_stats.get("sell_value", 0)))
	required_skill_level = maxi(0, int(_stats.get("required_skill_level", 0)))
	var restored := EquipmentProcessing.restore(state.get("processing", {}))
	if restored.is_ok:
		processing = restored.value
	var extra := ExtraAttributes.restore(state.get("extra_attributes", {}))
	if extra.is_ok:
		extra_attributes = extra.value
	var stars := EquipmentStrengthening.restore(state.get("strengthening", {}))
	if stars.is_ok:
		strengthening = stars.value
	var used := EquipmentUsage.restore(state.get("usage", {}))
	if used.is_ok:
		usage = used.value
	var rounds := WeaponMagazine.restore(state.get("magazine", {}))
	if rounds.is_ok:
		magazine = rounds.value
	magazine.bind_capacity(ammunition_capacity())
	# 旧荣耀服装曾遗漏 wear_degree，完整的 1/1 旧记录迁移到原版上限。
	if _stats.has("wear_degree") and max_durability == 1 and durability == 1:
		max_durability = maxi(1, int(_stats.wear_degree))
		durability = max_durability


## 记录与自身类型匹配的实际使用，维护链不完整或免磨损装备保持原状。
## [param event] shot、movement、mining 或 damage。
## [param amount] 实际次数或移动秒数。
## 返回是否刚刚损坏，用于一次性重算战斗属性。
func record_use(event: String, amount: float = 1.0) -> bool:
	if durability <= 0 or maintenance_profile == null or maintenance_profile.no_wear or not maintenance_profile.wear_enabled:
		return false
	var matches := (event == "shot" and self is VehicleWeapon) or (event == "movement" and self is VehicleEngine) \
		or (event == "mining" and self is VehicleMiningArm) or (event == "damage" and self is Clothing)
	if not matches:
		return false
	wear(usage.consume(event, amount, float(maintenance_profile.wear_thresholds.get(event, 0))))
	return durability == 0


## 计算弹仓真实上限，与普通容量加工使用同一属性。
## 返回无弹药装备的零容量或非负弹仓上限。
func ammunition_capacity() -> int:
	return maxi(0, int(stat("ammunition_capacity", 0)))


## 让装备承受磨损并保证耐久不小于零。
## [param amount] 本次损失的耐久值。
func wear(amount: int) -> void:
	durability = maxi(0, durability - maxi(0, amount))


## 修复装备，并按规则永久降低耐久上限。
## [param max_decrease] 本次修复造成的耐久上限损失。
func repair(max_decrease: int) -> void:
	max_durability = maxi(1, max_durability - maxi(0, max_decrease))
	durability = max_durability


## 按自身维护资格报价，常规维护与速修保持不同的上限规则。
## [param tool] 速修规则；null 表示常规维护。
## 返回耐久前后值或不能修复的理由。
func maintenance_preview(tool: EquipmentMaintenanceRules.RepairTool = null) -> DomainResult:
	return EquipmentMaintenance.regular_preview(self) if tool == null else EquipmentMaintenance.quick_preview(self, tool)


## 对已经支付的同一实例完成维护，并再次保证自身资格有效。
## [param tool] 与支付报价一致的速修规则；null 表示常规维护。
## 返回实际耐久变化或资格错误。
func maintain(tool: EquipmentMaintenanceRules.RepairTool = null) -> DomainResult:
	var quote := maintenance_preview(tool)
	if quote.is_ok:
		EquipmentMaintenance.settle(self, quote.value)
	return quote


## 查询配置表中的单项装备数值。
## [param stat_id] stats 中的字段名。
## [param fallback] 字段不存在时采用的默认值。
## 返回配置基数与该实例的加工增量。
func stat(stat_id: String, fallback: Variant = 0) -> Variant:
	var base: Variant = _stats.get(stat_id, fallback)
	return base + processing.bonus(stat_id) + extra_attributes.bonus(stat_id, extra_attribute_rules) \
		+ strengthening.bonus(stat_id, strengthening_profile) if base is int or base is float else base


## 在成功加工后同步子类缓存，供装配与战斗使用同一组数值。
func refresh_processed_stats() -> void:
	pass


## 导出装备提示框所需的完整安全视图。
## 返回在通用物品字段上追加耐久与配置数值的 DTO。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["equipment_memory_eligible"] = memory_profile != null
	view["armor_refinement_eligible"] = armor_refinement_profile != null
	view["armor_refinement_level"] = armor_refinement_profile.level if armor_refinement_profile != null else 0
	view["durability"] = durability
	view["max_durability"] = max_durability
	view["upgrade_level"] = upgrade_level
	view["stats"] = _stats.duplicate(true)
	for attribute: String in EquipmentProcessing.ATTRIBUTES:
		if processing.bonus(attribute) > 0:
			view.stats[attribute] = stat(attribute)
	view["processing"] = processing.to_dictionary()
	for attribute: String in ExtraAttributeRules.ATTRIBUTES:
		if extra_attributes.bonus(attribute, extra_attribute_rules) > 0:
			view.stats[attribute] = stat(attribute)
	view["extra_attributes"] = extra_attributes.to_dictionary()
	view["strengthening"] = strengthening.to_dictionary()
	if strengthening_profile != null:
		view.stats[strengthening_profile.attribute] = stat(strengthening_profile.attribute)
	view["strengthening_eligible"] = strengthening_profile != null
	view["extra_attribute_eligible"] = extra_attribute_rules != null and not extra_attribute_rules.allowed(definition_id).is_empty()
	view["usage"] = usage.to_dictionary()
	view["magazine"] = magazine.to_dictionary()
	view["ammunition_capacity"] = ammunition_capacity()
	view["processing_eligible"] = processing_rules != null and processing_rules.profile(definition_id) != null
	return view
