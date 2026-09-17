class_name CrystalSourceRules
extends RefCounted

class Profile extends RefCounted:
	var location: int
	var attribute: String
	var base: int
	var quality_steps: Array[int] = []
	var growth_steps: Array[int] = []
	var crystal_id: String
	var source_id: String
	var advanced_source_id: String
	var bound: bool

class Core extends RefCounted:
	var definition_id: String
	var color: String
	var level: int
	var attribute: String
	var bonus: int

var profiles: Dictionary[String, Profile] = {}
var cores: Dictionary[String, Core] = {}
var offers: Dictionary[String, int] = {}
var required_level := 400
var maximum_level := 15
var core_stabilizer_id: String
var quality_stabilizer_id: String
var five_color_id: String
var seven_color_id: String
var crystal_costs: Array[int] = []
var five_color_costs: Array[int] = []
var seven_color_costs: Array[int] = []
var source_costs: Array[int] = []
var advanced_source_costs: Array[int] = []
var quality_failure_levels: Array[int] = []
var quality_chances: Array[float] = []
var core_chances: Array[float] = []
var growth_chance := 1.0


## 将只读配置转成晶源体与核心的类型化规则，拒绝缺项、重复与非法概率。
## [param raw] JSON配置边界。
## 返回有效规则或配置错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := CrystalSourceRules.new()
	if raw.get("schema_version") != 1 or raw.get("maximum_level") != 15 or not integer(raw.get("required_level"), 1, 100000):
		return _invalid()
	rules.required_level = int(raw.required_level)
	for key: String in ["core_stabilizer_id", "quality_stabilizer_id", "five_color_id", "seven_color_id"]:
		if not raw.get(key) is String or String(raw[key]).is_empty(): return _invalid()
		rules.set(key, raw[key])
	for key: String in ["crystal_costs", "five_color_costs", "source_costs", "quality_failure_levels", "seven_color_costs", "advanced_source_costs"]:
		var count := 5 if key in ["seven_color_costs", "advanced_source_costs"] else 15
		if not raw.get(key) is Array or raw[key].size() != count: return _invalid()
		var values: Array[int] = []
		for value: Variant in raw[key]:
			if not integer(value, 0 if key == "quality_failure_levels" else 1, 100000): return _invalid()
			values.append(int(value))
		rules.set(key, values)
	for level in 15:
		if rules.quality_failure_levels[level] > level: return _invalid()
	for key: String in ["quality_chances", "core_chances"]:
		if not raw.get(key) is Array or raw[key].size() != (15 if key == "quality_chances" else 4): return _invalid()
		var values: Array[float] = []
		for value: Variant in raw[key]:
			if not probability(value): return _invalid()
			values.append(float(value))
		rules.set(key, values)
	if not probability(raw.get("growth_chance")): return _invalid()
	rules.growth_chance = float(raw.growth_chance)
	for row: Dictionary in raw.get("equipment", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.profiles.has(id) or not integer(row.get("location"), 28, 31) \
			or row.get("attribute") not in ["max_health", "energy_cannon_attack", "rocket_attack", "missile_attack"] \
			or not integer(row.get("base"), 1, 100000) or not row.get("bound") is bool: return _invalid()
		var profile := Profile.new()
		profile.location = int(row.location)
		profile.attribute = String(row.attribute)
		profile.base = int(row.base)
		profile.bound = bool(row.bound)
		for key: String in ["quality_steps", "growth_steps"]:
			if not row.get(key) is Array or row[key].size() != 2: return _invalid()
			var steps: Array[int] = []
			for value: Variant in row[key]:
				if not integer(value, 1, 100000): return _invalid()
				steps.append(int(value))
			profile.set(key, steps)
		for key: String in ["crystal_id", "source_id", "advanced_source_id"]:
			if not row.get(key) is String or String(row[key]).is_empty(): return _invalid()
			profile.set(key, row[key])
		rules.profiles[id] = profile
	var combinations := PackedStringArray()
	for row: Dictionary in raw.get("cores", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.cores.has(id) or row.get("color") not in ["red", "yellow", "black"] \
			or not integer(row.get("level"), 1, 5) or not integer(row.get("bonus"), 1, 100000) \
			or row.get("attribute") not in ["max_health", "energy_cannon_attack", "missile_attack"]: return _invalid()
		var key := "%s:%d" % [row.color, row.level]
		if key in combinations: return _invalid()
		combinations.append(key)
		var core := Core.new()
		core.definition_id = id
		core.color = String(row.color)
		core.level = int(row.level)
		core.attribute = String(row.attribute)
		core.bonus = int(row.bonus)
		rules.cores[id] = core
	for row: Dictionary in raw.get("offers", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.offers.has(id) or not integer(row.get("unit_price"), 1, 10000000): return _invalid()
		rules.offers[id] = int(row.unit_price)
	if rules.profiles.size() != 8 or rules.cores.size() != 15: return _invalid()
	return DomainResult.ok(rules)


## 从实际颜色与等级查找合成目标，不拼接运行时素材或物品名称。
## [param color] 核心颜色。[param level] 目标等级。
## 返回定义；不存在时为空。
func core_at(color: String, level: int) -> Core:
	for core: Core in cores.values():
		if core.color == color and core.level == level: return core
	return null


## 同时供规则和存档使用的有限整数验证。
## [param value] 边界数值。[param minimum] 下限。[param maximum] 上限。
## 返回是否为范围内整数。
static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


## 验证概率，不接受字符串、无穷或越界值。
## [param value] 原始概率。
## 返回是否在闭区间零至一。
static func probability(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= 1


## 汇总只读规则加载失败。
## 返回明确的配置错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"crystal_source.rules", "晶源体规则无效")
