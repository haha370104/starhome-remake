class_name EquipmentQuality
extends RefCounted

const LABELS := ["白色", "绿色", "蓝色", "紫色"]
const COLORS := ["fffbff", "18fb0b", "0076db", "ab3aee"]
var grade := 0


## 恢复普通装备品质，旧档保持白色，不接受超范围或小数伪值。
## [param raw] 存档边界的独立品质字段。
## 返回有效实例或格式错误。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary:
		return DomainResult.failure(&"quality.invalid_state", "装备品质格式无效")
	var result := EquipmentQuality.new()
	if raw.is_empty(): return DomainResult.ok(result)
	var value: Variant = raw.get("grade", -1)
	if raw.get("version") != 1 or not (value is int or value is float) or not is_finite(float(value)) \
		or float(value) != int(value) or int(value) < 0 or int(value) > 3:
		return DomainResult.failure(&"quality.invalid_state", "装备品质必须为白、绿、蓝、紫之一")
	result.grade = int(value)
	return DomainResult.ok(result)


## 校验非白色品质仅附着在具有原版品质规则的普通装备上。
## [param profile] 当前装备匹配的只读配置。
## 返回资格校验结果。
func validate_for(profile: EquipmentQualityRules.Profile) -> DomainResult:
	if grade > 0 and profile == null:
		return DomainResult.failure(&"quality.ineligible", "该装备没有普通品质成长")
	return DomainResult.ok()


## 按品质读取原版固定加成，与加工次数和星级独立。
## [param attribute] 装备基础属性标识。
## [param profile] 装备品质规则。
## 返回固定属性增量。
func bonus(attribute: String, profile: EquipmentQualityRules.Profile) -> int:
	return int(profile.bonuses[attribute][grade]) if profile != null and profile.bonuses.has(attribute) else 0


## 导出最小状态，白色使用旧档默认表示。
## 返回独立品质事实。
func to_dictionary() -> Dictionary:
	return {"version": 1, "grade": grade} if grade > 0 else {}
