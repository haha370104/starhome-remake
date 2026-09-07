class_name RepeatableTrainingTask
extends RefCounted

var _definition: Dictionary
var _policy: Dictionary
var _targets: Array[Dictionary]


## 训练规则仅消费配置、权威日期和随机种子，不读取时钟或网络。
func _init(definition: Dictionary, policy: Dictionary, targets: Array[Dictionary]) -> void:
	_definition = definition.duplicate(true)
	_policy = policy.duplicate(true)
	_targets = targets.duplicate(true)


## 使用左闭合累计上界：≤50、51–100……501以上；不会重复命中边界。
func eligible_targets(skill_level: int) -> Array[Dictionary]:
	var tiers: Array = []
	for band: Dictionary in _policy.get("level_bands", []):
		if skill_level <= int(band["maximum_level"]):
			for tier: Variant in band["tiers"]:
				tiers.append(int(tier))
			break
	var result: Array[Dictionary] = []
	for target: Dictionary in _targets:
		if int(target["tier"]) in tiers:
			result.append(target.duplicate(true))
	return result


## 接取时冻结目标，跨天只重置接取次数，未完成任务和击杀进度保留。
func accept(state: Dictionary, skill_level: int, day: String, random_seed: int) -> DomainResult:
	if bool(state.get("accepted", false)):
		return DomainResult.failure(&"quest.already_accepted", "此项训练尚未完成")
	var accepted_today := daily_accepted(state, day)
	if accepted_today >= int(_definition["daily_accept_limit"]):
		return DomainResult.failure(&"quest.daily_limit", "今日该项训练已接取%d次，请明天再来" % int(_definition["daily_accept_limit"]))
	var targets := eligible_targets(skill_level)
	if targets.is_empty():
		return DomainResult.failure(&"quest.no_targets", "该等级尚无可用训练怪物")
	var random := RandomNumberGenerator.new()
	random.seed = random_seed
	var selected: Dictionary = targets[random.randi_range(0, targets.size() - 1)]
	var result := state.duplicate(true)
	result.merge({
		"accepted": true, "accept_day": day, "daily_accepted": accepted_today + 1,
		"completions": int(state.get("completions", 0)),
		"target": selected, "kills": 0, "accepted_skill_level": skill_level,
	}, true)
	return DomainResult.ok(result)


## 返回指定服务器日期已经接取的次数，不依赖客户端时钟。
func daily_accepted(state: Dictionary, day: String) -> int:
	return int(state.get("daily_accepted", 0)) if String(state.get("accept_day", "")) == day else 0


## 只消费匹配物种的击杀；同一死亡标识最多一次，进度不超过目标数量。
func record_kill(state: Dictionary, species_id: String, death_id: String) -> Dictionary:
	if not bool(state.get("accepted", false)) or death_id.is_empty():
		return state
	if String(state.get("target", {}).get("species_id", "")) != species_id:
		return state
	var required := int(_definition["kill_count"])
	if int(state.get("kills", 0)) >= required:
		return state
	var seen: Array = state.get("seen_deaths", [])
	if death_id in seen:
		return state
	var result := state.duplicate(true)
	seen = seen.duplicate()
	seen.append(death_id)
	if seen.size() > 64:
		seen.pop_front()
	result["seen_deaths"] = seen
	result["kills"] = int(state.get("kills", 0)) + 1
	return result


## 验证击杀完成，仅返回新状态，技能奖励由玩家聚合结算。
func turn_in(state: Dictionary) -> DomainResult:
	if not bool(state.get("accepted", false)):
		return DomainResult.failure(&"quest.not_accepted", "请先接取训练任务")
	if int(state.get("kills", 0)) < int(_definition["kill_count"]):
		return DomainResult.failure(&"quest.requirements_missing", "训练目标尚未完成")
	var result := state.duplicate(true)
	result["accepted"] = false
	result["completions"] = int(state.get("completions", 0)) + 1
	return DomainResult.ok(result)


## 统一为收集任务兼容的只读进度 DTO，额外携带每日接取次数与技能奖励。
func snapshot(state: Dictionary, day: String) -> Dictionary:
	var accepted := bool(state.get("accepted", false))
	var count := daily_accepted(state, day)
	var required := int(_definition["kill_count"])
	var killed := mini(required, int(state.get("kills", 0)))
	var target: Dictionary = state.get("target", {})
	return {
		"task_id": _definition["id"], "title": _definition["title"], "kind": "kill_training",
		"provider_id": _definition["provider_id"], "accepted": accepted,
		"completions": int(state.get("completions", 0)), "maximum_completions": 0,
		"daily_accepted": count, "daily_accept_limit": _definition["daily_accept_limit"],
		"exhausted": not accepted and count >= int(_definition["daily_accept_limit"]),
		"ready_to_turn_in": accepted and killed >= required,
		"requirements": [{"display_name": target.get("display_name", "接取后指定目标怪物"),
			"owned": killed if accepted else 0, "required": required, "complete": accepted and killed >= required}],
		"currency_reward": 0, "skill_id": _definition["skill_id"],
		"skill_level_reward": _definition["skill_level_reward"],
		"dialogue": _definition["dialogue"].duplicate(true), "target": target.duplicate(true),
	}
