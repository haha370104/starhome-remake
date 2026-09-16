class_name RewardModifierProvider
extends RefCounted

var _rules: Array[RewardModifier] = []


## 保存已校验的配置规则；动态VIP、药品提供者可继承本端口。
## [param rules] 服务端解析好的类型化规则。
func _init(rules: Array[RewardModifier] = []) -> void:
	_rules = rules.duplicate()


## 按权威事实选出本提供者当前有效的规则。
## [param context] 单次结算上下文。
## 返回匹配规则，不修改玩家或基础奖励。
func modifiers_for(context: RewardContext) -> Array[RewardModifier]:
	var matched: Array[RewardModifier] = []
	for rule: RewardModifier in _rules:
		if rule.matches(context):
			matched.append(rule)
	return matched
