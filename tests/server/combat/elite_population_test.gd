extends SceneTree

var failures: Array[String] = []
var checks := 0


## 挂载正式内容后验证精英计时、真实投放、掉落和动画资源。
func _initialize() -> void:
	call_deferred("_run")


## 对全部十级区域建立真实种群，再抽样验证击杀和跨休眠补充。
func _run() -> void:
	_expect(RuntimeContentBootstrap.mount_default().ok, "正式内容包挂载")
	_test_clock()
	var loaded := CombatDefinitionCatalog.load_default()
	_expect(loaded.is_ok, "完整战斗目录有效")
	if not loaded.is_ok:
		_finish()
		return
	var catalog: CombatDefinitionCatalog = loaded.value
	var directory: Dictionary = JsonConfigLoader.load_dictionary("res://data/maps/glory_map_directory_v1.json").value
	var total_maps := 0
	for map_id: String in catalog.monster_encounter_map_ids():
		var policy := catalog.monster_population_policy_for_map(map_id, &"elite")
		if policy.is_empty():
			_expect(catalog.monster_replenishment_for_map(map_id, "test", {}, 0, 30, &"elite").value.is_empty(), "非十级区域不生成精英")
			continue
		total_maps += 1
		var instance := AuthoritativeMapInstance.new()
		_expect(instance.load_map(directory.definitions[map_id]).ok, "精英区域加载真实导航")
		_expect(instance.configure_combat(catalog, 20).ok, "精英区域初始化")
		_expect(_count(instance, &"ordinary") == 200, "普通怪独立200名额")
		_expect(_count(instance, &"elite") == 30, "每图实际初始化30只精英")
		var species := {}
		for monster: MonsterLifecycle in instance.combat_module.monsters.values():
			_expect(instance.navigation.is_walkable(monster.position), "出生点均可行走")
			if monster.population_kind == &"elite":
				species[monster.species_id] = true
				_expect(monster.drop_table.is_configured(), "精英具备实际掉落")
		_expect(species.size() == 20, "20种精英共用每图30名额")
		if total_maps == 1:
			_test_refresh(instance)
	_expect(total_maps == 24, "仅24张十级区域有精英")
	_test_loot(catalog)
	_test_assets(catalog)
	_finish()


## 验证周期边界、重复调用及休眠不累计批次。
func _test_clock() -> void:
	var quota := TimedPopulationQuota.new()
	_expect(not quota.configure({"maximum_population": 30, "replenish_interval_seconds": 0}, 20).is_ok, "拒绝零周期")
	_expect(quota.configure({"maximum_population": 30, "replenish_interval_seconds": 600}, 20).is_ok, "接受十分钟补足策略")
	_expect(quota.take_due_replenishment(0, 0) == 30, "首次补足30")
	_expect(quota.take_due_replenishment(0, 0) == 0, "同刻不重复")
	_expect(quota.take_due_replenishment(11999, 0) == 0, "600秒前不刷")
	_expect(quota.take_due_replenishment(12000, 7) == 23, "边界只补缺口")
	_expect(quota.take_due_replenishment(12000001, 28) == 2, "跳过千轮休眠仍只补两只")
	_expect(quota.next_refresh_tick == 12012000, "休眠保持原有计时相位")
	_expect(quota.take_due_replenishment(12012000, 35) == 0, "已达上限不增加")


