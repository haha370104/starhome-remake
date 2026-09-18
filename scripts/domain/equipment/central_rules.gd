class_name CentralRules
extends RefCounted

const CHIP_IDS := ["tank", "engine", "gun", "missile", "armor", "generator"]
const ATTRIBUTES := ["max_health", "energy_cannon_attack", "missile_attack", "defense"]

class Chip extends RefCounted:
	var display_name: String
	var bonuses: Array[Dictionary] = []
	var icon: String

class Module extends RefCounted:
	var chip_id: String
	var target_grade: int

class Profile extends RefCounted:
	var location: int
	var base: Dictionary = {}
	var visuals: Array[Dictionary] = []

var chips: Dictionary[String, Chip] = {}
var modules: Dictionary[String, Module] = {}
var profiles: Dictionary[String, Profile] = {}
var offers: Dictionary[String, int] = {}
var growth_materials: Array[String] = []
var health_increments: Array[int] = []
var attack_increments: Array[int] = []
var evolution_material: String
var evolution_bonus: Dictionary = {}
var fatal_chance_percent: Array[int] = []
var fatal_current_health_percent: int
var fatal_damage_cap_multiplier: int
var suspended_effects: Array[String] = []
var suspended_set_effects: Array[Dictionary] = []


## 将核查配置转换为有明确维度的中枢规则，不保留可变物品状态。
## [param raw] JSON配置。
## 返回规则或明确的配置错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := CentralRules.new()
	if raw.get("schema_version") != 1: return _invalid()
	for key: String in ["chips", "modules", "profiles", "offers", "suspended_set_effects"]:
		if not raw.get(key) is Array: return _invalid()
		for row: Variant in raw[key]:
			if not row is Dictionary: return _invalid()
	for row: Dictionary in raw.chips:
		var id := String(row.get("id", ""))
		if id not in CHIP_IDS or rules.chips.has(id) or not row.get("bonuses") is Array or row.bonuses.size() != 3: return _invalid()
		var chip := Chip.new()
		chip.display_name = String(row.get("display_name", ""))
		chip.icon = String(row.get("icon", ""))
		for bonus: Variant in row.bonuses:
			if not _valid_bonus(bonus): return _invalid()
			chip.bonuses.append(bonus.duplicate(true))
		rules.chips[id] = chip
	for row: Dictionary in raw.modules:
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.modules.has(id) or row.get("chip_id") not in CHIP_IDS or not integer(row.get("target_grade"), 1, 3): return _invalid()
		var module := Module.new()
		module.chip_id = String(row.chip_id)
		module.target_grade = int(row.target_grade)
		rules.modules[id] = module
	var locations: Array[int] = []
	for row: Dictionary in raw.profiles:
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.profiles.has(id) or not integer(row.get("location"), 40, 45) or int(row.location) in locations or not _valid_bonus(row.get("base")): return _invalid()
		if not row.get("visuals") is Array or row.visuals.is_empty(): return _invalid()
		var profile := Profile.new()
		profile.location = int(row.location)
		profile.base = row.base.duplicate(true)
		var previous := -1
		for visual: Variant in row.visuals:
			if not visual is Dictionary or not integer(visual.get("grade"), 0, 18) or int(visual.grade) <= previous or not visual.get("icon") is String: return _invalid()
			previous = int(visual.grade)
			profile.visuals.append(visual.duplicate(true))
		if int(profile.visuals[0].grade) != 0: return _invalid()
		locations.append(profile.location)
		rules.profiles[id] = profile
	for row: Dictionary in raw.offers:
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.offers.has(id) or not integer(row.get("unit_price"), 1, 10000000): return _invalid()
		rules.offers[id] = int(row.unit_price)
	for key: String in ["health_increments", "attack_increments", "fatal_chance_percent"]:
		var count := 3 if key == "fatal_chance_percent" else 19
		if not raw.get(key) is Array or raw[key].size() != count: return _invalid()
		var values: Array[int] = []
		for number: Variant in raw[key]:
			if not integer(number, 0, 100 if count == 3 else 100000): return _invalid()
			values.append(int(number))
		rules.set(key, values)
	if not raw.get("growth_materials") is Array or raw.growth_materials.size() != 6: return _invalid()
	for id: Variant in raw.growth_materials:
		if not id is String or id.is_empty() or id in rules.growth_materials: return _invalid()
		rules.growth_materials.append(id)
	if not raw.get("evolution_material") is String or not _valid_bonus(raw.get("evolution_bonus")): return _invalid()
	rules.evolution_material = raw.evolution_material
	rules.evolution_bonus = raw.evolution_bonus.duplicate(true)
	for key: String in ["fatal_current_health_percent", "fatal_damage_cap_multiplier"]:
		if not integer(raw.get(key), 1, 100): return _invalid()
		rules.set(key, int(raw[key]))
	if not raw.get("suspended_effects") is Array: return _invalid()
	for label: Variant in raw.suspended_effects:
		if not label is String: return _invalid()
		rules.suspended_effects.append(label)
	for effect: Dictionary in raw.suspended_set_effects:
		if effect.get("enabled") != false or effect.get("target") != "player" or not integer(effect.get("minimum_grade"), 3, 18): return _invalid()
		rules.suspended_set_effects.append(effect.duplicate(true))
	if rules.chips.size() != 6 or rules.modules.size() != 18 or rules.profiles.size() != 6 or rules.offers.size() != 31: return _invalid()
	return DomainResult.ok(rules)


## 验证只含已知属性且所有数值非负的常驻加成。
## [param raw] 配置边界。
## 返回是否合法。
static func _valid_bonus(raw: Variant) -> bool:
	if not raw is Dictionary or raw.is_empty(): return false
	for key: Variant in raw:
		if key not in ATTRIBUTES or not integer(raw[key], 0, 100000): return false
	return true


## 检查有限整数，拒绝字符串、布尔及小数截断。
## [param value] 原值。[param minimum] 下限。[param maximum] 上限。
## 返回范围内整数时为真。
static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


## 构造无效配置结果。
## 返回中枢配置错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"central.rules", "中枢规则无效")
