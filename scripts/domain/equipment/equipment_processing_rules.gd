class_name EquipmentProcessingRules
extends RefCounted

class AttributeRule extends RefCounted:
	var attribute: String = ""
	var label: String = ""
	var base: float = 0
	var limit: float = 0
	var required_skill_level: int = 0
	var materials: Array[Dictionary] = []
	var currency: int = 0

class Profile extends RefCounted:
	var attributes: Dictionary[String, AttributeRule] = {}

class ProcessingMaterial extends RefCounted:
	var definition_id: String = ""
	var attribute: String = ""
	var points: int = 0

var _profiles: Dictionary[String, Profile] = {}
var _materials: Dictionary[String, ProcessingMaterial] = {}
var success_chance: float = 1.0
var skill_id: String = "processing"


## 将原版加工表转换为类型化规则，原服未知成功率由显式复刻配置提供。
## [param data] 配置边界数据。
## 返回规则目录或非法配置。
static func from_dictionary(data: Dictionary) -> DomainResult:
	var rules := EquipmentProcessingRules.new()
	if data.get("schema_version") != 1:
		return DomainResult.failure(&"processing.rules_invalid", "加工规则版本不支持")
	rules.success_chance = float(data.get("policy", {}).get("success_chance", -1))
	if not is_finite(rules.success_chance) or rules.success_chance < 0 or rules.success_chance > 1:
		return DomainResult.failure(&"processing.rules_invalid", "加工成功率无效")
	for raw: Dictionary in data.get("equipment", []):
		var equipment_profile := Profile.new()
		var id := String(raw.get("definition_id", ""))
		for value: Dictionary in raw.get("attributes", []):
			var rule := AttributeRule.new()
			rule.attribute = String(value.get("attribute", ""))
			rule.label = String(value.get("label", ""))
			rule.base = float(value.get("base", 0))
			rule.limit = float(value.get("limit", 0))
			rule.required_skill_level = int(value.get("required_skill_level", 0))
			rule.currency = int(value.get("currency", 0))
			if rule.attribute not in EquipmentProcessing.ATTRIBUTES or equipment_profile.attributes.has(rule.attribute) \
				or not is_finite(rule.base) or not is_finite(rule.limit) or rule.base < 0 \
				or rule.limit <= rule.base or rule.required_skill_level < 0 or rule.currency < 0:
				return DomainResult.failure(&"processing.rules_invalid", "加工属性与上限无效")
			for cost: Dictionary in value.get("materials", []):
				if String(cost.get("definition_id", "")).is_empty() or int(cost.get("quantity", 0)) < 1:
					return DomainResult.failure(&"processing.rules_invalid", "加工材料无效")
				rule.materials.append(cost.duplicate(true))
			equipment_profile.attributes[rule.attribute] = rule
		if id.is_empty() or rules._profiles.has(id) or equipment_profile.attributes.is_empty():
			return DomainResult.failure(&"processing.rules_invalid", "加工装备资格无效")
		rules._profiles[id] = equipment_profile
	for raw: Dictionary in data.get("materials", []):
		var special_material := ProcessingMaterial.new()
		special_material.definition_id = String(raw.get("definition_id", ""))
		special_material.attribute = String(raw.get("attribute", ""))
		special_material.points = int(raw.get("points", 0))
		if special_material.definition_id.is_empty() or rules._materials.has(special_material.definition_id) \
			or special_material.attribute not in EquipmentProcessing.ATTRIBUTES or special_material.points <= 0:
			return DomainResult.failure(&"processing.rules_invalid", "特殊加工材料无效")
		rules._materials[special_material.definition_id] = special_material
	return DomainResult.ok(rules)


## 查询装备允许加工的属性和配方。
## [param id] 装备定义。
## 返回只读规则或 null。
func profile(id: String) -> Profile:
	return _profiles.get(id)


## 查询加工道具的固定增量。
## [param id] 道具定义。
## 返回只读材料规则或 null。
func material(id: String) -> ProcessingMaterial:
	return _materials.get(id)
