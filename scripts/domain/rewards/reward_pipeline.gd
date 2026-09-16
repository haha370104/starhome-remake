class_name RewardPipeline
extends RefCounted

var _providers: Array[RewardModifierProvider] = []


## 组合统一奖励切面；默认保留食品适配器且不附加任何运营倍率。
func _init() -> void:
	_providers.append(FoodRewardModifierProvider.new())


## 注册受信任的规则提供者，供VIP服务、活动或药品模块扩展。
## [param provider] 不接触客户端载荷的类型化提供者。
func add_provider(provider: RewardModifierProvider) -> void:
	if provider != null and provider not in _providers:
		_providers.append(provider)


## 在入账或随机判定之前统一结算倍率，独立来源相乘、互斥组取最高。
## [param context] 权威账号、目标和时间事实。
## [param base_amount] 尚未应用本切面的基础经验或掉落概率。
## 返回含来源明细的结算值；非法数值、重复规则或溢出一律拒绝。
func settle(context: RewardContext, base_amount: float) -> DomainResult:
	if context == null or context.channel not in [&"experience", &"drop"] or context.now < 0 or not is_finite(base_amount) or base_amount < 0:
		return DomainResult.failure(&"reward.invalid_context", "奖励上下文或基础值无效")
	var seen := {}
	var selected := {}
	for provider: RewardModifierProvider in _providers:
		for rule: RewardModifier in provider.modifiers_for(context):
			if not rule.matches(context):
				continue
			if rule.id.is_empty() or seen.has(rule.id) or not is_finite(rule.multiplier) or rule.multiplier < 0:
				return DomainResult.failure(&"reward.invalid_modifier", "重复或无效的奖励规则")
			seen[rule.id] = true
			var key := "rule:" + rule.id if rule.stack_group.is_empty() else "group:" + rule.stack_group
			var previous: RewardModifier = selected.get(key)
			if previous == null or rule.multiplier > previous.multiplier or (rule.multiplier == previous.multiplier and rule.id < previous.id):
				selected[key] = rule
	var result := RewardSettlement.new()
	result.base_amount = base_amount
	var keys: Array = selected.keys()
	keys.sort()
	for key: String in keys:
		var rule: RewardModifier = selected[key]
		result.multiplier *= rule.multiplier
		result.applied.append(rule)
	result.final_amount = base_amount * result.multiplier
	if not is_finite(result.multiplier) or not is_finite(result.final_amount):
		return DomainResult.failure(&"reward.overflow", "奖励倍率计算溢出")
	return DomainResult.ok(result)
