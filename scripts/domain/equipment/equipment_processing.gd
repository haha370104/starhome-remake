class_name EquipmentProcessing
extends RefCounted

const ATTRIBUTES := ["max_health", "output_power", "range", "drive", "base_attack", "ammunition_capacity"]
var _increments: Dictionary[String, int] = {}


## 恢复独立加工事实；旧存档默认为未加工，不接受负值、分数或未知字段。
## [param raw] 存档边界数据。
## 返回加工状态或格式错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or raw.get("version", 1) != 1 or not raw.get("increments", {}) is Dictionary:
		return DomainResult.failure(&"processing.invalid_state", "装备加工状态格式无效")
	var result := EquipmentProcessing.new()
	for key: Variant in raw.get("increments", {}):
		var value: Variant = raw.increments[key]
		if key not in ATTRIBUTES or not (value is float or value is int) \
			or not is_finite(float(value)) or value < 0 or value > 1000000 or float(value) != floorf(float(value)):
			return DomainResult.failure(&"processing.invalid_state", "装备加工增量无效")
		if value > 0:
			result._increments[String(key)] = int(value)
	return DomainResult.ok(result)


## 将存档增量与装备本身资格、上限核对，不能把车体加工移植到炮上。
## [param profile] 该装备的原版资格。
## 返回合法状态或越界错误。
func validate_for(profile: EquipmentProcessingRules.Profile) -> DomainResult:
	for attribute: String in _increments:
		if profile == null or not profile.attributes.has(attribute):
			return DomainResult.failure(&"processing.incompatible", "装备不支持此加工属性")
		var rule := profile.attributes[attribute]
		if _increments[attribute] > rule.limit - rule.base:
			return DomainResult.failure(&"processing.over_limit", "装备加工值超出上限")
	return DomainResult.ok()


## 计算一次加工的真实增量，最后一次只补至上限。
## [param profile] 装备加工规则。
## [param material] 本次使用的特殊材料。
## 返回属性、前后值、实际增量，或材料不适配与满级错误。
func preview(profile: EquipmentProcessingRules.Profile, material: EquipmentProcessingRules.ProcessingMaterial) -> DomainResult:
	if profile == null or material == null or not profile.attributes.has(material.attribute):
		return DomainResult.failure(&"processing.incompatible", "该材料不能加工所选装备")
	var rule := profile.attributes[material.attribute]
	var before := rule.base + bonus(material.attribute)
	if before >= rule.limit:
		return DomainResult.failure(&"processing.maximum", "该属性已达到加工上限")
	var points := mini(material.points, floori(rule.limit - before))
	return DomainResult.ok({"attribute": material.attribute, "before": before, "after": before + points, "points": points})


## 完成已预检的加工；独立保存增量，不改变配置基数或接合器等级。
## [param profile] 装备加工规则。
## [param material] 本次材料。
## 返回实际变更或不适配错误。
func apply(profile: EquipmentProcessingRules.Profile, material: EquipmentProcessingRules.ProcessingMaterial) -> DomainResult:
	var result := preview(profile, material)
	if result.is_ok:
		_increments[material.attribute] = bonus(material.attribute) + int(result.value.points)
	return result


## 查询单项加工增量。
## [param attribute] 规范化属性名。
## 返回固定增量；没有加工时为零。
func bonus(attribute: String) -> int:
	return _increments.get(attribute, 0)


## 导出原始事实，避免保存已经叠加晶石或称号的派生数值。
## 返回防御性存档字典。
func to_dictionary() -> Dictionary:
	return {"version": 1, "increments": _increments.duplicate()}
