class_name EquipmentMemoryRules
extends RefCounted

class Profile extends RefCounted:
	var definition_id: String
	var kind: int
	var level: int
	var extract_types := PackedInt32Array()
	var transfer_types := PackedInt32Array()

const TYPES := [1, 3, 4, 5, 6, 7]
var profiles: Dictionary[String, Profile] = {}
var chance: float
var stabilized_chance: float


## 编译原版模块资格，类型编号与普通加工、额外属性、星级、孔槽分开对应。
## [param raw] 版本化规则边界。
## 返回完整目录或规则错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	if raw.get("schema_version") != 1:
		return DomainResult.failure(&"memory.rules", "记忆模块规则版本无效")
	var result := EquipmentMemoryRules.new()
	result.chance = float(raw.get("chance", 0))
	result.stabilized_chance = float(raw.get("stabilized_chance", 0))
	if result.chance != 0.8 or result.stabilized_chance != 1.0:
		return DomainResult.failure(&"memory.rules", "原版模块概率无效")
	for row: Dictionary in raw.get("equipment", []):
		var profile := Profile.new()
		profile.definition_id = String(row.get("definition_id", ""))
		profile.kind = int(row.get("kind", 0))
		profile.level = int(row.get("level", 0))
		profile.extract_types = PackedInt32Array(row.get("extract_types", []))
		profile.transfer_types = PackedInt32Array(row.get("transfer_types", []))
		if profile.definition_id.is_empty() or result.profiles.has(profile.definition_id) or profile.level <= 0 or profile.kind not in [1, 2, 3, 6, 7, 9, 10, 11]:
			return DomainResult.failure(&"memory.rules", "模块装备资格无效")
		for types: PackedInt32Array in [profile.extract_types, profile.transfer_types]:
			for module_type: int in types:
				if module_type not in TYPES: return DomainResult.failure(&"memory.rules", "模块类型尚未开放")
		result.profiles[profile.definition_id] = profile
	return DomainResult.ok(result)
