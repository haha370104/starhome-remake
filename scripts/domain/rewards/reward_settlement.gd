class_name RewardSettlement
extends RefCounted

var base_amount := 0.0
var multiplier := 1.0
var final_amount := 0.0
var applied: Array[RewardModifier] = []


## 导出本次倍率来源，供日志和事务结果解释收益。
## 返回基础值、最终值及实际采用的规则，不包含未匹配的账号配置。
func to_dictionary() -> Dictionary:
	var rules: Array[Dictionary] = []
	for rule: RewardModifier in applied:
		rules.append({"id": rule.id, "multiplier": rule.multiplier, "stack_group": rule.stack_group})
	return {"base_amount": base_amount, "multiplier": multiplier, "final_amount": final_amount, "applied": rules}
