class_name RepeatableCollectionTask
extends RefCounted

var _definition: Dictionary


## 创建由配置驱动的循环收集任务规则。
## [param definition] 需求、奖励、上限和原版对话配置。
func _init(definition: Dictionary) -> void:
	_definition = definition.duplicate(true)


## 构建当前玩家可见的任务状态和材料进度。
## [param inventory] 玩家权威背包。
## [param state] 持久化任务状态。
## 返回不含领域对象引用的任务投影。
func snapshot(inventory: Inventory, state: Dictionary) -> Dictionary:
	var accepted := bool(state.get("accepted", false))
	var completions := maxi(0, int(state.get("completions", 0)))
	var requirements: Array[Dictionary] = []
	var ready := accepted
	for raw_requirement: Variant in _definition.get("requirements", []):
		var requirement: Dictionary = raw_requirement
		var owned := inventory.count_definition(String(requirement["definition_id"]))
		var quantity := int(requirement["quantity"])
		requirements.append({
			"definition_id": String(requirement["definition_id"]),
			"display_name": String(requirement["display_name"]),
			"required": quantity,
			"owned": owned,
			"complete": owned >= quantity,
		})
		ready = ready and owned >= quantity
	var maximum := int(_definition.get("maximum_completions", 0))
	return {
		"task_id": String(_definition.get("id", "")),
		"title": String(_definition.get("title", "")),
		"accepted": accepted,
		"completions": completions,
		"maximum_completions": maximum,
		"exhausted": maximum > 0 and completions >= maximum,
		"ready_to_turn_in": ready,
		"requirements": requirements,
		"currency_reward": int(_definition.get("currency_reward", 0)),
		"next_milestone_rewards": RepeatableQuestCatalog.rewards_at(_definition, (floori(float(completions) / 5.0) + 1) * 5),
		"provider_id": String(_definition.get("provider_id", "")),
		"dialogue": (_definition.get("dialogue", {}) as Dictionary).duplicate(true),
	}


## 验证任务可接受，并返回更新状态。
## [param state] 当前持久化任务状态。
## 返回更新后的任务状态或准入失败原因。
func accept(state: Dictionary) -> DomainResult:
	var completions := maxi(0, int(state.get("completions", 0)))
	var maximum := int(_definition.get("maximum_completions", 0))
	if bool(state.get("accepted", false)):
		return DomainResult.failure(&"quest.already_accepted", "task is already active")
	if maximum > 0 and completions >= maximum:
		return DomainResult.failure(&"quest.exhausted", "task completion limit has been reached")
	return DomainResult.ok({"accepted": true, "completions": completions})


## 消耗任务材料并计算本轮固定和里程碑奖励。
## [param inventory] 玩家权威背包。
## [param state] 当前持久化任务状态。
## 返回消费摘要、奖励与更新后的任务状态。
func turn_in(inventory: Inventory, state: Dictionary) -> DomainResult:
	var current := snapshot(inventory, state)
	if not bool(current["accepted"]):
		return DomainResult.failure(&"quest.not_accepted", "task is not active")
	if bool(current["exhausted"]):
		return DomainResult.failure(&"quest.exhausted", "任务完成次数已达上限")
	if not bool(current["ready_to_turn_in"]):
		return DomainResult.failure(&"quest.requirements_missing", "task materials are incomplete")
	for raw_requirement: Variant in _definition.get("requirements", []):
		var requirement: Dictionary = raw_requirement
		var consumed := inventory.consume_definition(
			String(requirement["definition_id"]), int(requirement["quantity"])
		)
		if not consumed.is_ok:
			return consumed
	var completion := int(current["completions"]) + 1
	var rewards := RepeatableQuestCatalog.rewards_at(_definition, completion)
	return DomainResult.ok({
		"state": {"accepted": false, "completions": completion},
		"currency_reward": int(_definition.get("currency_reward", 0)),
		"milestone_reward": rewards[0] if not rewards.is_empty() else {},
		"milestone_rewards": rewards,
	})
