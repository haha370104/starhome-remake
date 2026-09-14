extends SceneTree

var failures: Array[String] = []
var checks := 0


## 验证成就计数、去重、存档、称号选择及真实战斗装配。
func _initialize() -> void:
	var book := PlayerAchievements.new()
	_expect(book.total_points() == 0, "新玩家从零开始")
	var first := AchievementEvent.new(AchievementEvent.Kind.MONSTER_KILLED, "toxic_gel", 10, "death.batch.1")
	_expect(book.record(first) and book.total_points() == 5, "达到击杀门槛获得一次积分")
	_expect(not book.record(first) and book.total_points() == 5, "重放事件不能重复加点")
	var restored := PlayerAchievements.new(book.to_dictionary())
	_expect(not restored.record(first), "重启后仍拒绝同一事件")
	_expect(not restored.record(AchievementEvent.new(AchievementEvent.Kind.MONSTER_KILLED, "unknown", 10, "x")), "未知目标不累计")
	_expect(not restored.record(AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED, "iron_ore", -1, "bad")), "负数无效")
	_expect(restored.record(AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED, "iron_ore", 10, "ore.1")), "采矿独立累计")
	_expect(restored.total_points() == 10 and restored.snapshot()["title_id"] == "rookie", "精确门槛自动晋升")
	_expect(restored.bonuses().energy_cannon_attack == 1 and restored.bonuses().max_health == 10, "称号增益来自配置")
	restored.record(AchievementEvent.new(AchievementEvent.Kind.MONSTER_KILLED, "toxic_gel", 1000, "death.batch.2"))
	restored.record(AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED, "iron_ore", 1000, "ore.2"))
	_expect(restored.total_points() == 100, "批量事实跨阶结算且进度封顶")
	_expect(restored.bonuses().energy_cannon_attack == 3, "只生效最高称号，不叠加低阶")
	_expect(not restored.record(AchievementEvent.new(AchievementEvent.Kind.MONSTER_KILLED, "toxic_gel", 1, "after.cap")), "满进度不扩充收据")
	var raw := restored.to_dictionary()
	raw["points"] = 999999
	raw["title_id"] = "legend"
	_expect(PlayerAchievements.new(raw).total_points() == 100, "积分称号不能由存档冗余字段伪造")
	_expect(not PlayerAchievements.valid_state({"counters": {"kill:toxic_gel": -1}}), "存档拒绝负进度")
	_expect(not PlayerAchievements.valid_state({"counters": {"kill:toxic_gel": 0.5}}), "存档拒绝小数进度")
	_expect(not restored.snapshot().has("receipts"), "网络投影不含收据")
	var config: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/achievements_v1.json").value
	config["milestones"]["kill"][0]["points"] = -1
	_expect(not AchievementCatalog.new().initialize(config).is_ok, "无效奖励配置被拒绝")
	_test_combat(restored)
	for failure in failures:
		push_error(failure)
	print("ACHIEVEMENTS_DOMAIN checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 比较加成前后的真实装配、存档和客户端投影，并验证热更新不重置战斗状态。
## [param achievements] 已晋升到开拓者的测试账本。
func _test_combat(achievements: PlayerAchievements) -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "玩家夹具初始化")
	var player: Player = fixture._service.restore_player(fixture._state).value
	var catalog: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var movement := {"base_speed_multiplier": 1500.0, "base_speed_cap": 240.0}
	var original: Dictionary = catalog.vehicle_combat_loadout(player, 20, movement).value
	player.achievements = achievements
	player.vehicle.achievement_bonuses = achievements.bonuses()
	player.vehicle.health = 40
	player.vehicle.reconcile_loadout_state(false)
	var modified: Dictionary = catalog.vehicle_combat_loadout(player, 20, movement).value
	_expect(modified.assembly.max_health == original.assembly.max_health + 30, "真实战斗生命上限增加")
	_expect(player.vehicle.health == 40, "晋升不恢复当前生命")
	for ability: String in original.weapons:
		_expect(modified.weapons[ability].minimum_damage == original.weapons[ability].minimum_damage + 3, "实际武器攻击增加 " + ability)
	_expect(modified.weapons["energy_cannon.primary"].range == original.weapons["energy_cannon.primary"].range + 10, "实际能量炮射程增加")
	_expect(modified.assembly.self_repair_bonus_strength == original.assembly.self_repair_bonus_strength + 2, "实际自维修增益")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var record: PlayerStateRecord = mapper.to_record(player).value
	var round_trip: Player = mapper.to_domain(record).value
	_expect(round_trip.vehicle.max_health == 100 and round_trip.vehicle.health == 40, "存档恢复不重复加成或缩放生命")
	var client := CurrentPlayer.new(items)
	_expect(client.apply_bundle(fixture._service.build_bundle(record)), "客户端接收完整投影")
	_expect(client.vehicle.max_health == 100 and client.achievements.total_points() == 100, "客户端面板与服务器称号一致")
	var combat := AuthoritativeCombatModule.new()
	combat.configure(20, 1)
	combat.register_vehicle("player", "field", Vector2.ZERO, original.assembly, original.weapons)
	var actor: Dictionary = combat.actors["player"]
	var state: VehicleCombatState = actor.vehicle_state
	state.health = 40
	state.working_energy = 25
	actor.cooldown_ready_ticks["energy_cannon.primary"] = 123
	actor.last_command_sequence = 77
	actor.self_repair.active = true
	actor.self_repair.next_cycle_tick = 999
	_expect(combat.refresh_achievement_loadout("player", modified).is_ok, "热更新成功")
	_expect(actor.cooldown_ready_ticks["energy_cannon.primary"] == 123 and actor.last_command_sequence == 77, "升级保留冷却和防重放序号")
	_expect(state.health == 40 and state.max_health == 100 and state.working_energy == 25, "热更新不补血或补能量")
	_expect(actor.self_repair.active and actor.self_repair.next_cycle_tick == 999, "热更新保留维修时序")
	_expect(actor.self_repair.health_per_cycle == modified.assembly.self_repair_base_strength + modified.assembly.self_repair_bonus_strength, "进行中的维修使用新加成")
	combat.advance_ticks(999, false)
	_expect(state.health > 40, "权威维修周期实际恢复生命")


## 累计领域断言并记录失败原因。
## [param condition] 预期成立的领域条件。
## [param message] 失败时的说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
