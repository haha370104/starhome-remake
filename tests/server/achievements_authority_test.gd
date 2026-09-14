extends SceneTree

var failures: Array[String] = []
var checks := 0


## 验证成就事实只由权威结算进入聚合，并与奖励候选事务共同保存。
func _initialize() -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "玩家服务初始化")
	var service := AuthoritativeCommerceService.new()
	_expect(service.initialize().is_ok, "商店任务服务初始化")
	var state: PlayerStateRecord = fixture._state.duplicate_record()
	var original := state.to_dictionary()
	var event := {"killer_id": state.character_id, "species_id": "toxic_gel", "death_id": "death.0"}
	var wrong := event.duplicate()
	wrong.killer_id = "other.player"
	_expect(not service.record_monster_kill(state, wrong).value.changed, "他人的击杀不计入当前玩家")
	for index in range(10):
		event.death_id = "death.%d" % index
		var result := service.record_monster_kill(state, event)
		_expect(result.is_ok and result.value.changed, "没有接任务也能获得击杀成就")
		state = result.value.candidate
		_expect(not service.record_monster_kill(state, event).value.changed, "重复死亡事件不修改候选")
	_expect(PlayerAchievements.new(state.achievements).total_points() == 5, "十次权威击杀获得五点")
	_expect(fixture._state.to_dictionary() == original, "候选操作不提前修改仓储原记录")
	var restored: PlayerStateRecord = PlayerStateRecord.from_dictionary(state.to_dictionary()).value
	_expect(not service.record_monster_kill(restored, event).value.changed, "存档往返后去重仍有效")
	_expect(not fixture._service.execute(state, {"type": "record_achievement", "points": 99999}).is_ok, "客户端无成就写命令")
	var queried := fixture._service.execute(state, {"type": "query", "achievements": {"points": 99999}})
	_expect(not queried.value.changed and queried.value.panel_bundle.achievements.points == 5, "查询中的伪造积分被忽略")
	var loot := {"loot_id": "mining.cycle.1", "item_definition_id": "iron_ore", "quantity": 10}
	var fact := AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED, "iron_ore", 10, "mining.cycle.1")
	var ordinary := fixture._service.grant_loot(state, loot)
	_expect(ordinary.is_ok and ordinary.value.panel_bundle.achievements.points == 5, "拾取矿物不冒充挖矿成就")
	var mined := fixture._service.grant_loot(state, loot, fact)
	_expect(mined.is_ok and mined.value.panel_bundle.achievements.points == 10, "挖矿入包候选内同时结算成就")
	_expect(mined.value.title_changed, "采矿跨越积分门槛触发称号更新")
	_expect(PlayerAchievements.new(state.achievements).total_points() == 5, "入包候选未提交时原成就不改变")
	var full := state.duplicate_record()
	full.inventory_capacity = full.inventory_stacks.size()
	var refused := fixture._service.grant_loot(full, loot, fact)
	_expect(not refused.is_ok and PlayerAchievements.new(full.achievements).total_points() == 5, "背包满时采矿和成就同时失败")
	var mismatched := fixture._service.grant_loot(state, loot,
		AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED, "iron_ore", 1000, "mining.cycle.1"))
	_expect(not mismatched.is_ok, "成就事实必须与入包数量一致")
	_test_quests(fixture, service)
	for failure in failures:
		push_error(failure)
	print("ACHIEVEMENTS_AUTHORITY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 验证材料交付与训练交付均在成功后记一次，失败和重复领奖不加点。
## [param fixture] 隔离的玩家服务夹具。
## [param service] 已初始化的权威商店服务。
func _test_quests(fixture: PlayerPanelServiceFixture, service: AuthoritativeCommerceService) -> void:
	var state := fixture._state.duplicate_record()
	state.map_id = "glory_nft_bl_weaponshop1"
	var accept := {"type": "accept_weapon_merchant_task", "merchant_id": "weapon_merchant", "task_id": "arms_npc_supply"}
	var accepted := service.execute(state, accept)
	_expect(accepted.is_ok, "材料任务接取")
	state = accepted.value.candidate
	_expect(PlayerAchievements.new(state.achievements).total_points() == 0, "接任务不算完成")
	var turn_in := {"type": "turn_in_weapon_merchant_task", "merchant_id": "weapon_merchant", "task_id": "arms_npc_supply", "inventory_revision": state.inventory_revision}
	_expect(not service.execute(state, turn_in).is_ok, "材料不足不能获得任务成就")
	for id: String in ["low_grade_gel", "low_grade_energy_catalyst", "low_grade_biosilicon"]:
		var granted := fixture._service.grant_loot(state, {"loot_id": "material." + id, "item_definition_id": id, "quantity": 20})
		_expect(granted.is_ok, "准备材料")
		state = granted.value.candidate
	turn_in.inventory_revision = state.inventory_revision
	var completed := service.execute(state, turn_in)
	_expect(completed.is_ok and completed.value.panel_bundle.achievements.points == 5, "交付材料任务后自动计入五点")
	state = completed.value.candidate
	turn_in.inventory_revision = state.inventory_revision
	_expect(not service.execute(state, turn_in).is_ok, "重复交付不能刷成就")
	state.map_id = "yian_harbor_hall_floor_1"
	accept.merchant_id = "combat_trainer"
	accept.task_id = "training_energy_cannon"
	accepted = service.execute(state, accept)
	_expect(accepted.is_ok, "接取训练任务")
	state = accepted.value.candidate
	var target := String(state.quest_states["training_energy_cannon"]["target"]["species_id"])
	for index in range(20):
		var killed := service.record_monster_kill(state, {"killer_id": state.character_id, "species_id": target, "death_id": "training.%d" % index})
		state = killed.value.candidate
	var before := PlayerAchievements.new(state.achievements).total_points()
	turn_in.merchant_id = "combat_trainer"
	turn_in.task_id = "training_energy_cannon"
	completed = service.execute(state, turn_in)
	_expect(completed.is_ok and completed.value.panel_bundle.achievements.points == before + 5, "训练交付独立计入任务成就")
	_expect(not service.execute(completed.value.candidate, turn_in).is_ok, "训练重复领奖被拒绝")


## 累计权威边界断言。
## [param condition] 预期成立的结算条件。
## [param message] 失败时显示的说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
