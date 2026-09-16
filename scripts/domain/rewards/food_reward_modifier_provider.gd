class_name FoodRewardModifierProvider
extends RewardModifierProvider


## 将原版食品经验效果转成通用倍率，不承担技能入账或食品计时写入。
## [param context] 同一权威时刻下的技能和食品状态。
## 返回尚未过期的技能经验规则；其他食品效果继续由相应领域对象负责。
func modifiers_for(context: RewardContext) -> Array[RewardModifier]:
	var matched: Array[RewardModifier] = []
	if context.channel != &"experience" or context.food_status == null:
		return matched
	for effect: FoodEffect in context.food_status.active:
		if effect.kind <= 0 or effect.kind >= FoodEffect.SKILLS.size() or effect.expires_at <= context.now:
			continue
		if FoodEffect.SKILLS[effect.kind] != context.skill_id:
			continue
		var rule := RewardModifier.new()
		rule.id = "food.experience.%d" % effect.kind
		rule.channel = &"experience"
		rule.skill_ids = PackedStringArray([context.skill_id])
		rule.multiplier = 1.0 + float(effect.amount) / 100.0
		rule.expires_at = effect.expires_at
		rule.stack_group = "food.experience.%s" % context.skill_id
		matched.append(rule)
	return matched
