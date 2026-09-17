extends SceneTree

var checks := 0
var failures: Array[String] = []


## 检查全部原版资格、逐星封顶、普通与极限消耗，以及失败降级边界。
func _initialize() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay/equipment_strengthening_rules_v1.json"))
	var parsed := EquipmentStrengtheningRules.from_dictionary(data)
	_check(parsed.is_ok, "catalog")
	var rules: EquipmentStrengtheningRules = parsed.value
	_check(rules.profiles.size() == 116, "all eligible original equipment")
	_check(rules.profiles.has("recruit_tank") and rules.profiles.has("recruit_energy_cannon"), "starter independent strengthening allowed")
	_check(not rules.profiles.has("starter_rocket_launcher"), "no invented rocket family")
	for profile: EquipmentStrengtheningRules.Profile in rules.profiles.values():
		var growth := EquipmentStrengthening.new()
		for index: int in 10:
			var material := profile.ultimate_material if index == 9 else profile.ordinary_material
			var count := 9 if index == 9 else 4
			var outcome := growth.apply(profile, rules, material, count, 0.999)
			_check(outcome.is_ok and outcome.value.success and growth.level == index + 1, "guaranteed success " + profile.definition_id)
			_check(outcome.value.currency == 100000 and outcome.value.requirements[1].quantity == 300, "original costs")
			if index == 9: _check(outcome.value.requirements[2].quantity == 2, "two catalysts for tenth star")
		_check(not growth.preview(profile, rules, profile.ultimate_material, 9).is_ok, "cap")
		var restored: EquipmentStrengthening = EquipmentStrengthening.restore(growth.to_dictionary()).value
		_check(restored.bonus(profile.attribute, profile) == profile.values[10], "round trip exact cap")
	var profile: EquipmentStrengtheningRules.Profile = rules.profiles["recruit_tank"]
	_check(profile.values[9] == 400 and profile.values[10] == 600, "source chassis values")
	for index: int in 10:
		var growth: EquipmentStrengthening = EquipmentStrengthening.restore({"level": index}).value
		var material := profile.ultimate_material if index == 9 else profile.ordinary_material
		var result := growth.apply(profile, rules, material, 1, 0.99)
		_check(result.is_ok and not result.value.success and growth.level == maxi(0, index - (2 if index == 9 else 1)), "failure loss")
		var wrong := profile.ordinary_material if index == 9 else profile.ultimate_material
		growth.level = index
		_check(not growth.preview(profile, rules, wrong, 9).is_ok, "stage-specific stone")
	for raw: Variant in [{"level": -1}, {"level": 11}, {"level": 0.1}, {"level": NAN}, []]:
		_check(not EquipmentStrengthening.restore(raw).is_ok, "malformed state")
	var forged: EquipmentStrengthening = EquipmentStrengthening.restore({"level": 1}).value
	_check(not forged.validate_for(null).is_ok, "ineligible nonzero growth rejected")
	print("Equipment strengthening model: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言。
## [param condition] 当前检查。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
