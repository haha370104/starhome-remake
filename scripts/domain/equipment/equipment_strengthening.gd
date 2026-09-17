class_name EquipmentStrengthening
extends RefCounted

var level: int = 0


## 恢复独立星级，不将其混入接合器 upgrade_level。
## [param raw] 旧档默认零星，新档只保存版本和星级。
## 返回成长对象或非法事实。
static func restore(raw: Variant) -> DomainResult:
	if not raw is Dictionary or raw.get("version", 1) != 1:
		return DomainResult.failure(&"strengthening.invalid_state", "装备星级记录无效")
	var count: Variant = raw.get("level", 0)
	if not (count is int or count is float) or not is_finite(float(count)) or float(count) != int(count) or count < 0 or count > 10:
		return DomainResult.failure(&"strengthening.invalid_state", "装备星级必须在零到十星之间")
	var result := EquipmentStrengthening.new()
	result.level = int(count)
	return DomainResult.ok(result)


## 验证有成长的装备是否仍属于原版明确允许的系列。
## [param profile] 原版装备资格。
## 返回合法记录或资格错误。
func validate_for(profile: EquipmentStrengtheningRules.Profile) -> DomainResult:
	return DomainResult.ok() if level == 0 or profile != null else DomainResult.failure(&"strengthening.incompatible", "该装备不允许独立星级强化")


## 按本装备星级取得某项派生增量。
## [param attribute] 请求的统一属性。
## [param profile] 目录中的资格和逐星值。
## 返回非负固定增量。
func bonus(attribute: String, profile: EquipmentStrengtheningRules.Profile) -> int:
	return profile.values[level] if profile != null and attribute == profile.attribute else 0


## 校验普通石和极限石阶段，预览整次成本、成功与失败。
## [param profile] 本装备资格。
## [param rules] 强化目录。
## [param material] 选择的材料定义。
## [param quantity] 本次投入的强化石数量。
## 返回完整报价或未变更的错误。
func preview(profile: EquipmentStrengtheningRules.Profile, rules: EquipmentStrengtheningRules, material: String, quantity: int) -> DomainResult:
	if profile == null or rules == null:
		return DomainResult.failure(&"strengthening.incompatible", "原版不允许该装备进行星级强化")
	if level >= 10:
		return DomainResult.failure(&"strengthening.maximum", "装备已达十星")
	var ultimate := level == 9
	if material != (profile.ultimate_material if ultimate else profile.ordinary_material) or quantity < 1 or quantity > 99:
		return DomainResult.failure(&"strengthening.material", "请选择该部位与当前星级对应的强化石，数量为 1～99")
	var requirements: Array[Dictionary] = [{"definition_id": material, "quantity": quantity}, {"definition_id": profile.alloy_id, "quantity": rules.alloy_quantity}]
	if ultimate: requirements.append({"definition_id": rules.additional_material, "quantity": rules.additional_quantity})
	var failed_level := maxi(0, level - rules.failure_loss(ultimate))
	return DomainResult.ok({"before": level, "after": level + 1, "failed_level": failed_level, "chance": rules.chance(ultimate, quantity),
		"attribute": profile.attribute, "bonus_before": profile.values[level], "bonus_after": profile.values[level + 1],
		"bonus_failed": profile.values[failed_level], "requirements": requirements, "currency": rules.currency})


## 对已经通过交易预检的独立候选结算星级。
## [param profile] 本装备资格。
## [param rules] 权威规则。
## [param material] 所选强化石。
## [param quantity] 投入量。
## [param roll] 服务端随机样本。
## 返回实际星级、派生值和成功标志。
func apply(profile: EquipmentStrengtheningRules.Profile, rules: EquipmentStrengtheningRules, material: String, quantity: int, roll: float) -> DomainResult:
	if not is_finite(roll) or roll < 0 or roll >= 1:
		return DomainResult.failure(&"strengthening.invalid_roll", "装备强化随机样本无效")
	var result := preview(profile, rules, material, quantity)
	if not result.is_ok: return result
	result.value["success"] = roll < float(result.value.chance)
	level = int(result.value.after if result.value.success else result.value.failed_level)
	result.value["actual_level"] = level
	return result


## 导出星级事实，重启按同一目录派生数值。
## 返回独立存档字典。
func to_dictionary() -> Dictionary:
	return {"version": 1, "level": level}