## 验证真实精英死亡不会被普通补怪或原地复活提前补上。
## [param instance] 已初始化230只怪物的真实地图实例。
func _test_refresh(instance: AuthoritativeMapInstance) -> void:
	var survivor: MonsterLifecycle
	var killed: Array[String] = []
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		if monster.population_kind != &"elite":
			continue
		if killed.size() < 8:
			monster.apply_damage(monster.max_health, "test.player", 0)
			monster.advance_to_tick(11999)
			_expect(not monster.is_alive(), "精英死亡后不能单独原地复活")
			killed.append(monster.monster_id)
		else:
			survivor = monster
	survivor.apply_damage(1, "test.player", 0)
	survivor.clear_target()
	var health := survivor.health
	instance.combat_module.current_tick = 1200
	instance._replenish_monster_population_if_due()
	instance._replenish_elite_population_if_due()
	_expect(_count(instance, &"ordinary") == 200 and _count(instance, &"elite") == 22, "普通补怪不占用精英名额")
	instance.combat_module.current_tick = 11999
	instance._replenish_elite_population_if_due()
	_expect(_count(instance, &"elite") == 22, "真实地图未到600秒不能刷新")
	# 由正常地图推进跨过边界，验证服务端模拟已接入。
	instance.simulate(0.05)
	_expect(_count(instance, &"elite") == 30, "权威模拟在600秒自动补足")
	_expect(survivor.health == health, "补怪不重置存活怪血量")
	var removed := 0
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		if monster.population_kind == &"elite" and monster != survivor and removed < 5:
			monster.apply_damage(monster.max_health, "test.player", 12000)
			removed += 1
	_expect(instance.suspend_runtime(12000), "无人地图允许休眠")
	_expect(instance.resume_runtime(18000).ok, "五分钟后恢复")
	_expect(_count(instance, &"elite") == 25, "切图或短休眠不提前补足")
	_expect(instance.suspend_runtime(18000), "再次休眠")
	_expect(instance.resume_runtime(240001).ok, "长时间无人后恢复")
	_expect(_count(instance, &"elite") == 30 and _count(instance, &"ordinary") == 200, "长休眠补足但不积累历史精英批次")
	_expect(instance.combat_module.monsters.has(survivor.monster_id) and survivor.health == health, "休眠保留存活精英实体和血量")


## 按种群查询真实存活数量。
## [param instance] 当前地图实例。
## [param kind] 普通或精英种群标识。
## 返回当前存活个体数。
func _count(instance: AuthoritativeMapInstance, kind: StringName) -> int:
	var count := 0
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		if monster.population_kind == kind and monster.is_alive():
			count += 1
	return count


## 逐条验证20倍期望并用真实随机源抽样，覆盖超过100%的数量和20%的稀有物。
## [param catalog] 权威最终掉落目录。
func _test_loot(catalog: CombatDefinitionCatalog) -> void:
	var policy: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/elite_population_v1.json").value
	var mapping: Dictionary = policy.inherited_drop_sources.duplicate()
	for index in range(60, 66):
		mapping["glory_monster_%03d" % index] = "glory_monster_%03d" % (index - 6)
	var random := RandomNumberGenerator.new()
	random.seed = 20260916
	for elite: String in mapping:
		var base := {}
		for drop: Dictionary in catalog.monster_definition(mapping[elite]).drops:
			base[drop.item_definition_id] = float(drop.chance) * (drop.minimum_quantity + drop.maximum_quantity) / 2.0
		var entries: Array = catalog.monster_definition(elite).drops
		_expect(entries.size() == base.size(), "精英掉落候选与明确指定的基础来源一致")
		for drop: Dictionary in entries:
			var expected: float = float(drop.chance) * (drop.minimum_quantity + drop.maximum_quantity) / 2.0
			_expect(is_equal_approx(expected, float(base.get(drop.item_definition_id, -1)) * 20), "每条精英掉落数量期望严格为基础20倍")
			_expect(drop.item_definition_id != "item:material:9713f13ede8d", "精英不越过爬虫碎片例外")
		var table := DropTable.new(entries)
		var totals := {}
		for _sample in range(5000):
			for drop: Dictionary in table.roll(random):
				totals[drop.item_definition_id] = int(totals.get(drop.item_definition_id, 0)) + int(drop.quantity)
		for drop: Dictionary in entries:
			var expected := float(base[drop.item_definition_id]) * 20
			_expect(absf(float(totals.get(drop.item_definition_id, 0)) / 5000 - expected) < maxf(0.04, expected * 0.05), "精英真实随机抽取符合20倍期望")


## 加载32种新增怪物的真实三态贴图，避免只投放数据却缺少表现。
## [param catalog] 含原版表现引用的怪物目录。
func _test_assets(catalog: CombatDefinitionCatalog) -> void:
	var repository := AleSpriteRepository.new()
	_expect(repository.load_default(), "动画仓储初始化")
	for index: int in range(48, 66) + range(97, 111):
		var species := catalog.monster_definition("glory_monster_%03d" % index)
		var presentation: Dictionary = species.presentation
		for action: String in ["idle", "move", "attack"]:
			var animation := repository.load_animation(presentation.actions[action], presentation.preferred_prefix)
			_expect(not animation.get("frames", []).is_empty(), "%s %s 原版动画完整" % [species.display_name, action])


## 记录断言失败而继续收集其他错误。
## [param condition] 被验证的不变量。
## [param message] 失败时的诊断说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


## 汇总当前测试结果并返回正确退出码。
func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("ELITE_POPULATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
