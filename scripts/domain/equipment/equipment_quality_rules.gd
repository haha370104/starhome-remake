class_name EquipmentQualityRules
extends RefCounted

class Profile extends RefCounted:
	var bonuses: Dictionary[String, Array] = {}

var profiles: Dictionary[String, Profile] = {}
var manufacturing_chances: Array[float] = []


## 校验四档品质属性与制造概率；概率为显式复刻配置。
## [param raw] 只读配置边界。
## 返回类型化规则或配置错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := EquipmentQualityRules.new()
	if raw.get("schema_version") != 1:
		return DomainResult.failure(&"quality.invalid_rules", "装备品质规则版本错误")
	var total := 0.0
	for chance: Variant in raw.get("manufacturing_chances", []):
		if not (chance is int or chance is float) or not is_finite(float(chance)) or float(chance) < 0:
			return DomainResult.failure(&"quality.invalid_rules", "制造品质概率无效")
		rules.manufacturing_chances.append(float(chance))
		total += float(chance)
	if rules.manufacturing_chances.size() != 4 or not is_equal_approx(total, 1):
		return DomainResult.failure(&"quality.invalid_rules", "制造品质概率之和必须为100%")
	for row: Dictionary in raw.get("equipment", []):
		var id := String(row.get("definition_id", ""))
		var profile := Profile.new()
		for attribute: String in row.get("bonuses", {}):
			var values: Variant = row.bonuses[attribute]
			if attribute not in ["max_health", "output_power", "base_attack", "drive"] or not values is Array or values.size() != 4:
				return DomainResult.failure(&"quality.invalid_rules", "品质属性无效")
			for value: Variant in values:
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) != int(value) or int(value) < 0:
					return DomainResult.failure(&"quality.invalid_rules", "品质加成必须为非负整数")
			if values[0] != 0: return DomainResult.failure(&"quality.invalid_rules", "白色品质不能重复增加基础值")
			profile.bonuses[attribute] = values.duplicate()
		if id.is_empty() or rules.profiles.has(id) or profile.bonuses.is_empty():
			return DomainResult.failure(&"quality.invalid_rules", "装备品质资格无效")
		rules.profiles[id] = profile
	return DomainResult.ok(rules)


## 依据服务器独立随机数生成制造品质，其他来源的装备不调用。
## [param definition_id] 制造成品定义。
## [param roll] 服务器0到1随机数；无品质装备始终为白色。
## 返回可交给物品工厂的品质实例字段。
func manufactured_state(definition_id: String, roll: float) -> Dictionary:
	if not profiles.has(definition_id) or not is_finite(roll) or roll < 0 or roll >= 1: return {}
	var cumulative := 0.0
	for grade in manufacturing_chances.size():
		cumulative += manufacturing_chances[grade]
		if roll < cumulative:
			return {"version": 1, "grade": grade} if grade > 0 else {}
	return {}


## 展示制造品质分布，避免用户把必定产出理解成必定高品质。
## [param definition_id] 产物定义。
## 返回中文概率说明；没有品质的物品返回空字符串。
func manufacturing_description(definition_id: String) -> String:
	if not profiles.has(definition_id): return ""
	var parts := PackedStringArray()
	for grade in manufacturing_chances.size():
		parts.append("%s %.0f%%" % [EquipmentQuality.LABELS[grade], manufacturing_chances[grade] * 100])
	return "制造品质：" + " / ".join(parts) + "（复刻概率）"
