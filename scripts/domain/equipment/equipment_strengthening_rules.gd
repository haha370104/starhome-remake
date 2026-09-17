class_name EquipmentStrengtheningRules
extends RefCounted

class Profile extends RefCounted:
	var definition_id: String
	var attribute: String
	var values: Array[int] = []
	var ordinary_material: String
	var ultimate_material: String
	var alloy_id: String

var profiles: Dictionary[String, Profile] = {}
var currency: int
var alloy_quantity: int
var additional_material: String
var additional_quantity: int
var _ordinary_chances: Array[float] = []
var _ultimate_chances: Array[float] = []
var _ordinary_loss: int
var _ultimate_loss: int


## 编译十星独立强化规则，与接合器升级及原版普通加工分开。
## [param raw] 权威版本化配置。
## 返回类型化规则或目录错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	if raw.get("schema_version") != 1 or raw.get("maximum_level") != 10:
		return DomainResult.failure(&"strengthening.rules_invalid", "装备强化版本无效")
	var rules := EquipmentStrengtheningRules.new()
	rules.currency = int(raw.get("currency", -1))
	rules.alloy_quantity = int(raw.get("alloy_quantity", 0))
	rules.additional_material = String(raw.get("ultimate_additional_material", ""))
	rules.additional_quantity = int(raw.get("ultimate_additional_quantity", 0))
	rules._ordinary_loss = int(raw.get("ordinary_failure_loss", -1))
	rules._ultimate_loss = int(raw.get("ultimate_failure_loss", -1))
	if rules.currency < 0 or rules.alloy_quantity <= 0 or rules.additional_material.is_empty() or rules.additional_quantity <= 0 \
		or rules._ordinary_loss < 0 or rules._ultimate_loss < 0:
		return DomainResult.failure(&"strengthening.rules_invalid", "装备强化消耗或失败配置无效")
	for key: String in ["ordinary_chances", "ultimate_chances"]:
		var chances: Array[float] = []
		for chance: float in raw.get(key, []):
			if not is_finite(chance) or chance <= 0 or chance > 1:
				return DomainResult.failure(&"strengthening.rules_invalid", "装备强化概率无效")
			chances.append(chance)
		if chances.is_empty() or chances[-1] != 1.0:
			return DomainResult.failure(&"strengthening.rules_invalid", "装备强化缺少保成功档")
		if key == "ordinary_chances": rules._ordinary_chances = chances
		else: rules._ultimate_chances = chances
	for row: Dictionary in raw.get("equipment", []):
		var profile := Profile.new()
		profile.definition_id = String(row.get("definition_id", ""))
		profile.attribute = String(row.get("attribute", ""))
		profile.ordinary_material = String(row.get("ordinary_material", ""))
		profile.ultimate_material = String(row.get("ultimate_material", ""))
		profile.alloy_id = String(row.get("alloy_id", ""))
		profile.values.assign(row.get("values", []))
		if profile.definition_id.is_empty() or rules.profiles.has(profile.definition_id) or profile.attribute not in ["max_health", "base_attack", "drive"] \
			or profile.ordinary_material.is_empty() or profile.ultimate_material.is_empty() or profile.alloy_id.is_empty() or profile.values.size() != 11 or profile.values[0] != 0:
			return DomainResult.failure(&"strengthening.rules_invalid", "装备强化资格无效")
		for index: int in range(1, profile.values.size()):
			if profile.values[index] <= profile.values[index - 1]:
				return DomainResult.failure(&"strengthening.rules_invalid", "装备强化数值未递增")
		rules.profiles[profile.definition_id] = profile
	return DomainResult.ok(rules)


## 按是否第十星和投入颗数取得原版成功率。
## [param ultimate] 是否当前九星。
## [param quantity] 正整数投入，超过保成功数量仍为百分百。
## 返回成功率。
func chance(ultimate: bool, quantity: int) -> float:
	var bands := _ultimate_chances if ultimate else _ordinary_chances
	return bands[mini(maxi(quantity - 1, 0), bands.size() - 1)]


## 查询普通失败降一星或第十星失败降二星的规则。
## [param ultimate] 是否在尝试第十星。
## 返回降星数量。
func failure_loss(ultimate: bool) -> int:
	return _ultimate_loss if ultimate else _ordinary_loss
