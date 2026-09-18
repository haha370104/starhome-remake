class_name AustinGlensRules
extends RefCounted

const ATTRIBUTES := ["max_health", "defense", "energy_cannon_attack", "missile_attack", "self_repair_bonus"]
const MATERIALS := ["light_essence", "primal_spirit", "eternal_energy", "magic_core", "dispel_stone", "heritage_blessing", "space_crystal"]
const OPERATIONS := ["color", "stage", "base", "additional", "blessing", "unlock", "inlay"]

class Profile extends RefCounted:
	var location: int
	var effect: String

class Rune extends RefCounted:
	var definition_id: String
	var location: int
	var slot: int
	var bonuses: Dictionary[String, int] = {}

var profiles: Dictionary[String, Profile] = {}
var runes: Dictionary[String, Rune] = {}
var materials: Dictionary[String, String] = {}
var offers: Dictionary[String, int] = {}
var color_health: Array[int] = []
var color_defense: Array[int] = []
var color_penetration: Array[int] = []
var stage_cannon: Array[int] = []
var stage_missile: Array[int] = []
var stage_penetration: Array[int] = []
var base_repair: Array[int] = []
var level_costs: Array[int] = []
var space_costs: Array[int] = []
var color_costs: Array[int] = []
var color_space_costs: Array[int] = []
var mitigation: Array[int] = []
var healing: Array[int] = []
var blessing_bonuses: Dictionary[String, int] = {}
var blessing_cost: int
var blessing_space_cost: int
var unlock_cost: int
var inlay_cost: int
var trigger_chance: float
var cooldown_seconds: int


## 将已核查的原版表转成独立类型化规则，并拒绝悬空维度和重复槽位。
## [param raw] JSON配置边界。
## 返回可供实例共用的只读规则或配置错误。
static func from_dictionary(raw: Dictionary) -> DomainResult:
	var rules := AustinGlensRules.new()
	if raw.get("schema_version") != 1: return _invalid()
	for key: String in ["color_health", "color_defense", "color_penetration", "stage_cannon", "stage_missile", "stage_penetration", "base_repair", "level_costs", "space_costs", "color_costs", "color_space_costs", "mitigation", "healing"]:
		var count := 11
		if key in ["color_health", "color_defense", "color_penetration"]: count = 4
		elif key in ["level_costs", "space_costs"]: count = 10
		elif key in ["color_costs", "color_space_costs"]: count = 3
		if not raw.get(key) is Array or raw[key].size() != count: return _invalid()
		var values: Array[int] = []
		for value: Variant in raw[key]:
			if not integer(value, 0, 100000): return _invalid()
			values.append(int(value))
		rules.set(key, values)
	for key: String in ["blessing_cost", "blessing_space_cost", "unlock_cost", "inlay_cost", "cooldown_seconds"]:
		if not integer(raw.get(key), 1, 100000): return _invalid()
		rules.set(key, int(raw[key]))
	var chance: Variant = raw.get("trigger_chance")
	if not (chance is int or chance is float) or not is_finite(float(chance)) or chance < 0 or chance > 1: return _invalid()
	rules.trigger_chance = float(chance)
	if not raw.get("materials") is Dictionary or not raw.get("blessing_bonuses") is Dictionary: return _invalid()
	for key: String in MATERIALS:
		if not raw.materials.get(key) is String or String(raw.materials[key]).is_empty(): return _invalid()
		rules.materials[key] = String(raw.materials[key])
	for key: String in raw.blessing_bonuses:
		if key not in ATTRIBUTES or not integer(raw.blessing_bonuses[key], 1, 100000): return _invalid()
		rules.blessing_bonuses[key] = int(raw.blessing_bonuses[key])
	var locations: Array[int] = []
	for row: Dictionary in raw.get("profiles", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.profiles.has(id) or not integer(row.get("location"), 24, 27) \
			or int(row.location) in locations or row.get("effect") not in ["mitigation", "healing", "pvp_cannon", "pvp_missile"]: return _invalid()
		var profile := Profile.new()
		profile.location = int(row.location)
		profile.effect = String(row.effect)
		rules.profiles[id] = profile
		locations.append(profile.location)
	var combinations := PackedStringArray()
	for row: Dictionary in raw.get("runes", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.runes.has(id) or not integer(row.get("location"), 24, 27) \
			or not integer(row.get("slot"), 0, 1) or not row.get("bonuses") is Dictionary: return _invalid()
		var key := "%d:%d" % [row.location, row.slot]
		if key in combinations: return _invalid()
		combinations.append(key)
		var rune := Rune.new()
		rune.definition_id = id
		rune.location = int(row.location)
		rune.slot = int(row.slot)
		for attribute: String in row.bonuses:
			if attribute not in ATTRIBUTES or not integer(row.bonuses[attribute], 1, 100000): return _invalid()
			rune.bonuses[attribute] = int(row.bonuses[attribute])
		if rune.bonuses.is_empty(): return _invalid()
		rules.runes[id] = rune
	for row: Dictionary in raw.get("offers", []):
		var id := String(row.get("definition_id", ""))
		if id.is_empty() or rules.offers.has(id) or not integer(row.get("unit_price"), 1, 10000000): return _invalid()
		rules.offers[id] = int(row.unit_price)
	if rules.profiles.size() != 4 or rules.runes.size() != 8: return _invalid()
	return DomainResult.ok(rules)


## 按装备位置和孔位寻找唯一许可符文，运行时不猜测物品名称。
## [param location] 装备固定位置。[param slot] 左右孔索引。
## 返回允许的符文，未定义时为空。
func rune_at(location: int, slot: int) -> Rune:
	for rune: Rune in runes.values():
		if rune.location == location and rune.slot == slot: return rune
	return null


## 验证存档和协议中的有限整数，不接受字符串与布尔替代。
## [param value] 原始值。[param minimum] 下限。[param maximum] 上限。
## 返回是否满足整数范围。
static func integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum


## 生成规则加载失败，禁止静默采用另一套装备的默认值。
## 返回明确的领域错误。
static func _invalid() -> DomainResult:
	return DomainResult.failure(&"austin.rules", "奥斯格兰规则无效")
