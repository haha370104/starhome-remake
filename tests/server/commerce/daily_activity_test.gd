extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var failures: Array[String] = []
var checks := 0
var service := AuthoritativeCommerceService.new()
var items := ItemCatalog.new()
var state: PlayerStateRecord
var now := int(Time.get_unix_time_from_datetime_string("2026-09-15T04:00:00"))


## 验证真实交易服务中的任务可达性、原子奖励、重放、跨日与存档往返。
func _initialize() -> void:
	var fixture := Fixture.new()
	_expect(fixture.initialize().is_ok and items.initialize().is_ok and service.initialize().is_ok, "服务初始化")
	service.daily.clock = func() -> int: return now
	state = fixture._state.duplicate_record()
	var legacy := state.to_dictionary()
	legacy.erase("daily_activities")
	_expect(PlayerStateRecord.from_dictionary(legacy).is_ok, "旧存档缺日常字段兼容")
	legacy.daily_activities = {"accepted_today": -1}
	_expect(not PlayerStateRecord.from_dictionary(legacy).is_ok, "坏计数被拒")
	var original := state.to_dictionary()
	var query := service.execute(state, {"type": "query_daily_activities", "day": "1900-01-01"})
	_expect(query.is_ok and query.value.changed and state.to_dictionary() == original, "首次查询生成候选而不修改原存档")
	state = query.value.candidate
	_expect(state.daily_activities.day == "2026-09-15", "客户端日期不参与换日")
	_expect(not service.execute(state, {"type": "query_daily_activities"}).value.changed, "同日重复查询不刷新或写入")
	var catalog := service.daily.catalog
	var bands: Dictionary = {}
	for task: MercenaryDefinition in catalog.tasks.values():
		_expect(task.kind in [1, 2] and not task.target_id.is_empty(), "只发布已接入目标")
		_expect(task.reward == 10 + task.grade * 5, "八档奖励从15至50")
		bands[task.grade] = true
	_expect(bands.size() == 8, "八档均有可完成任务")
	print("DAILY_CATALOG available=%d grades=%d" % [catalog.tasks.size(), bands.size()])
	_expect(catalog.tasks.has("2"), "低级类胶使用实际掉落 ID")
	state.daily_activities.offers = ["2", "3", "4"]
	var accepted := _command("accept_mercenary", {"task_id": "2", "reward": 9999})
	_expect(accepted.is_ok and state.daily_activities.active.size() == 1, "接取白名单任务")
	var ticket := String(accepted.value.operation.ticket)
	var balance := state.amethyst
	_expect(not _command("complete_mercenary", {"ticket": ticket}).is_ok and state.amethyst == balance, "材料不足不发奖励")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(state).value
	var task: MercenaryDefinition = catalog.tasks["2"]
	player.inventory.restore_items([])
	var material: GameItem = items.create(task.target_id, {"instance_id": "daily-material", "quantity": task.quantity}).value
	var locked: GameItem = items.create(task.target_id, {"instance_id": "daily-locked", "quantity": 5, "locked": true}).value
	_expect(player.receive_loot(locked).is_ok, "锁定材料加入背包夹具")
	_expect(player.receive_loot(material).is_ok, "领取前后已有材料均可交付")
	state = mapper.to_record(player).value
	var command := {"type": "complete_mercenary", "ticket": ticket, "daily_revision": state.daily_activities.revision,
		"inventory_revision": state.inventory_revision, "reward": 9999, "amethyst": 99999}
	var completed := service.execute(state, command)
	_expect(completed.is_ok and completed.value.candidate.amethyst == balance + 15, "交付仅发服务端15紫晶")
	_expect(state.amethyst == balance, "候选提交前余额不变")
	state = completed.value.candidate
	_expect(not service.execute(state, command).is_ok and state.amethyst == balance + 15, "重放不重复入账")
	player = mapper.to_domain(state).value
	_expect(player.inventory.find("daily-locked").quantity == 5, "锁定材料不被消费")
	_expect(player.inventory.count_consumable_definition(task.target_id) == 0, "只消费非锁定材料")
	_expect(not player.inventory.consume_definition(task.target_id, 1).is_ok and player.inventory.find("daily-locked").quantity == 5, "只有锁定材料时拒绝且不修改背包")
	var kill: MercenaryDefinition
	for candidate: MercenaryDefinition in catalog.tasks.values():
		if candidate.kind == 1 and candidate.grade == 1:
			kill = candidate
			break
	_expect(kill != null, "新兵有真实击杀任务")
	state.daily_activities.offers = [kill.id]
	accepted = _command("accept_mercenary", {"task_id": kill.id})
	ticket = String(accepted.value.operation.ticket)
	var event := {"killer_id": state.character_id, "species_id": kill.target_id, "death_id": "daily.death.1"}
	var wrong := event.duplicate()
	wrong.killer_id = "other-player"
	_expect(not service.record_monster_kill(state, wrong).value.changed, "拒绝他人击杀")
	var death := service.record_monster_kill(state, event)
	_expect(death.is_ok and death.value.changed, "可信击杀推进任务")
	state = death.value.candidate
	_expect(not service.record_monster_kill(state, event).value.changed, "重复死亡事件不推进")
	now += 86400
	_command("query_daily_activities", {})
	_expect(state.daily_activities.active.has(ticket) and state.daily_activities.accepted_today == 0, "换日保留昨日任务并重置领取计数")
	_expect(not service.record_monster_kill(state, event).value.changed, "跨日仍去重旧死亡")
	for index in range(1, kill.quantity):
		event.death_id = "daily.death.%d" % (index + 1)
		state = service.record_monster_kill(state, event).value.candidate
	_expect(_command("complete_mercenary", {"ticket": ticket}).is_ok and state.daily_activities.completed_today == 1, "昨日领取任务计入今日交付")
	state.daily_activities.accepted_today = 20
	state.daily_activities.offers = ["2"]
	_expect(_command("accept_mercenary", {"task_id": "2"}).error_code == &"daily.limit", "每日20次上限")
	state.daily_activities.accepted_today = 0
	state.daily_activities.active = {}
	for index in range(5):
		state.daily_activities.active[str(index)] = {"id": "2", "progress": 0}
	_expect(_command("accept_mercenary", {"task_id": "2"}).error_code == &"daily.limit", "同时最多5个")
	var before_count: int = state.daily_activities.accepted_today
	_expect(_command("abandon_mercenary", {"ticket": "0"}).is_ok and state.daily_activities.accepted_today == before_count, "放弃不退领取次数")
	# 用临近里程碑的合法存档夹具验证第10次交付到历练领奖的完整事务。
	state.daily_activities.active = {"milestone": {"id": kill.id, "progress": kill.quantity}}
	state.daily_activities.completed_today = 9
	_expect(_command("complete_mercenary", {"ticket": "milestone"}).is_ok, "第10次交付")
	balance = state.amethyst
	_expect(_command("claim_experience", {"task_id": "8"}).is_ok and state.amethyst == balance + 20, "历练里程碑发20紫晶")
	_expect(not _command("claim_experience", {"task_id": "8"}).is_ok, "同日历练不能重复领奖")
	_expect(not _command("claim_experience", {"task_id": "9"}).is_ok, "未实现战场不能伪造领奖")
	_expect(PlayerStateRecord.from_dictionary(state.to_dictionary()).value.daily_activities == state.daily_activities, "含收据和领取状态的存档往返")
	for failure: String in failures:
		push_error(failure)
	print("DAILY_ACTIVITIES checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 模拟仓储接受成功候选，失败时保留原记录。
## [param action] 任务命令。
## [param fields] 任务身份参数。
## 返回服务执行结果。
func _command(action: String, fields: Dictionary) -> DomainResult:
	fields.merge({"type": action, "daily_revision": state.daily_activities.revision, "inventory_revision": state.inventory_revision})
	var result := service.execute(state, fields)
	if result.is_ok and result.value.changed:
		state = result.value.candidate
	return result


## 记录行为断言，失败时保留完整说明。
## [param condition] 待验证行为。
## [param message] 失败定位信息。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
