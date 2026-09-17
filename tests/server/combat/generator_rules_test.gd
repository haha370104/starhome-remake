extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证原版配置、边界拒绝以及相互错开的临时状态计时。
func _initialize() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/gameplay/generator_rules_v1.json"))
	var parsed := GeneratorRules.from_dictionary(raw)
	_check(parsed.is_ok, "配置加载")
	if not parsed.is_ok: quit(1); return
	var rules: GeneratorRules = parsed.value
	_check(rules.profiles.size() == 26, "全部26发生器")
	var by_name := {}
	for profile: GeneratorRules.Profile in rules.profiles.values():
		by_name[profile.label] = profile
		_check(not profile.description().is_empty(), "说明：" + profile.label)
	var heat: GeneratorRules.Profile = by_name["高热发生器"]
	var acid: GeneratorRules.Profile = by_name["腐蚀发生器"]
	var magnet: GeneratorRules.Profile = by_name["磁化发生器"]
	_check(heat.chance == 0.03 and heat.heat_damage == 17 and heat.duration_seconds == 5, "原版高热默认1级")
	_check(acid.chance == 0.04 and acid.defense_percent_reduction == 0.35, "原版腐蚀默认2级")
	_check(magnet.chance == 0.05 and magnet.attack_percent_reduction == 0.28 and magnet.cooldown_seconds == 3, "原版磁化默认3级")
	var emperor: GeneratorRules.Profile = by_name["帝王级发生器(1级)"]
	_check(emperor.heat_damage == 120 and emperor.max_health == 1000 and emperor.defense == 80 and emperor.defense_flat_reduction == 200, "原版帝王基础值")
	_check((by_name["帝王级紫电发生器（1级）"] as GeneratorRules.Profile).heat_damage == 1200, "紫电仅原版品质0分支")
	_check((by_name["烈焰发生器"] as GeneratorRules.Profile).passive_bonus("energy_cannon_attack") == 10, "烈焰常驻加值")
	var statuses := GeneratorAfflictions.new()
	statuses.apply(heat, "a", "heat", 0, 20)
	_check(statuses.advance(19) == null, "不到1秒不伤害")
	statuses.apply(heat, "a", "heat", 19, 20)
	var pulse := statuses.advance(20)
	_check(pulse != null and pulse.damage == 17 and pulse.source_actor == "a", "刷新不延期首次伤害")
	statuses.apply(emperor, "b", "emperor", 21, 20)
	_check(statuses.advance(39) == null, "错峰效果不额外制造周期")
	pulse = statuses.advance(40)
	_check(pulse != null and pulse.damage == 120 and pulse.source_actor == "b", "最强效果及归属")
	statuses.apply(acid, "a", "acid", 40, 20)
	statuses.apply(magnet, "a", "magnet", 40, 20)
	_check(statuses.defense_after(300) == 65, "固定蚀甲后百分比腐蚀")
	_check(statuses.attack_after(100) == 72 and statuses.attack_after(100, "energy_cannon") == 40, "仅确认能量炮类型受到专属压制")
	statuses.remove_source("b")
	_check(statuses.defense_after(300) == 195 and statuses.attack_after(100, "energy_cannon") == 72, "移除来源恢复剩余较弱效果")
	statuses.remove_source("a", PackedStringArray(["heat"]))
	_check(statuses.labels() == PackedStringArray(["高热"]), "卸装移除对应状态")
	statuses.clear()
	statuses.apply(heat, "a", "heat", 3, 20)
	var total := 0
	for tick: int in range(4, 105):
		pulse = statuses.advance(tick)
		if pulse != null: total += pulse.damage
	_check(total == 85 and statuses.labels().is_empty(), "独立起点含结束秒恰好5跳")
	statuses.apply(acid, "a", "acid", 10, 20)
	statuses.apply(acid, "a", "acid2", 10, 20)
	_check(statuses.defense_after(100) == 65, "两个同类腐蚀取最强")
	statuses.clear()
	_check(statuses.defense_after(100) == 100 and statuses.attack_after(100) == 100, "清理恢复基础值")
	for invalid: Variant in [-1, NAN, INF, "3", null]:
		var changed := raw.duplicate(true)
		changed.equipment[0].chance = invalid
		_check(not GeneratorRules.from_dictionary(changed).is_ok, "拒绝非法概率")
	print("Generator rules: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总行为断言。
## [param condition] 实际条件。
## [param label] 失败描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
