class_name ClothingBonuses
extends RefCounted

const ATTRIBUTES := ClothingEnhancement.GEMS
const TRAITS := ClothingEnhancement.TRAITS

var _flat := PackedFloat64Array()
var _percent := PackedFloat64Array()
var _penalty := PackedFloat64Array()
var _traits := PackedFloat64Array()
var active_instances := PackedStringArray()
var suppressed_effects := PackedStringArray()


## 初始化独立属性槽，避免共享可变默认值。
func _init() -> void:
	_flat.resize(ATTRIBUTES.size())
	_percent.resize(ATTRIBUTES.size())
	_penalty.resize(ATTRIBUTES.size())
	_traits.resize(TRAITS.size())


## 汇总人物装备强化，按品质或段数稳定排序，同类前缀和宝石仅计两件。
## [param clothes] 玩家当前穿着的装备实例。
## [param rules] 已校验的只读数值目录。
## 返回与战车装配解耦的类型化效果汇总。
static func collect(clothes: Array[Clothing], rules: ClothingEnhancementRules) -> ClothingBonuses:
	var result := ClothingBonuses.new()
	for item: Clothing in clothes:
		if item.durability <= 0 or item.improvement.level == 0 or item.improvement_rules == null: continue
		var channel: ClothingImprovementRules.Channel = item.improvement_rules.channels.get(item.improvement.attribute)
		if channel != null:
			result._flat[ATTRIBUTES.find(channel.attribute)] += channel.increment * item.improvement.level
			result.active_instances.append("%s:improvement" % item.instance_id)
	for family: String in ["prefix", "trait", "gem"]:
		var sorted := clothes.duplicate()
		sorted.sort_custom(func(a: Clothing, b: Clothing) -> bool:
			var ar := _rank(a.enhancement, family)
			var br := _rank(b.enhancement, family)
			return ar > br if ar != br else a.instance_id < b.instance_id)
		var accepted: Dictionary = {}
		for item: Clothing in sorted:
			if item.durability <= 0:
				continue
			var id := _effect(item.enhancement, family)
			if id.is_empty():
				continue
			var count := int(accepted.get(id, 0))
			if count >= (1 if family == "trait" else 2):
				result.suppressed_effects.append("%s:%s" % [item.instance_id, family])
				continue
			accepted[id] = count + 1
			result.active_instances.append("%s:%s" % [item.instance_id, family])
			var rank := _rank(item.enhancement, family)
			if family == "gem":
				result._flat[ATTRIBUTES.find(id)] += rules.gem_increment(id) * rank
			elif family == "trait":
				result._traits[TRAITS.find(id)] = rules.trait_value(id, rank)
			else:
				rules.apply_prefix(result, id, rank)
	return result


## 按单一乘法阶段计算属性；调用方负责临时效果与能力、上下限。
## [param attribute] 统一属性标识。
## [param base] 尚未加入强化的永久值。
## 返回应用固定宝石、前缀比例和代价后的浮点值。
func apply_value(attribute: String, base: float) -> float:
	var index := ATTRIBUTES.find(attribute)
	return base if index < 0 else (base + _flat[index]) * (1.0 + _percent[index]) - _penalty[index]


## 累加一个已验证前缀的比例和代价。
## [param attribute] 属性标识。
## [param percentage] 相加的百分比小数。
## [param penalty] 最后扣除的固定值。
func add_prefix(attribute: String, percentage: float, penalty: float) -> void:
	var index := ATTRIBUTES.find(attribute)
	if index >= 0:
		_percent[index] += percentage
		_penalty[index] += penalty


## 查询已经去重的特性强度。
## [param id] 特性稳定标识。
## 返回最高品质对应值；未装备时为零。
func trait_value(id: String) -> float:
	var index := TRAITS.find(id)
	return _traits[index] if index >= 0 else 0.0


## 根据强化种类取得用于排序的等级。
## [param state] 装备强化状态。
## [param family] 前缀、特性或宝石。
## 返回品质或实际镶嵌段数。
static func _rank(state: ClothingEnhancement, family: String) -> int:
	return state.prefix_quality if family == "prefix" else (state.trait_quality if family == "trait" else state.gem_stage)


## 根据强化种类取得同类去重身份。
## [param state] 装备强化状态。
## [param family] 前缀、特性或宝石。
## 返回类型标识；未强化为空。
static func _effect(state: ClothingEnhancement, family: String) -> String:
	return state.prefix if family == "prefix" else (state.trait_id if family == "trait" else state.gem)
