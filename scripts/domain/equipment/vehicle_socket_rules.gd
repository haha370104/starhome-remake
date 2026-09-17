class_name VehicleSocketRules
extends RefCounted

class Profile extends RefCounted:
	var base_capacity: int = 0
	var maximum_capacity: int = 0
	var expansion: bool = false
	var high_only: bool = false
	var high_guaranteed: bool = false

class Crystal extends RefCounted:
	var definition_id: String = ""
	var effect: String = ""
	var value: float = 0.0
	var grade: int = 0

class Solvent extends RefCounted:
	var definition_id: String = ""
	var chances: Array[float] = []
	var repeat_last: bool = false
	var failure: String = ""

var _profiles: Dictionary[String, Profile] = {}
var _crystals: Dictionary[String, Crystal] = {}
var _solvents: Dictionary[String, Solvent] = {}
var maximum_effective: int = 4
var critical_multiplier: float = 1.5
var maximum_cracks: int = 3
var expansion_material: String = ""
var expansion_quantity: int = 8
var hammer_id: String = ""


## 从版本化配置构建开槽资格和材料规则，不访问文件或玩家状态。
## [param data] JSON 边界传入的配置。
## 返回完整目录或具体配置错误。
static func from_dictionary(data: Dictionary) -> DomainResult:
	var rules := VehicleSocketRules.new()
	if data.get("schema_version") != 1:
		return DomainResult.failure(&"sockets.rules_invalid", "战车晶石规则版本不支持")
	rules.maximum_effective = int(data.get("maximum_effective_per_kind", 4))
	rules.critical_multiplier = float(data.get("critical_multiplier", 1.5))
	rules.maximum_cracks = int(data.get("maximum_cracks", 3))
	rules.hammer_id = String(data.get("hammer_id", ""))
	rules.expansion_material = String(data.get("expansion_cost", {}).get("definition_id", ""))
	rules.expansion_quantity = int(data.get("expansion_cost", {}).get("quantity", 0))
	if rules.maximum_effective < 1 or rules.maximum_cracks != 3 or rules.expansion_quantity < 1:
		return DomainResult.failure(&"sockets.rules_invalid", "战车晶石上限配置无效")
	for raw: Dictionary in data.get("equipment", []):
		var entry := Profile.new()
		entry.base_capacity = int(raw.get("base_capacity", 0))
		entry.maximum_capacity = int(raw.get("maximum_capacity", 0))
		entry.expansion = bool(raw.get("expansion", false))
		entry.high_only = bool(raw.get("high_solvent_only", false))
		entry.high_guaranteed = bool(raw.get("high_solvent_guaranteed", false))
		var id := String(raw.get("definition_id", ""))
		if id.is_empty() or rules._profiles.has(id) or entry.base_capacity < 1 \
			or entry.maximum_capacity < entry.base_capacity or entry.maximum_capacity > 12:
			return DomainResult.failure(&"sockets.rules_invalid", "装备开槽资格配置无效")
		rules._profiles[id] = entry
	for raw: Dictionary in data.get("crystals", []):
		var entry := Crystal.new()
		entry.definition_id = String(raw.get("definition_id", ""))
		entry.effect = String(raw.get("effect", ""))
		entry.value = float(raw.get("value", 0))
		entry.grade = int(raw.get("grade", 0))
		if entry.definition_id.is_empty() or rules._crystals.has(entry.definition_id) \
			or entry.effect not in ["firepower", "health", "defense", "guidance", "critical", "rocket"] \
			or not is_finite(entry.value) or entry.value <= 0 or entry.grade not in [1, 2]:
			return DomainResult.failure(&"sockets.rules_invalid", "战车晶石属性配置无效")
		rules._crystals[entry.definition_id] = entry
	for raw: Dictionary in data.get("solvents", []):
		var entry := Solvent.new()
		entry.definition_id = String(raw.get("definition_id", ""))
		entry.repeat_last = bool(raw.get("repeat_last", false))
		entry.failure = String(raw.get("failure", ""))
		for chance: Variant in raw.get("chances", []):
			if not (chance is float or chance is int) or not is_finite(float(chance)) \
				or float(chance) < 0 or float(chance) > 1:
				return DomainResult.failure(&"sockets.rules_invalid", "开槽概率配置无效")
			entry.chances.append(float(chance))
		if entry.definition_id.is_empty() or entry.chances.is_empty() \
			or rules._solvents.has(entry.definition_id) \
			or entry.failure not in ["destroy_equipment", "close_last_socket", "none"]:
			return DomainResult.failure(&"sockets.rules_invalid", "柔解剂配置无效")
		rules._solvents[entry.definition_id] = entry
	return DomainResult.ok(rules)


## 查询某装备的开槽资格，未配置的装备不开放。
## [param definition_id] 稳定装备定义。
## 返回只读资格对象或 null。
func profile(definition_id: String) -> Profile:
	return _profiles.get(definition_id)


## 查询普通晶石，人物宝石和专属符文不会匹配。
## [param definition_id] 材料定义。
## 返回只读晶石规则或 null。
func crystal(definition_id: String) -> Crystal:
	return _crystals.get(definition_id)


## 查询开槽材料规则。
## [param definition_id] 材料定义。
## 返回只读柔解剂规则或 null。
func solvent(definition_id: String) -> Solvent:
	return _solvents.get(definition_id)


## 根据装备覆盖规则与已经开启的孔数计算概率。
## [param equipment_profile] 该装备的资格。
## [param material] 已核验的柔解剂。
## [param opened] 当前已开孔数，不含仅解锁的扩展孔。
## 返回概率；负值表示材料不适用。
func opening_chance(equipment_profile: Profile, material: Solvent, opened: int) -> float:
	if equipment_profile == null or material == null or opened < 0:
		return -1.0
	var high := material.definition_id == "high_grade_density_solvent"
	if equipment_profile.high_only and not high:
		return -1.0
	if high and equipment_profile.high_guaranteed:
		return 1.0
	if opened >= material.chances.size() and not material.repeat_last:
		return -1.0
	return material.chances[mini(opened, material.chances.size() - 1)]
