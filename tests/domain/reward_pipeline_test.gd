extends SceneTree

var failures: Array[String] = []
var checks := 0


## 验证奖励切面的筛选、叠加、有效期、食品和拒绝非法配置。
func _initialize() -> void:
	var document := {"schema_version": 1, "rules": [
		{"id": "global", "channel": "experience", "multiplier": 1.5},
		{"id": "vip.basic", "channel": "experience", "multiplier": 2, "account_ids": ["vip"], "skill_ids": ["mining"], "stack_group": "vip", "expires_at": 200},
		{"id": "vip.plus", "channel": "experience", "multiplier": 3, "account_ids": ["vip"], "skill_ids": ["mining"], "stack_group": "vip", "starts_at": 100, "expires_at": 150},
		{"id": "item", "channel": "drop", "multiplier": 4, "account_ids": ["vip"], "item_ids": ["ore"], "species_ids": ["crawler"], "sources": ["monster_kill"]}
	]}
	var loaded := RewardPolicyLoader.from_document(document)
	_expect(loaded.is_ok, "运营规则可解析")
	var pipeline: RewardPipeline = loaded.value
	var context := RewardContext.new()
	context.account_id = "vip"
	context.skill_id = "mining"
	context.now = 100
	var result: RewardSettlement = pipeline.settle(context, 10).value
	_expect(is_equal_approx(result.final_amount, 45), "独立来源相乘、VIP组只取最高")
	_expect(result.applied.size() == 2, "结算保留来源明细")
	context.now = 150
	_expect(is_equal_approx(pipeline.settle(context, 10).value.final_amount, 30), "到期边界降为仍有效的低档VIP")
	context.now = 200
	_expect(is_equal_approx(pipeline.settle(context, 10).value.final_amount, 15), "到期VIP不生效")
	context.now = 100
	context.skill_id = "repair"
	_expect(is_equal_approx(pipeline.settle(context, 10).value.final_amount, 15), "其他技能不误用专属倍率")
	context.skill_id = "mining"
	context.account_id = "ordinary"
	_expect(is_equal_approx(pipeline.settle(context, 10).value.final_amount, 15), "账号隔离")
	context.account_id = "vip"
	context.food_status = FoodStatus.new({"active": [{"kind": 5, "amount": 20, "expires_at": 120}]})
	_expect(is_equal_approx(pipeline.settle(context, 10).value.final_amount, 54), "食品作为同一切面的独立来源叠加")
	context.now = 120
	_expect(is_equal_approx(pipeline.settle(context, 10).value.final_amount, 45), "未清理食品也不会过期继续加成")
	context.source = "monster_kill"
	context.species_id = "crawler"
	var drop_context := context.for_item("ore")
	_expect(is_equal_approx(pipeline.settle(drop_context, 0.1).value.final_amount, 0.4), "账号物品及物种同时匹配")
	_expect(is_equal_approx(pipeline.settle(context.for_item("other"), 0.1).value.final_amount, 0.1), "逐条物品筛选不泄漏")
	_expect(not pipeline.settle(context, NAN).is_ok and not pipeline.settle(context, -1).is_ok, "拒绝非法基础量")
	for rule: Dictionary in [
		{"id": "x", "channel": "drop", "multiplier": -1},
		{"id": "x", "channel": "drop", "multiplier": INF},
		{"id": "x", "channel": "drop", "multiplier": "2"},
		{"id": "x", "channel": "drop", "multiplier": 2, "account_id": "typo"},
		{"id": "x", "channel": "drop", "multiplier": 2, "account_ids": "vip"},
		{"id": "x", "channel": "drop", "multiplier": 2, "skill_ids": ["mining"]},
		{"id": "x", "channel": "drop", "multiplier": 2, "starts_at": 10, "expires_at": 5}
	]:
		_expect(not RewardPolicyLoader.from_document({"schema_version": 1, "rules": [rule]}).is_ok, "非法配置整体失败")
	var duplicate := document.duplicate(true)
	duplicate.rules.append(duplicate.rules[0])
	_expect(not RewardPolicyLoader.from_document(duplicate).is_ok, "重复规则不能翻倍")
	var zero := RewardPolicyLoader.from_document({"schema_version": 1, "rules": [{"id": "zero", "channel": "experience", "multiplier": 0}]}).value as RewardPipeline
	_expect(is_zero_approx(zero.settle(context, 10).value.final_amount), "允许显式关闭某类奖励")
	for failure: String in failures:
		push_error(failure)
	print("REWARD_PIPELINE checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 记录每个领域边界断言。
## [param condition] 不变量是否成立。
## [param message] 失败时的定位信息。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
