class_name SamaRules
extends RefCounted

const OPERATIONS := ["growth", "quality", "transfer"]
const ATTRIBUTES := ["max_health", "defense", "energy_cannon_attack", "missile_attack"]

class Profile extends RefCounted:
	var location: int
	var effect: String

class Offer extends RefCounted:
	var definition_id: String
	var color: int
	var unit_price: int

var profiles: Dictionary[String, Profile] = {}
var offers: Dictionary[String, Offer] = {}
var materials: Dictionary[String, String] = {}
var color_caps: Array[int] = []
var color_health: Array[int] = []
var color_attack: Array[int] = []
var growth_costs: Array[int] = []
var chance_percent: Array[int] = []
var duration_seconds: Array[int] = []
var duration_additions: Array[int] = []
var damage_base: Array[int] = []
var pulse_additions: Array[int] = []
var fission_additions: Array[int] = []
var growth_health: int
var quality_health: int
var growth_attack: int
var quality_attack: int
var quality_cost: int
var transfer_amethyst: int
var pulse_range: int
var visuals: Dictionary = {}


## 将原版核查表转换为独立规则，拒绝不完整数组和重复部件。
## [param raw] JSON配置边界。
## 返回可供装备共享的规则或配置失败。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := SamaRules.new()
	if raw.get("schema_version") != 1: return _invalid()
	for key: String in ["color_caps", "color_health", "color_attack", "growth_costs", "chance_percent", "duration_seconds", "duration_additions", "damage_base", "pulse_additions", "fission_additions"]:
		var count := 4
		if key.ends_with("additions"): count = 11
		elif key == "growth_costs": count = 10
		if not raw.get(key) is Array or raw[key].size() != count: return _invalid()
		var values: Array[int] = []
		for value: Variant in raw[key]:
			if not SamaRules.integer(value, 0, 100000): return _invalid()
			values.append(int(value))
		rules.set(key, values)
	if rules.color_caps != [1, 3, 6, 10]: return _invalid()
	for key: String in ["growth_health", "quality_health", "growth_attack", "quality_attack", "quality_cost", "transfer_amethyst", "pulse_range"]:
		if not SamaRules.integer(raw.get(key), 1, 100000): return _invalid()
		rules.set(key, int(raw[key]))
	if not raw.get("materials") is Dictionary or not raw.get("visuals") is Dictionary: return _invalid()
	for key: String in ["growth", "quality"]:
		if not raw.materials.get(key) is String or String(raw.materials[key]).is_empty(): return _invalid()
		rules.materials[key] = String(raw.materials[key])
	var locations: Array[int] = []
	for row: Dictionary in raw.get("profiles", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.profiles.has(id) or not SamaRules.integer(row.get("location"), 19, 22) \
			or int(row.location) in locations or row.get("effect") not in ["piercing", "pulse", "fission", "pvp_absorption"]: return _invalid()
		var profile := Profile.new()
		profile.location = int(row.location)
		profile.effect = String(row.effect)
		rules.profiles[id] = profile
		locations.append(profile.location)
	for row: Dictionary in raw.get("offers", []):
		var id := String(row.get("id", ""))
		if id.is_empty() or rules.offers.has(id) or not row.get("definition_id") is String \
			or not SamaRules.integer(row.get("color"), 0, 3) or not SamaRules.integer(row.get("unit_price"), 1, 10000000): return _invalid()
		var offer := Offer.new()
		offer.definition_id = String(row.definition_id)
		offer.color = int(row.color)
		offer.unit_price = int(row.unit_price)
		rules.offers[id] = offer
	if rules.profiles.size() != 4: return _invalid()
	rules.visuals = raw.visuals.duplicate(true)
	return DomainResult.ok(rules)


## 拒绝缺失或不符合原版维度的配置。
## 返回明确配置错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"sama.rules", "撒玛装备规则无效")


## 校验协议及存档有限整数，不允许字符串、布尔和截断。
## [param value] 原值。[param minimum] 下限。[param maximum] 上限。
## 返回是否为范围内整数。
static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum
