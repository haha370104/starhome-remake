extends SceneTree

var checks := 0
var failures := PackedStringArray()


## 验证中枢角色进化与六件装备成长分别持有事实，原版分档和失败原子性可复现。
func _initialize() -> void:
	var raw: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/central_rules_v1.json").value
	var parsed := CentralRules.from_dictionary(raw)
	_check(parsed.is_ok, "audited free rules")
	if not parsed.is_ok:
		quit(1)
		return
	var rules: CentralRules = parsed.value
	for id: String in rules.profiles:
		var profile := rules.profiles[id]
		var growth := CentralGrowth.new()
		_check(growth.bonus("max_health", profile, rules) in [300, 500], "scaled original base")
		for stage in 18:
			var result := growth.advance(rules)
			_check(result.is_ok and result.value[0].definition_id == rules.growth_materials[floori(stage / 3.0)] and result.value[0].quantity == 1, "original material band")
		_check(growth.bonus("max_health", profile, rules) == profile.base.max_health + 3300, "eighteen stages health")
		_check(growth.bonus("energy_cannon_attack", profile, rules) == profile.base.energy_cannon_attack + 330, "eighteen stages cannon")
		_check(growth.bonus("missile_attack", profile, rules) == profile.base.missile_attack + 330, "eighteen stages missile")
		_check(growth.bonus("defense", profile, rules) == 0, "no invented accessory defense")
		var before := growth.to_dictionary()
		_check(not growth.advance(rules).is_ok and growth.to_dictionary() == before, "max atomic")
		_check(CentralGrowth.restore(JSON.parse_string(JSON.stringify(before))).value.grade == 18, "equipment JSON roundtrip")
		_check(not growth.validate_for(null).is_ok, "foreign item rejected")
		_check(growth.presentation(profile).icon.ends_with("_18.png"), "original tier icon")
	for bad: Variant in [null, [], {"grade": true}, {"grade": 1.5}, {"grade": "3"}, {"grade": -1}, {"grade": 19}]:
		_check(not CentralGrowth.restore(bad).is_ok, "invalid accessory state")
	var controller := PlayerCentralController.new()
	_check(controller.core_grade() == 0 and not controller.evolve().is_ok, "fresh core")
	for id: String in CentralRules.CHIP_IDS:
		var module := rules.modules["central_%s_module_1" % id]
		var upgrade := rules.modules["central_%s_module_3" % id]
		_check(not controller.use_module(upgrade).is_ok and controller.grade(id) == 0, "requires activation")
		_check(controller.use_module(module).is_ok and controller.grade(id) == 1, "activate once")
		_check(not controller.use_module(module).is_ok, "duplicate activation")
		_check(controller.use_module(upgrade).is_ok and controller.grade(id) == 3, "upgrade item sets target")
		_check(not controller.use_module(rules.modules["central_%s_module_2" % id]).is_ok, "no downgrade")
	_check(controller.core_grade() == 3 and controller.evolve().is_ok, "six level three core evolves")
	_check(not controller.evolve().is_ok, "one permanent evolution")
	var empty := VehicleLoadout.new()
	_check(controller.bonus("max_health", empty, rules) == 5000, "evolved original total hp including unusual engine rank three")
	_check(controller.bonus("energy_cannon_attack", empty, rules) == 350, "evolved original total cannon including non-linear gun")
	_check(controller.bonus("defense", empty, rules) == 350, "evolved original total defense")
	_check(controller.bonus("rocket_attack", empty, rules) == 0, "no invented rocket buff")
	_check(controller.fatal_damage(100000, 100, 0.069, rules) == 500, "fatal capped for strong targets")
	_check(controller.fatal_damage(100, 100, 0.01, rules) == 90, "fatal original current hp percent")
	_check(controller.fatal_damage(100, 100, 0.07, rules) == 0, "fatal chance edge")
	_check(controller.fatal_damage(0, 100, 0.0, rules) == 0, "no fatal on corpse")
	_check(PlayerCentralController.restore(JSON.parse_string(JSON.stringify(controller.to_dictionary()))).value.to_dictionary() == controller.to_dictionary(), "controller JSON roundtrip")
	for bad: Variant in [null, [], {"grades": []}, {"grades": {"unknown": 1}}, {"grades": {"gun": true}}, {"grades": {"gun": 1.5}}, {"grades": {"gun": 4}}, {"evolved": 1}, {"evolved": true}]:
		_check(not PlayerCentralController.restore(bad).is_ok, "invalid controller facts")
	for key: String in ["chips", "modules", "profiles", "offers", "growth_materials", "health_increments", "fatal_chance_percent"]:
		var malformed := raw.duplicate(true)
		malformed[key] = []
		_check(not CentralRules.from_dictionary(malformed).is_ok, "incomplete rules " + key)
	print("Central growth: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总规则与失败边界断言。
## [param condition] 条件。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
