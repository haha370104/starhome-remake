class_name EquipmentDismantleRules
extends RefCounted

class Outcome extends RefCounted:
	var probability := 0.0
	var materials: Array[Dictionary] = []

class Profile extends RefCounted:
	var minimum_quality := 1
	var outcomes: Array[Outcome] = []

var profiles: Dictionary[String, Profile] = {}
var currency_cost := 200
var minimum_free_slots := 3


## 解析原表概率与各档材料，保留无返还结果，拒绝未知物品和非法权重。
## [param raw] 配置边界。
## [param catalog] 已装载定义的目录，用于验证材料身份。
## 返回类型化拆解规则。
static func from_dictionary(raw: Dictionary, catalog: ItemCatalog) -> DomainResult:
	var rules := EquipmentDismantleRules.new()
	rules.currency_cost = int(raw.get("currency_cost", -1))
	rules.minimum_free_slots = int(raw.get("minimum_free_slots", -1))
	if raw.get("schema_version") != 1 or rules.currency_cost < 0 or rules.minimum_free_slots < 0:
		return DomainResult.failure(&"dismantle.rules", "拆解费用或规则版本无效")
	for row: Dictionary in raw.get("equipment", []):
		var id := String(row.get("definition_id", ""))
		var profile := Profile.new()
		profile.minimum_quality = int(row.get("minimum_quality", -1))
		var total := 0.0
		for entry: Dictionary in row.get("outcomes", []):
			var outcome := Outcome.new()
			outcome.probability = float(entry.get("probability", -1))
			if not is_finite(outcome.probability) or outcome.probability <= 0 or outcome.probability > 1:
				return DomainResult.failure(&"dismantle.rules", "拆解概率无效")
			total += outcome.probability
			var seen := PackedStringArray()
			for material: Dictionary in entry.get("materials", []):
				var definition_id := ItemDefinitionAliases.canonical(String(material.get("definition_id", "")))
				var definition := catalog.definition(definition_id)
				var count := int(material.get("quantity", 0))
				if definition.is_empty() or int(definition.get("max_stack", 1)) <= 1 or count <= 0 or definition_id in seen:
					return DomainResult.failure(&"dismantle.rules", "拆解材料无效")
				seen.append(definition_id)
				outcome.materials.append({"definition_id": definition_id, "quantity": count})
			profile.outcomes.append(outcome)
		if catalog.definition(id).is_empty() or rules.profiles.has(id) or profile.minimum_quality < 1 or profile.minimum_quality > 3 or not is_equal_approx(total, 1):
			return DomainResult.failure(&"dismantle.rules", "拆解装备或总概率无效")
		rules.profiles[id] = profile
	return DomainResult.ok(rules)
