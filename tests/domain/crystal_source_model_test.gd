extends SceneTree

var _checks := 0
var _failures := PackedStringArray()


## 核对原版分段值、独立三核、失败退级、绑定裂纹以及非法状态拒绝。
func _initialize() -> void:
	var data := JsonConfigLoader.load_dictionary("res://data/gameplay/crystal_source_rules_v1.json")
	var parsed := CrystalSourceRules.from_dictionary(data.value)
	_check(parsed.is_ok, "rules load")
	if not parsed.is_ok:
		quit(1)
		return
	var rules: CrystalSourceRules = parsed.value
	var expected := {28: [800, 1150], 29: [90, 135], 30: [115, 170], 31: [65, 100]}
	for id: String in rules.profiles:
		var profile := rules.profiles[id]
		var value := CrystalSourceGrowth.new()
		_check(value.bonus(profile.attribute, profile, rules) == profile.base, "original base " + id)
		value.quality = 10
		value.growth = 10
		_check(value.bonus(profile.attribute, profile, rules) == expected[profile.location][0], "level ten " + id)
		value.quality = 15
		value.growth = 15
		_check(value.bonus(profile.attribute, profile, rules) == expected[profile.location][1], "level fifteen " + id)
		_check(value.bonus("defense", profile, rules) == 0, "no invented defense")
		_check(not value.advance("quality", true, false, rules).is_ok, "quality cap")
		_check(not value.advance("growth", true, false, rules).is_ok, "growth cap")
	var profile: CrystalSourceRules.Profile = rules.profiles.values()[0]
	var value := CrystalSourceGrowth.new()
	var red := _core(rules, "red", 5, 2, true)
	_check(value.inlay(0, red, rules).is_ok, "inlay bound two crack core")
	_check(not value.inlay(1, _core(rules, "red", 1), rules).is_ok, "same color rejected regardless of level")
	_check(value.inlay(1, _core(rules, "yellow", 4), rules).is_ok, "yellow accepted")
	_check(value.inlay(2, _core(rules, "black", 3), rules).is_ok, "black accepted")
	_check(not value.inlay(3, red, rules).is_ok, "no fourth slot")
	_check(value.bonus("energy_cannon_attack", null, rules) == 0, "unrelated item has no passive")
	_check(value.bonus("energy_cannon_attack", profile, rules) == 20 + (profile.base if profile.attribute == "energy_cannon_attack" else 0), "red original +20")
	_check(value.bonus("max_health", profile, rules) == 80 + (profile.base if profile.attribute == "max_health" else 0), "yellow original +80")
	_check(value.bonus("missile_attack", profile, rules) == 9 + (profile.base if profile.attribute == "missile_attack" else 0), "black original +9")
	var cloned: CrystalSourceGrowth = CrystalSourceGrowth.restore(JSON.parse_string(JSON.stringify(value.to_dictionary()))).value
	_check(cloned.validate_for(profile, rules).is_ok and cloned.slots[0].cracks == 2 and cloned.slots[0].bound, "JSON core facts")
	_check(not cloned.validate_for(null, rules).is_ok, "foreign state rejected")
	cloned.slots[1].definition_id = red.definition_id
	_check(not cloned.validate_for(profile, rules).is_ok, "duplicate color save rejected")
	cloned.slots[1].definition_id = "iron_piece"
	_check(not cloned.validate_for(profile, rules).is_ok, "ordinary material cannot become core")
	for sample: Array in [[0, 0], [2, 2], [3, 2], [6, 5], [7, 5], [12, 5], [13, 0], [14, 0]]:
		value = CrystalSourceGrowth.new()
		value.quality = sample[0]
		_check(value.advance("quality", false, false, rules).is_ok and value.quality == sample[1], "original failure cliff")
		if sample[0] >= 3:
			value.quality = sample[0]
			_check(value.advance("quality", false, true, rules).is_ok and value.quality == sample[0], "quality protection")
	_check(not CrystalSourceGrowth.new().advance("growth", true, true, rules).is_ok, "growth cannot consume quality protector")
	for invalid: Variant in [1, [], {"version": 2}, {"version": 1, "quality": 1.5, "growth": 0, "slots": [{}, {}, {}]}, {"version": 1, "quality": 0, "growth": 16, "slots": [{}, {}, {}]}, {"version": 1, "quality": 0, "growth": 0, "slots": []}]:
		_check(not CrystalSourceGrowth.restore(invalid).is_ok, "invalid state")
	var split := red.copy_stack("split", 3) as CrystalSourceCore
	_check(split.cracks == 2 and split.bound and split.profile == red.profile and red.can_stack_with(split), "split retains typed facts")
	split.cracks = 1
	_check(not red.can_stack_with(split), "no crack laundering")
	_check(rules.core_at("red", 6) == null and rules.core_at("blue", 1) == null, "only original unlocked levels and colors")
	for key: String in ["required_level", "growth_chance", "quality_chances", "equipment", "cores"]:
		var broken: Dictionary = data.value.duplicate(true)
		broken.erase(key)
		_check(not CrystalSourceRules.from_dictionary(broken).is_ok, "missing rules rejected " + key)
	print("Crystal source model: %d checks, %d failures" % [_checks, _failures.size()])
	for failure: String in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 创建不依赖运行目录接线的专属核心测试样本。
## [param rules] 原版规则。[param color] 颜色。[param level] 等级。[param cracks] 裂纹。[param bound] 绑定。
## 返回具有完整类型与规则的样本。
func _core(rules: CrystalSourceRules, color: String, level: int, cracks: int = 0, bound: bool = false) -> CrystalSourceCore:
	var profile := rules.core_at(color, level)
	var core := CrystalSourceCore.new({"id": profile.definition_id, "max_stack": 999},
		{"instance_id": profile.definition_id, "quantity": 10, "crystal_source_cracks": cracks, "bound": bound})
	core.profile = profile
	return core


## 记录单项验收，不掩盖后续独立失败。
## [param condition] 断言条件。[param message] 检查描述。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition: _failures.append(message)
