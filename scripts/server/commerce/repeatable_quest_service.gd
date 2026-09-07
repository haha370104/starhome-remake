class_name RepeatableQuestService
extends RefCounted

var catalog := RepeatableQuestCatalog.new()
var _items: ItemCatalog


## 初始化任务消费器，不在代码内指定任何 NPC 材料或奖励表。
func initialize(items: ItemCatalog) -> DomainResult:
	_items = items
	return catalog.initialize(items)


## 只允许发布者操作属于自己的任务；调用方提供隔离的待提交玩家聚合。
func execute(player: Player, provider_id: String, command: Dictionary) -> DomainResult:
	var candidates := catalog.tasks_for(provider_id)
	var task_id := String(command.get("task_id", candidates[0]["id"] if candidates.size() == 1 else ""))
	var definition: Dictionary = catalog.definitions.get(task_id, {})
	if definition.is_empty() or String(definition["provider_id"]) != provider_id:
		return DomainResult.failure(&"quest.unavailable", "此NPC不提供该任务")
	if player.map_id not in catalog.providers[provider_id].get("map_ids", []):
		return DomainResult.failure(&"quest.wrong_map", "请前往任务发布者所在地图")
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
	result["action"] = "turn_in_task"
	result["task_id"] = task_id
	return DomainResult.ok(result)


## 构建发布者所有任务的实时进度，不修改存档。
func snapshots(player: Player, provider_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in catalog.tasks_for(provider_id):
		result.append(RepeatableCollectionTask.new(definition).snapshot(
			player.inventory, player.quest_states.get(String(definition["id"]), {})
		))
	return result


## 按物品最大堆叠数拆分奖励，实例 ID 跨进程重启保持随机唯一。
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
