extends SceneTree

var checks := 0
var failures: Array[String] = []


## 遍历全部轮次验证奖励、上限、NPC隔离和旧存档续接。
func _initialize() -> void:
	var items := ItemCatalog.new()
	_expect(items.initialize().is_ok, "物品目录加载")
	var service := RepeatableQuestService.new()
	var loaded := service.initialize(items)
	_expect(loaded.is_ok, "循环任务配置加载：" + loaded.error_message)
	for task: Dictionary in service.catalog.definitions.values():
		if String(task.get("kind", "")) != "collection":
			continue
		var provider := String(task["provider_id"])
		var player := Player.new({"map_id": service.catalog.providers[provider]["map_ids"][0], "inventory_capacity": 200})
		for round_number in range(1, int(task["maximum_completions"]) + 1):
			var accepted := service.execute(player, provider, {"type": "accept_weapon_merchant_task", "task_id": task["id"]})
			_expect(accepted.is_ok, "%s 第%d次接取" % [provider, round_number])
			_expect(not service.execute(player, provider, {"type": "accept_weapon_merchant_task"}).is_ok, "不能重复接取")
			for requirement: Dictionary in task["requirements"]:
				_expect(service._grant_item(player, requirement).is_ok, "加入材料（按堆叠上限拆分）")
			var before := player.inventory.currency
			var result := service.execute(player, provider, {"type": "turn_in_weapon_merchant_task", "inventory_revision": player.inventory.revision})
			_expect(result.is_ok, "%s 第%d次交付" % [provider, round_number])
			if not result.is_ok:
				push_error(result.error_message)
				break
			_expect(player.inventory.currency - before == int(task["currency_reward"]), "金币准确")
			_expect(result.value["milestone_rewards"] == RepeatableQuestCatalog.rewards_at(task, round_number), "多物品里程碑准确")
		_expect(not service.execute(player, provider, {"type": "accept_weapon_merchant_task"}).is_ok, "次数上限生效")
	var legacy := Player.new({"map_id": "glory_nft_bl_weaponshop1", "quest_states": {"arms_npc_supply": {"accepted": false, "completions": 30}}})
	_expect(service.execute(legacy, "weapon_merchant", {"type": "accept_weapon_merchant_task"}).is_ok, "原30次存档可继续第31轮")
	_expect(not service.execute(legacy, "weapon_merchant", {"type": "accept_weapon_merchant_task", "task_id": "ore_npc_supply"}).is_ok, "不能跨NPC伪造任务")
	_expect(not service.execute(legacy, "ore_merchant", {"type": "accept_weapon_merchant_task"}).is_ok, "不能跨地图接取")
	for failure in failures:
		push_error(failure)
	print("REPEATABLE_COLLECTION_TASKS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
