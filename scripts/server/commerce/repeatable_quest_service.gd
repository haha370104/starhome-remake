class_name RepeatableQuestService
extends RefCounted

var catalog := RepeatableQuestCatalog.new()
var _items: ItemCatalog
var _skill_config: Dictionary = {}
var clock := Callable()


## 初始化任务消费器，不在代码内指定任何 NPC 材料或奖励表。
## [param items] 权威物品目录。
## 返回任务配置加载结果。
func initialize(items: ItemCatalog) -> DomainResult:
	_items = items
	var loaded := JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json")
	if not loaded.is_ok:
		return loaded
	_skill_config = loaded.value
	return catalog.initialize(items)


## 只允许发布者操作属于自己的任务；调用方提供隔离的待提交玩家聚合。
## [param player] 隔离事务中的玩家聚合。
## [param provider_id] 当前交互发布者。
## [param command] 客户端任务选择意图。
## 返回操作结果或发布者、地图、材料等校验错误。
func execute(player: Player, provider_id: String, command: Dictionary) -> DomainResult:
	var candidates := catalog.tasks_for(provider_id)
	var task_id := String(command.get("task_id", candidates[0]["id"] if candidates.size() == 1 else ""))
	var definition: Dictionary = catalog.definitions.get(task_id, {})
	if definition.is_empty() or String(definition["provider_id"]) != provider_id:
		return DomainResult.failure(&"quest.unavailable", "此NPC不提供该任务")
	if player.map_id not in catalog.providers[provider_id].get("map_ids", []):
		return DomainResult.failure(&"quest.wrong_map", "请前往任务发布者所在地图")
	if String(definition.get("kind", "")) == "kill_training":
		return _execute_training(player, definition, command)
	var rule := RepeatableCollectionTask.new(definition)
	var state: Dictionary = player.quest_states.get(task_id, {})
	if String(command["type"]).begins_with("accept_"):
		var accepted := rule.accept(state)
		if not accepted.is_ok:
			return accepted
		player.quest_states[task_id] = accepted.value
		return DomainResult.ok({"action": "accept_task", "task_id": task_id})
	var checked := player.inventory.require_revision(int(command.get("inventory_revision", -1)))
	if not checked.is_ok:
		return checked
	var completed := rule.turn_in(player.inventory, state)
	if not completed.is_ok:
		return completed
	var result: Dictionary = completed.value
	for reward: Dictionary in result.get("milestone_rewards", []):
		var granted := _grant_item(player, reward)
		if not granted.is_ok:
			return granted
	player.inventory.currency += int(result["currency_reward"])
	player.quest_states[task_id] = result["state"]
	player.record_achievement(AchievementEvent.new(AchievementEvent.Kind.QUEST_COMPLETED,
		task_id, 1, "%s:%d" % [task_id, int(result["state"]["completions"])]))
	result["action"] = "turn_in_task"
	result["task_id"] = task_id
	return DomainResult.ok(result)


## 构建发布者所有任务的实时进度，不修改存档。
## [param player] 当前权威玩家。
## [param provider_id] 指定发布者。
## 返回该发布者全部任务的当前进度。
func snapshots(player: Player, provider_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in catalog.tasks_for(provider_id):
		result.append(catalog.snapshot(player, definition, current_day()))
	return result


## 服务器日期可注入以测试午夜，不接受命令中的日期或随机种子。
## 返回由注入时钟或系统时钟确定的业务日期。
func current_day() -> String:
	return catalog.day_key(int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system()))


## 训练交付不消耗背包；+1取交付时技能等级，而不是冻结的接取等级。
## [param player] 待提交玩家聚合。
## [param definition] 已验证的训练任务定义。
## [param command] 接取或交付意图。
## 返回冻结目标或技能奖励的实际结算结果。
func _execute_training(player: Player, definition: Dictionary, command: Dictionary) -> DomainResult:
	var task_id := String(definition["id"])
	var skill_id := String(definition["skill_id"])
	if player.skills.base_level(skill_id) >= int(_skill_config.get("maximum_level", 700)):
		return DomainResult.failure(&"quest.skill_maximum", "该技能已满级，无需继续训练")
	var rule := catalog.training_rule(definition)
	var state: Dictionary = player.quest_states.get(task_id, {})
	if String(command["type"]).begins_with("accept_"):
		var accepted := rule.accept(state, player.skills.base_level(skill_id), current_day(), randi())
		if not accepted.is_ok:
			return accepted
		player.quest_states[task_id] = accepted.value
		return DomainResult.ok({"action": "accept_task", "task_id": task_id})
	var completed := rule.turn_in(state)
	if not completed.is_ok:
		return completed
	var reward := player.grant_skill_level_reward(skill_id, _skill_config)
	if not reward.is_ok:
		return reward
	player.quest_states[task_id] = completed.value
	player.record_achievement(AchievementEvent.new(AchievementEvent.Kind.QUEST_COMPLETED,
		task_id, 1, "%s:%d" % [task_id, int(completed.value["completions"])]))
	return DomainResult.ok({"action": "turn_in_task", "task_id": task_id, "skill_level_up": reward.value,
		"currency_reward": 0, "milestone_rewards": []})


## 内部权威死亡入口；不提供对应客户端 RPC。一次击杀可推进多个匹配目标的已接任务。
## [param player] 击杀者的隔离聚合。
## [param event] 服务器生成的死亡事件。
## 返回是否至少推进了一项训练。
func record_monster_kill(player: Player, event: Dictionary) -> bool:
	if String(event.get("killer_id", "")) != player.entity_id:
		return false
	var changed := false
	for definition: Dictionary in catalog.definitions.values():
		if String(definition.get("kind", "")) != "kill_training":
			continue
		var task_id := String(definition["id"])
		var state: Dictionary = player.quest_states.get(task_id, {})
		var updated := catalog.training_rule(definition).record_kill(state,
			String(event.get("species_id", "")), String(event.get("death_id", "")))
		if updated != state:
			player.quest_states[task_id] = updated
			changed = true
	return changed


## 按物品最大堆叠数拆分奖励，实例 ID 跨进程重启保持随机唯一。
## [param player] 接收里程碑奖励的隔离聚合。
## [param reward] 已验证的定义身份和数量。
## 返回全部入包成功或容量错误，由外层事务决定提交。
func _grant_item(player: Player, reward: Dictionary) -> DomainResult:
	var remaining := int(reward["quantity"])
	while remaining > 0:
		var created := _items.create(String(reward["definition_id"]), {
			"instance_id": "quest." + Crypto.new().generate_random_bytes(16).hex_encode(), "quantity": 1,
		})
		if not created.is_ok:
			return created
		var item: GameItem = created.value
		item.quantity = mini(remaining, item.max_stack)
		var added := player.inventory.add_reward(item)
		if not added.is_ok:
			return added
		remaining -= item.quantity
	return DomainResult.ok()
