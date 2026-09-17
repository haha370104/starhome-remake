extends SceneTree

var checks := 0
var failures := 0


## 穷举七种纤维的百级收益与每五级材料阶梯，拒绝伪造成长事实。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "目录可加载")
	var rules := catalog.clothing_improvement_rules
	_check(rules.slots.size() == 49, "原版49件时装")
	var id: String = rules.slots.keys()[0]
	for channel: ClothingImprovementRules.Channel in rules.channels.values():
		var state := ClothingImprovement.new()
		var material := catalog.create(channel.material_id, {"instance_id": channel.material_id})
		_check(material.is_ok and material.value is ClothingImprovementMaterial, "纤维类型")
		for level in range(100):
			var quantity := 1 << (floori(level / 5.0) + 1)
			var quote := state.preview(id, rules, channel.attribute, quantity)
			_check(quote.is_ok and quote.value.chance == 1.0, "每五级材料翻倍")
			_check(quote.value.bonus_after == channel.increment * (level + 1), "逐级固定增益")
			_check(not state.preview(id, rules, channel.attribute, quantity + 1).is_ok, "拒绝浪费过量纤维")
			var failed := state.apply(id, rules, channel.attribute, quantity / 2, 0.5)
			_check(failed.is_ok and not failed.value.success and state.level == level, "失败边界保留等级")
			_check(state.apply(id, rules, channel.attribute, quantity, 0.99999).is_ok and state.level == level + 1, "保证成功")
			var restored := catalog.create(id, {"instance_id": "fashion", "clothing_improvement": state.to_dictionary()})
			_check(restored.is_ok and restored.value.improvement.level == level + 1, "目录恢复成长")
			var other := "defense" if channel.attribute != "defense" else "max_health"
			_check(not state.preview(id, rules, other, quantity).is_ok, "禁止改换方向")
		_check(not state.preview(id, rules, channel.attribute, 1048576).is_ok, "百级封顶")
	var state := ClothingImprovement.new()
	_check(not state.apply(id, rules, "defense", 2, NAN).is_ok, "拒绝非法随机数")
	for invalid: Variant in [{"level": -1}, {"level": 101, "attribute": "defense"}, {"level": 1.1, "attribute": "defense"}, {"level": 1}, {"attribute": "defense"}, {"version": 2}, []]:
		_check(not ClothingImprovement.restore(invalid).is_ok, "拒绝非法存档")
	_check(not catalog.create("recruit_tank", {"instance_id": "bad", "clothing_improvement": {"level": 1, "attribute": "defense"}}).is_ok, "不能给战车伪造成长")
	var high: ClothingImprovement = ClothingImprovement.restore({"level": 99, "attribute": "defense"}).value
	_check(not high.preview(id, rules, "defense", 9999).is_ok, "原版整数百分比拒绝0%")
	_check(high.preview(id, rules, "defense", 10486).value.chance == 0.01, "跨堆叠1%可尝试")
	print("Clothing improvement model: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## 记录独立断言，继续覆盖所有属性与档位。
## [param condition] 期望条件。
## [param message] 失败定位。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)
