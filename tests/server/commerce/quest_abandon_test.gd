extends SceneTree

var failures: Array[String] = []
var checks := 0


## 验证放弃任务保留每日额度、历史奖励及跨地图权威限制。
func _initialize() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "初始化玩家")
	var service := AuthoritativeCommerceService.new()
	_expect(service.initialize().is_ok, "初始化服务")
	var state := fixture._state.duplicate_record()
	state.map_id = "outside_task_provider"
	var day := service.quests.current_day()
	state.quest_states["training_energy_cannon"] = {"accepted": true, "completions": 9,
		"daily_accepted": 10, "accept_day": day, "kills": 20,
		"target": {"species_id": "old_target"}, "seen_deaths": ["old_death"]}
	var command := {"type": "abandon_weapon_merchant_task", "merchant_id": "combat_trainer",
		"task_id": "training_energy_cannon"}
	var result := service.execute(state, command)
	_expect(result.is_ok, "野外也可放弃")
	if result.is_ok:
		var candidate: PlayerStateRecord = result.value["candidate"]
		var progress: Dictionary = candidate.quest_states["training_energy_cannon"]
		_expect(not progress["accepted"] and progress["completions"] == 9, "保留完成次数")
		_expect(progress["daily_accepted"] == 10 and progress["accept_day"] == day, "保留当日接取额度")
		_expect(not progress.has("target") and not progress.has("seen_deaths"), "清除旧目标与本轮去重")
		_expect(state.quest_states["training_energy_cannon"]["accepted"], "失败前未修改原记录")
		_expect(not service.execute(candidate, command).is_ok, "重复放弃被拒绝")
		candidate.map_id = "yian_harbor_hall_floor_1"
		var accept := command.duplicate()
		accept["type"] = "accept_weapon_merchant_task"
		_expect(not service.execute(candidate, accept).is_ok, "放弃不退还当天第十次额度")
		var rule: RepeatableTrainingTask = service.quests.catalog.training_rule(service.quests.catalog.definitions["training_energy_cannon"])
		_expect(rule.accept(progress, 1, "2099-01-02", 1).is_ok, "次日可正常接取")
	var collection := RepeatableCollectionTask.new({"maximum_completions": 60})
	var abandoned := collection.abandon({"accepted": true, "completions": 59})
	_expect(abandoned.is_ok and abandoned.value["completions"] == 59, "放弃收集不重置里程碑")
	_expect(collection.accept(abandoned.value).value["completions"] == 59, "重新接取沿用轮次")
	for failure in failures:
		push_error(failure)
	print("QUEST_ABANDON: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 累积断言以报告多个独立的状态问题。
## [param condition] 预期条件。[param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
