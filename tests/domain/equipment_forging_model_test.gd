extends SceneTree

var _checks := 0
var _failures := PackedStringArray()


## 穷举已确认PVE方向的最高值、回退、序列化及加工上限扩展。
func _initialize() -> void:
	var raw: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_forging_rules_v1.json").value
	var loaded := EquipmentForgingRules.from_dictionary(raw)
	_check(loaded.is_ok, "load")
	if not loaded.is_ok: quit(1); return
	var rules: EquipmentForgingRules = loaded.value
	var processing: EquipmentProcessingRules = EquipmentProcessingRules.from_dictionary(JsonConfigLoader.load_dictionary("res://data/gameplay/equipment_processing_rules_v1.json").value).value
	_check(rules.profiles.size() == 102 and rules.channels.size() == 8, "eligible ordinary PVE equipment")
	_check(rules.chances == [0.25, 0.60, 0.95], "original probabilities")
	for id: String in rules.profiles:
		var profile: EquipmentForgingRules.Profile = rules.profiles[id]
		for kind: int in profile.limits:
			var channel: EquipmentForgingRules.Channel = rules.channels[kind]
			var forged := EquipmentForging.new()
			_check(forged.apply(channel, profile, false).value.after == 0, "zero floor")
			while forged.extensions.get(kind, 0) < profile.limits[kind]:
				_check(forged.apply(channel, profile, true).is_ok, "growth step")
			_check(forged.extensions[kind] == profile.limits[kind], "original cap")
			_check(not forged.apply(channel, profile, true).is_ok, "over cap rejected")
			var restored := EquipmentForging.restore(JSON.parse_string(JSON.stringify(forged.to_dictionary())))
			_check(restored.is_ok and restored.value.validate_for(profile).is_ok, "JSON round trip")
			var base := processing.profile(id)
			var expanded := forged.expanded_processing(base, rules)
			if channel.expands_processing and base.attributes.has(channel.attribute):
				_check(expanded.attributes[channel.attribute].limit == base.attributes[channel.attribute].limit + profile.limits[kind], "expanded processing")
				var value := EquipmentProcessing.new()
				value._increments[channel.attribute] = int(expanded.attributes[channel.attribute].limit - expanded.attributes[channel.attribute].base)
				_check(value.validate_for(expanded).is_ok and not value.validate_for(base).is_ok, "extension allows extra work without editing shared profile")
			_check(forged.direct_bonus(channel.attribute, rules) == (profile.limits[kind] if channel.direct_bonus else 0), "direct effects distinct from limits")
			forged.extensions[kind] = channel.step
			_check(forged.apply(channel, profile, false).value.after == 0, "one-step failure")
			forged.extensions[kind] = profile.limits[kind] + 1
			_check(not forged.validate_for(profile).is_ok, "reject corrupt saved cap")
	for invalid: Variant in [1, [], {"version": 2}, {"extensions": []}, {"extensions": {"9": 1}}, {"extensions": {"1": -1}}, {"extensions": {"1": 1.5}}, {"extensions": {"1": INF}}, {"extensions": {1: 1}}]:
		_check(not EquipmentForging.restore(invalid).is_ok, "reject invalid save")
	_check(EquipmentForging.restore({}).value.to_dictionary().is_empty(), "old save default")
	print("Equipment forging model: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 记录边界断言。
## [param condition] 期望结果。
## [param label] 故障说明。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
