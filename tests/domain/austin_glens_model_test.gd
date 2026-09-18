extends SceneTree

var checks := 0
var failures := PackedStringArray()


## 核对四件装备的原版成长、固定符文、拒绝边界和真实JSON恢复。
func _initialize() -> void:
	var raw: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/austin_glens_rules_v1.json").value
	var parsed := AustinGlensRules.from_dictionary(raw)
	_check(parsed.is_ok, "rules")
	if not parsed.is_ok:
		quit(1)
		return
	var rules: AustinGlensRules = parsed.value
	for profile: AustinGlensRules.Profile in rules.profiles.values():
		var growth := AustinGlensGrowth.new()
		_check(growth.to_dictionary().is_empty(), "legacy default")
		_check(growth.bonus("max_health", rules) == 30 and growth.bonus("energy_cannon_attack", rules) == 2 and growth.bonus("missile_attack", rules) == 2, "original baseline includes two zero-level tracks")
		for level in 3:
			var cost := growth.change("color", profile, rules).value as Array
			_check(cost[0].quantity == [10, 20, 40][level] and cost[1].quantity == [5, 10, 20][level], "color cost")
		var before := growth.to_dictionary()
		_check(not growth.change("color", profile, rules).is_ok and growth.to_dictionary() == before, "color cap atomic")
		for mode: String in ["stage", "base", "additional"]:
			if mode == "additional" and profile.effect.begins_with("pvp"):
				_check(growth.change(mode, profile, rules).error_code == &"austin.pvp_only" and growth.to_dictionary() == before, "no charge for unavailable PvP growth")
				continue
			for level in 10:
				var result := growth.change(mode, profile, rules)
				_check(result.is_ok and result.value[0].quantity == (2 if level == 0 else level * 4), "exact original level cost")
			before = growth.to_dictionary()
			_check(not growth.change(mode, profile, rules).is_ok and growth.to_dictionary() == before, "level cap atomic")
		_check(growth.change("blessing", profile, rules).is_ok, "bless")
		_check(not growth.change("blessing", profile, rules).is_ok, "one blessing")
		_check(growth.bonus("max_health", rules) == 150 and growth.bonus("defense", rules) == 4 and growth.bonus("self_repair_bonus", rules) == 4, "max passive baseline")
		_check(growth.bonus("energy_cannon_attack", rules) == 17 and growth.bonus("missile_attack", rules) == 17, "max attacks")
		for index in 2:
			var rune := rules.rune_at(profile.location, index)
			before = growth.to_dictionary()
			_check(not growth.change("inlay", profile, rules, index, rune.definition_id).is_ok and growth.to_dictionary() == before, "closed slot cannot inlay")
			_check(growth.change("unlock", profile, rules, index).value[0].quantity == 4, "four dispel stones per opening")
			before = growth.to_dictionary()
			_check(not growth.change("inlay", profile, rules, index, rules.rune_at(profile.location, 1 - index).definition_id).is_ok and growth.to_dictionary() == before, "wrong side rejects")
			var inlay := growth.change("inlay", profile, rules, index, rune.definition_id, true)
			_check(inlay.is_ok and inlay.value.size() == 2 and inlay.value[0].quantity == 1 and inlay.value[1].quantity == 1, "one rune and one stone")
			_check(not growth.change("inlay", profile, rules, index, rune.definition_id).is_ok, "cannot overwrite permanent rune")
		_check(growth.validate_for(profile, rules).is_ok, "correct fixed runes")
		var restored := AustinGlensGrowth.restore(JSON.parse_string(JSON.stringify(growth.to_dictionary())))
		_check(restored.is_ok and restored.value.to_dictionary() == growth.to_dictionary(), "JSON numeric normalization")
		_check(not growth.validate_for(null, rules).is_ok, "foreign equipment rejects")
		before = growth.to_dictionary()
		var bad := before.duplicate(true)
		bad.slots[0].opened = false
		_check(not AustinGlensGrowth.restore(bad).is_ok, "closed occupied slot rejects")
		bad = before.duplicate(true)
		bad.stage = 1.5
		_check(not AustinGlensGrowth.restore(bad).is_ok, "fractional level rejects")
		bad = before.duplicate(true)
		bad.blessed = 1
		_check(not AustinGlensGrowth.restore(bad).is_ok, "boolean required")
		bad = before.duplicate(true)
		bad.slots[0].rune_id = "austin.not-a-rune"
		_check(not AustinGlensGrowth.restore(bad).value.validate_for(profile, rules).is_ok, "unknown rune rejects")
	var wrong := raw.duplicate(true)
	wrong.trigger_chance = NAN
	_check(not AustinGlensRules.from_dictionary(wrong).is_ok, "finite proc chance")
	wrong = raw.duplicate(true)
	wrong.runes[0].location = 23
	_check(not AustinGlensRules.from_dictionary(wrong).is_ok, "rune location bounds")
	wrong = raw.duplicate(true)
	wrong.stage_cannon = [1]
	_check(not AustinGlensRules.from_dictionary(wrong).is_ok, "no truncated attribute arrays")
	print("Austin model: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录规则不变量，集中报告失败。
## [param condition] 验证结果。[param message] 场景说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
