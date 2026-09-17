extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证人物强化实际状态、逐段镶嵌、同类上限与序列化边界。
func _initialize() -> void:
	var state := ClothingEnhancement.new()
	var high := _stone("gem", "movement_speed", 3)
	_expect(state.apply_stone(high).is_ok and state.gem_stage == 1, "三级石打空装备只到一段")
	_expect(not state.preview(_stone("gem", "movement_speed", 1)).is_ok, "二段拒绝一级石")
	_expect(state.apply_stone(_stone("gem", "movement_speed", 2)).is_ok and state.gem_stage == 2, "第二次累计二段")
	_expect(not state.preview(_stone("gem", "max_health", 3)).is_ok, "路线不同不能暗中替换")
	_expect(state.apply_stone(_stone("prefix", "tiger", 6)).is_ok and state.gem_stage == 2, "前缀保留宝石")
	_expect(not state.preview(_stone("prefix", "tiger", 5)).is_ok, "同类型低品质不能覆盖")
	var saved := state.to_dictionary()
	var restored: ClothingEnhancement = ClothingEnhancement.restore(saved).value
	_expect(restored.gem_stage == 2 and restored.prefix_quality == 6, "强化事实往返")
	var target := ClothingEnhancement.new()
	_expect(restored.transfer_gem_to(target).is_ok, "迁移到空装备")
	_expect(restored.gem_stage == 0 and target.gem_stage == 2 and restored.prefix_quality == 6, "迁移只移动宝石且不复制")
	_expect(not restored.transfer_gem_to(target).is_ok, "重复迁移拒绝")
	for invalid: Variant in [null, [], {"version": 2}, {"prefix": "tiger"}, {"prefix": "unknown", "prefix_quality": 1}, {"gem": "movement_speed", "gem_stage": 16}, {"gem_stage": 1}, {"gem_stage": 0.5}]:
		_expect(not ClothingEnhancement.restore(invalid).is_ok, "拒绝损坏的强化存档")
	for rank: int in range(3, 16):
		_expect(state.apply_stone(_stone("gem", "movement_speed", rank)).is_ok, "逐级镶嵌直到十五段")
	_expect(not state.preview(_stone("gem", "movement_speed", 15)).is_ok, "十五段封顶")
	_expect(_stone("gem", "defense", 1).synthesis_count() == 2, "固定宝石二合一")
	_expect(_stone("prefix", "tiger", 1).synthesis_count() == 3, "前缀品质三合一")
	_expect(_stone("gem", "defense", 15).next_definition_id().is_empty(), "十五级不再合成")
	var rules_result := ClothingEnhancementRules.load_default()
	_expect(rules_result.is_ok, "正式数值配置有效")
	if rules_result.is_ok:
		_test_bonuses(rules_result.value)
	print("Clothing enhancement: %d checks; failures=%s" % [checks, failures])
	quit(0 if failures.is_empty() else 1)


## 验证五件同类上限、破损停用、不同效果共存以及设计例子。
## [param rules] 实际读取的正式强化数值。
func _test_bonuses(rules: ClothingEnhancementRules) -> void:
	var clothes: Array[Clothing] = []
	for index: int in range(5):
		var item := Clothing.new({"id": "test.clothes", "character_slot": "upper_body"}, {"instance_id": "c%d" % index})
		item.enhancement.apply_stone(_stone("prefix", "dragon", 6))
		for rank: int in range(1, 16):
			item.enhancement.apply_stone(_stone("gem", "movement_speed", rank))
		item.enhancement.apply_stone(_stone("trait", "economy", index + 1))
		clothes.append(item)
	var bonuses := ClothingBonuses.collect(clothes, rules)
	_expect(is_equal_approx(bonuses.apply_value("energy_cannon_attack", 100), 120), "五龙只生效两件且比例相加")
	_expect(is_equal_approx(bonuses.apply_value("defense", 10), 6), "只扣两个生效龙的代价")
	_expect(is_equal_approx(bonuses.apply_value("movement_speed", 160), 220), "五件速度十五段最多贡献六十")
	_expect(is_equal_approx(bonuses.trait_value("economy"), 0.1), "同名特性取最高品质")
	clothes[4].wear(1)
	_expect(is_equal_approx(ClothingBonuses.collect(clothes, rules).trait_value("economy"), 0.08), "破损装备特性失效并回退次高品质")
	var one := Clothing.new({}, {})
	one.enhancement.apply_stone(_stone("prefix", "tiger", 6))
	for rank: int in range(1, 16):
		one.enhancement.apply_stone(_stone("gem", "max_health", rank))
	_expect(floori(ClothingBonuses.collect([one], rules).apply_value("max_health", 644)) == 913, "征服者设计例子真实执行")


## 构造测试用可信强化石，不依赖具体素材导入。
## [param family] 三套强化之一。
## [param effect] 对应类型。
## [param rank] 品质或宝石等级。
## 返回独立材料实例。
func _stone(family: String, effect: String, rank: int) -> EnhancementStone:
	return EnhancementStone.new({"id": "enhancement:%s:%s:%d" % [family, effect, rank],
		"enhancement": {"family": family, "effect": effect, "rank": rank}}, {"instance_id": "stone"})


## 累计检查并记录失败原因。
## [param condition] 实际领域行为断言。
## [param message] 中文检查说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
