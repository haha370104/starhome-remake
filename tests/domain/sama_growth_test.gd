extends SceneTree

var checks := 0
var failures := PackedStringArray()


## 验证原版颜色阶段约束、确定材料、转移破坏条件及缩放后的属性与技能。
func _initialize() -> void:
	var result := SamaRules.from_dictionary(JsonConfigLoader.load_dictionary("res://data/gameplay/sama_rules_v1.json").value)
	_check(result.is_ok, "valid audited rules")
	if not result.is_ok:
		quit(1)
		return
	var rules: SamaRules = result.value
	for color in 4:
		var growth := SamaGrowth.new()
		growth.color = color
		_check(growth.bonus("max_health", rules) == (color + 1) * 25, "scaled base health")
		_check(not growth.advance("quality", rules).is_ok, "quality requires growth")
		for level in rules.color_caps[color]:
			_check(growth.advance("growth", rules).value[0].quantity == [5,10,20,40,60,80,110,140,170,200][level], "original growth cost")
			_check(growth.advance("quality", rules).value[0].quantity == 6, "six bound capacity cores")
			_check(not growth.advance("quality", rules).is_ok, "quality cannot exceed stage")
		var before := growth.to_dictionary()
		_check(not growth.advance("growth", rules).is_ok and growth.to_dictionary() == before, "color cap atomic")
		var parsed := SamaGrowth.restore(JSON.parse_string(JSON.stringify(before)))
		_check(parsed.is_ok and parsed.value.to_dictionary() == before, "JSON roundtrip")
		_check(not growth.validate_for(null).is_ok, "foreign equipment forbidden")
		for target_color in 4:
			var recipient := SamaGrowth.new()
			recipient.color = target_color
			var original := recipient.to_dictionary()
			var transfer := recipient.receive(growth)
			_check(transfer.is_ok == (target_color >= color), "same or higher colors only")
			_check(recipient.quality == growth.quality if transfer.is_ok else recipient.to_dictionary() == original, "transfer or unchanged recipient")
		if color == 3:
			_check(growth.bonus("max_health", rules) == 500 and growth.bonus("energy_cannon_attack", rules) == 50, "max scaled stats")
			_check(is_equal_approx(growth.chance(rules), 0.18) and growth.duration(rules) == 28, "original top skill probability/duration")
			_check(growth.damage("pulse", rules) == 300 and growth.damage("fission", rules) == 135, "scaled skill damage")
	for raw: Variant in [null, [], 1, {"version":1,"color":0,"growth":2,"quality":0}, {"version":1,"color":3,"growth":1,"quality":2}, {"version":1,"color":1.5,"growth":0,"quality":0}, {"version":1,"color":true,"growth":0,"quality":0}]:
		_check(not SamaGrowth.restore(raw).is_ok, "malformed facts rejected")
	_check(not SamaGrowth.new().receive(SamaGrowth.new()).is_ok, "empty donor rejected")
	print("Sama growth: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总不变量断言。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
