class_name ClothingEnhancementRules
extends RefCounted

const PATH := "res://data/gameplay/clothing_enhancement_rules_v1.json"
static var _cached: ClothingEnhancementRules
var _gems := PackedFloat64Array()
var _prefix_percent: Array[PackedFloat64Array] = []
var _prefix_penalty: Array[PackedFloat64Array] = []
var _trait_values: Array[PackedFloat64Array] = []


## 在配置边界验证所有效果的有限非负数值并转换为类型化数组。
## 返回可供领域对象使用的目录或配置错误。
static func load_default() -> DomainResult:
	if _cached != null:
		return DomainResult.ok(_cached)
	var loaded := JsonConfigLoader.load_dictionary(PATH)
	if not loaded.is_ok:
		return loaded
	var raw: Dictionary = loaded.value
	if int(raw.get("schema_version", 0)) != 1:
		return DomainResult.failure(&"enhancement.invalid_rules", "强化数值目录版本错误")
	var rules := ClothingEnhancementRules.new()
	for id: String in ClothingEnhancement.GEMS:
		var value := float(raw.get("gems", {}).get(id, -1))
		if not is_finite(value) or value <= 0.0:
			return DomainResult.failure(&"enhancement.invalid_rules", "宝石增量配置错误")
		rules._gems.append(value)
	for id: String in ClothingEnhancement.PREFIXES:
		var row: Dictionary = raw.get("prefixes", {}).get(id, {})
		for key: String in ["percent", "penalty"]:
			var values := _six_values(row.get(key))
			if values.size() != 6:
				return DomainResult.failure(&"enhancement.invalid_rules", "前缀品质配置错误")
			if key == "percent":
				rules._prefix_percent.append(values)
			else:
				rules._prefix_penalty.append(values)
	for id: String in ClothingEnhancement.TRAITS:
		var values := _six_values(raw.get("traits", {}).get(id))
		if values.size() != 6:
			return DomainResult.failure(&"enhancement.invalid_rules", "特性品质配置错误")
		rules._trait_values.append(values)
	_cached = rules
	return DomainResult.ok(rules)


## 查询一段宝石的固定增量。
## [param id] 属性类型。
## 返回目录中的固定值；未知类型为零。
func gem_increment(id: String) -> float:
	var index := ClothingEnhancement.GEMS.find(id)
	return _gems[index] if index >= 0 else 0.0


## 查询某档特性数值。
## [param id] 特性类型。
## [param quality] 一至六品质。
## 返回数值；非法输入返回零。
func trait_value(id: String, quality: int) -> float:
	var index := ClothingEnhancement.TRAITS.find(id)
	return _trait_values[index][quality - 1] if index >= 0 and quality in range(1, 7) else 0.0


## 将一个前缀按明确的属性关联计入汇总。
## [param bonuses] 同一玩家的效果汇总。
## [param id] 前缀类型。
## [param quality] 一至六品质。
func apply_prefix(bonuses: ClothingBonuses, id: String, quality: int) -> void:
	var index := ClothingEnhancement.PREFIXES.find(id)
	if index < 0 or quality not in range(1, 7):
		return
	var percent := _prefix_percent[index][quality - 1]
	var penalty := _prefix_penalty[index][quality - 1]
	match id:
		"tiger":
			bonuses.add_prefix("max_health", percent, 0)
			for weapon: String in ["energy_cannon_attack", "missile_attack", "rocket_attack"]:
				bonuses.add_prefix(weapon, 0, penalty)
		"turtle":
			bonuses.add_prefix("defense", percent, 0)
			bonuses.add_prefix("movement_speed", 0, penalty)
		"dragon":
			for weapon: String in ["energy_cannon_attack", "missile_attack", "rocket_attack"]:
				bonuses.add_prefix(weapon, percent, 0)
			bonuses.add_prefix("defense", 0, penalty)
		"phoenix":
			bonuses.add_prefix("movement_speed", percent, 0)
			bonuses.add_prefix("max_health", 0, penalty)


## 转换六档品质的外部数组。
## [param raw] 未可信的配置字段。
## 返回有限非负六元素数组；格式错误为空。
static func _six_values(raw: Variant) -> PackedFloat64Array:
	var result := PackedFloat64Array()
	if not raw is Array or raw.size() != 6:
		return result
	for value: Variant in raw:
		if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)) or float(value) < 0.0:
			return PackedFloat64Array()
		result.append(float(value))
	return result
