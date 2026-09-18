class_name PlayerSkillProgression
extends RefCounted

var skills: SkillBook
var level: int
var account_id: String
var food_status: FoodStatus


## 组合技能及综合等级的一致性边界，只持有经验结算需要的账号与食品事实。
## [param book] 本次操作拥有的技能集合。[param comprehensive_level] 当前综合等级。
## [param account] 权威账号身份。[param food] 本次结算只读的食品状态。
## 设计：完整Player可委托同一行为；高频驾驶候选不需要构造背包、装备和仓库。
func _init(book: SkillBook, comprehensive_level: int, account: String, food: FoodStatus) -> void:
	skills = book
	level = comprehensive_level
	account_id = account
	food_status = food


## 通过统一奖励切面发放经验，在升级后同时重算综合等级。
## [param skill_id] 目标技能。[param amount] 倍率前经验。[param config] 权威成长规则。
## [param rewards] 同一服务器共享的奖励切面。[param source] 内部来源标识。
## [param now] 权威时间，负数使用当前Unix秒数。
## 返回升级结果、倍率明细和综合等级变化；失败不改变综合等级。
func grant_experience(skill_id: String, amount: float, config: Dictionary, rewards: RewardPipeline, source: String = "direct", now: int = -1) -> DomainResult:
	var context := RewardContext.for_account(account_id, food_status, int(Time.get_unix_time_from_system()) if now < 0 else now)
	context.skill_id = skill_id
	context.source = source
	var settled := rewards.settle(context, amount)
	if not settled.is_ok: return settled
	var settlement: RewardSettlement = settled.value
	var previous_level := level
	var granted := skills.grant_experience(skill_id, settlement.final_amount, config)
	if not granted.is_ok: return granted
	var value: Dictionary = granted.value
	if bool(value.get("upgraded", false)):
		level = skills.comprehensive_level(config)
	value["reward_settlement"] = settlement.to_dictionary()
	value["base_experience"] = amount
	value["granted_experience"] = settlement.final_amount
	value["previous_comprehensive_level"] = previous_level
	value["comprehensive_level"] = level
	value["comprehensive_level_changed"] = level != previous_level
	return DomainResult.ok(value)
