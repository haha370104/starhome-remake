extends SceneTree

var checks := 0
var failures: Array[String] = []
var _now := 1788710400


func _initialize() -> void:
	var items := ItemCatalog.new()
	_expect(items.initialize().is_ok, "物品加载")
	var service := RepeatableQuestService.new()
	var initialized := service.initialize(items)
	_expect(initialized.is_ok, "训练配置：" + initialized.error_message)
	if not initialized.is_ok:
		quit(1)
		return
	service.clock = func() -> int: return _now
	_expect(service.catalog.tasks_for("combat_trainer").size() == 5, "五种训练")
	var definition: Dictionary = service.catalog.definitions["training_energy_cannon"]
	var rule := service.catalog.training_rule(definition)
	var boundaries := {0: [1, 2], 50: [1, 2], 51: [2, 4], 100: [2, 4],
		101: [3, 5], 150: [3, 5], 151: [4, 6], 200: [4, 6], 201: [5, 7],
		300: [5, 7], 301: [6, 8], 400: [6, 8], 401: [7, 9], 500: [7, 9], 501: [10, 10], 699: [10, 10]}
	for level: int in boundaries:
		var candidates := rule.eligible_targets(level)
		_expect(not candidates.is_empty(), "边界有候选%d" % level)
		for target: Dictionary in candidates:
			_expect(int(target["tier"]) >= boundaries[level][0] and int(target["tier"]) <= boundaries[level][1], "等级分段正确")
			_expect(not target["map_ids"].is_empty(), "目标有实际刷怪地图")
	var midnight := int(Time.get_unix_time_from_datetime_string("2026-09-08T00:00:00")) - 28800
	_expect(service.catalog.day_key(midnight - 1) == "2026-09-07" and service.catalog.day_key(midnight) == "2026-09-08", "北京时间零点换日")
	var player := Player.new({"character_id": "trainee", "map_id": "yian_harbor_hall_floor_1",
		"skills": {"energy_cannon": {"level": 20, "current_exp": 3, "fractional_exp": 0.5}}})
	for task: Dictionary in service.catalog.tasks_for("combat_trainer"):
		var task_id := String(task["id"])
		var skill_id := String(task["skill_id"])
		var initial_level := player.skills.base_level(skill_id)
		for round_number in range(10):
			var accepted := service.execute(player, "combat_trainer", {"type": "accept_weapon_merchant_task", "task_id": task_id, "skill_level": 999, "day": "2099-01-01"})
			_expect(accepted.is_ok, "第%d轮接取%s" % [round_number, task_id])
			_expect(not service.execute(player, "combat_trainer", {"type": "accept_weapon_merchant_task", "task_id": task_id}).is_ok, "同类不能重复接取")
			var state: Dictionary = player.quest_states[task_id]
			var target := String(state["target"]["species_id"])
			_expect(int(state["target"]["tier"]) <= 2, "客户端等级不能影响选怪")
			_expect(not service.record_monster_kill(player, {"killer_id": "other", "species_id": target, "death_id": "bad"}), "别人的击杀不计数")
			_expect(not service.record_monster_kill(player, {"killer_id": "trainee", "species_id": "wrong", "death_id": "bad"}), "非目标不计数")
			_expect(not service.execute(player, "combat_trainer", {"type": "turn_in_weapon_merchant_task", "task_id": task_id}).is_ok, "未击杀20不能领奖")
			for number in range(20):
				var event := {"killer_id": "trainee", "species_id": target, "death_id": "%s.%d.%d" % [task_id, round_number, number]}
				_expect(service.record_monster_kill(player, event), "有效击杀增加进度")
				_expect(not service.record_monster_kill(player, event), "同一死亡重复到达不加进度")
			var result := service.execute(player, "combat_trainer", {"type": "turn_in_weapon_merchant_task", "task_id": task_id})
			_expect(result.is_ok, "击杀20后领奖")
			_expect(player.skills.base_level(skill_id) == initial_level + round_number + 1, "每次只升一级")
			_expect(player.skills.current_experience(skill_id) == 0, "升级经验清零")
			_expect(not service.execute(player, "combat_trainer", {"type": "turn_in_weapon_merchant_task", "task_id": task_id}).is_ok, "重复领奖拒绝")
		_expect(not service.execute(player, "combat_trainer", {"type": "accept_weapon_merchant_task", "task_id": task_id}).is_ok, "当日第11次拒绝")
	_now += 86400
	var command := {"type": "accept_weapon_merchant_task", "task_id": "training_energy_cannon"}
	_expect(service.execute(player, "combat_trainer", command).is_ok, "第二天恢复次数")
	var target_before: Dictionary = player.quest_states["training_energy_cannon"]["target"].duplicate(true)
	_now += 86400
	_expect(not service.execute(player, "combat_trainer", command).is_ok, "跨天仍不能重抽已接任务")
	_expect(player.quest_states["training_energy_cannon"]["target"] == target_before, "跨天目标不变")
	_expect(rule.snapshot(player.quest_states["training_energy_cannon"], service.current_day())["daily_accepted"] == 0, "跨天重置接取计数")
	_test_persistence_and_authority()
	for failure in failures:
		push_error(failure)
	print("TRAINING_TASKS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 经真实存档映射验证目标、进度、日额度和升级原子结算。
func _test_persistence_and_authority() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "存档夹具初始化")
	var commerce := AuthoritativeCommerceService.new()
	_expect(commerce.initialize().is_ok, "服务初始化")
	var state := fixture._state.duplicate_record()
	state.map_id = "yian_harbor_hall_floor_1"
	var accepted := commerce.execute(state, {"type": "accept_weapon_merchant_task", "merchant_id": "combat_trainer", "task_id": "training_energy_cannon"})
	_expect(accepted.is_ok, "服务端接取：" + accepted.error_message)
	if not accepted.is_ok:
		return
	state = accepted.value["candidate"]
	var round_trip := PlayerStateRecord.from_dictionary(state.to_dictionary())
	_expect(round_trip.is_ok and round_trip.value.quest_states == state.quest_states, "重登目标和日次数保留")
	state = round_trip.value
	var target := String(state.quest_states["training_energy_cannon"]["target"]["species_id"])
	for number in range(20):
		var killed := commerce.record_monster_kill(state, {"killer_id": state.character_id, "species_id": target, "death_id": "persistence.%d" % number})
		_expect(killed.is_ok and killed.value["changed"], "存档击杀计数")
		state = killed.value["candidate"]
	var ready := commerce.execute(state, {"type": "query_weapon_merchant", "merchant_id": "combat_trainer"})
	_expect(ready.is_ok and ready.value["panel_bundle"]["commerce"]["tasks"][0]["ready_to_turn_in"], "客户端得到可交付状态")
	var turn_in := commerce.execute(state, {"type": "turn_in_weapon_merchant_task", "merchant_id": "combat_trainer", "task_id": "training_energy_cannon"})
	_expect(turn_in.is_ok and turn_in.value["operation"].has("skill_level_up"), "奖励携带系统升级事件")
	_expect(bool(state.quest_states["training_energy_cannon"]["accepted"]), "结算不原地污染旧存档")
	var full := Player.new({"map_id": "yian_harbor_hall_floor_1", "skills": {"energy_cannon": 700}})
	_expect(not commerce.quests.execute(full, "combat_trainer", {"type": "accept_weapon_merchant_task", "task_id": "training_energy_cannon"}).is_ok, "满级不接训练")


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
