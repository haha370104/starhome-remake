extends SceneTree

var failures: Array[String] = []
var checks := 0


## 挂载正式内容后验证新增种群、倍率、AI与掉落边界。
func _initialize() -> void:
	call_deferred("_run")


## 遍历全部地图及新增怪物，检查本体映射和权威生成结果。
func _run() -> void:
	_expect(RuntimeContentBootstrap.mount_default().ok, "正式内容包挂载")
	var loaded := CombatDefinitionCatalog.load_default()
	_expect(loaded.is_ok, "含强化怪物的目录有效")
	if not loaded.is_ok:
		failures.append(loaded.error_message)
		_finish()
		return
	var catalog: CombatDefinitionCatalog = loaded.value
	var raw: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/enhancement_monsters_v1.json").value
	var items := ItemCatalog.new()
	items.initialize()
	var seen_mutants := {}
	var seen_bosses := {}
	var boss_maps := 0
	var first_boss_map := ""
	for map_id: String in catalog.monster_encounter_map_ids():
		var ordinary := catalog.monster_replenishment_for_map(map_id, "test", {}, 0, 200).value as Array
		var parents := {}
		for row: Dictionary in ordinary:
			parents[row.species_id] = true
		for kind: StringName in [&"mutant", &"boss"]:
			var policy := catalog.monster_population_policy_for_map(map_id, kind)
			if policy.is_empty():
				continue
			var definitions := catalog.monster_replenishment_for_map(map_id, "test", {}, 200, int(policy.maximum_population), kind).value as Array
			if kind == &"boss":
				boss_maps += 1
				first_boss_map = map_id if first_boss_map.is_empty() else first_boss_map
				_expect(not catalog.monster_population_policy_for_map(map_id, &"elite").is_empty(), "BOSS地图确为既有十级区域")
				_expect(definitions.size() == 2 and int(policy.replenish_interval_seconds) == 1800, "每图两只BOSS半小时补足")
			for row: Dictionary in definitions:
				var id := String(row.species_id)
				if kind == &"mutant":
					seen_mutants[id] = true
					var parent: Dictionary = catalog.monster_definition(raw.mutant_parents[id])
					_expect(parents.has(raw.mutant_parents[id]), "变异所在地图必有对应本体")
					_expect(row.max_health == int(parent.stats.max_health) * 15 and row.base_attack == int(parent.stats.base_attack) * 3, "本体十五倍生命和三倍攻击")
					_expect(row.defense == int(parent.combat.get("runtime_defense", 0)) * 3, "本体运行防御三倍")
				else:
					seen_bosses[id] = true
				row.position = Vector2.ZERO
				var monster := MonsterLifecycle.new()
				_expect(monster.configure(row, 20).is_ok, "新增怪物领域对象有效")
				_expect(row.engagement_policy == ("unresponsive" if id == "glory_monster_070" else "retaliatory"), "只反击；福利毒胶不还击")
				monster.apply_damage(1, "player", 1)
				_expect(monster.target_actor_id == ("" if id == "glory_monster_070" else "player"), "受击后实际索敌符合规则")
	_expect(seen_mutants.size() == 27 and seen_bosses.size() == 10 and boss_maps == 24, "27变异与10BOSS全部覆盖，BOSS仅24图")
	for row: Dictionary in raw.definitions:
		var gem_expected := 0.0
		var affix_expected := 0.0
		var boss: bool = String(row.monster_id) in raw.boss_species
		for drop: Dictionary in row.drops:
			var stone: EnhancementStone = items.create(drop.item_definition_id, {}).value
			_expect(stone != null, "掉落身份可实例化")
			if stone.family == "gem":
				_expect(stone.rank >= (5 if boss else 1) and stone.rank <= (10 if boss else 7), "宝石等级严格遵守投放边界")
				gem_expected += float(drop.chance)
			else:
				_expect(stone.rank >= (3 if boss else 1) and stone.rank <= (6 if boss else 4), "前后缀品质严格遵守投放边界")
				affix_expected += float(drop.chance)
		_expect(absf(gem_expected - float(row.gem_expected)) < 0.00001 and absf(affix_expected - float(row.affix_expected)) < 0.00001, "分类掉落期望无额外精英二十倍")
	_test_refresh(catalog, first_boss_map)
	_finish()


## 在真实导航地图中验证死亡、计时、休眠与补足，不创建用户存档。
## [param catalog] 正式战斗目录。
## [param map_id] 第一张启用BOSS的十级地图。
func _test_refresh(catalog: CombatDefinitionCatalog, map_id: String) -> void:
	var directory: Dictionary = JsonConfigLoader.load_dictionary("res://data/maps/glory_map_directory_v1.json").value
	var instance := AuthoritativeMapInstance.new()
	_expect(instance.load_map(directory.definitions[map_id]).ok and instance.configure_combat(catalog, 20).ok, "真实十级图种群初始化")
	_expect(_count(instance, &"boss") == 2 and _count(instance, &"elite") == 30, "BOSS不挤占三十精英名额")
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		if monster.population_kind == &"boss":
			monster.apply_damage(monster.max_health, "player", 0)
	instance.combat_module.current_tick = 35999
	instance._replenish_additional_populations_if_due()
	_expect(_count(instance, &"boss") == 0, "未到半小时不能补BOSS")
	instance.combat_module.current_tick = 36000
	instance._replenish_additional_populations_if_due()
	_expect(_count(instance, &"boss") == 2, "半小时只补到两只")
	_expect(instance.suspend_runtime(36000) and instance.resume_runtime(3600000).ok, "无人图长时间休眠恢复")
	_expect(_count(instance, &"boss") == 2 and _count(instance, &"elite") == 30, "休眠不累计多批BOSS和精英")


## 统计指定种群存活数量。
## [param instance] 权威地图实例。
## [param kind] 需要统计的种群。
## 返回实际存活个体数。
func _count(instance: AuthoritativeMapInstance, kind: StringName) -> int:
	var result := 0
	for monster: MonsterLifecycle in instance.combat_module.monsters.values():
		if monster.population_kind == kind and monster.is_alive():
			result += 1
	return result


## 记录检查结果。
## [param condition] 预期成立的行为。
## [param message] 中文说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


## 汇总专项并终止测试进程。
func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("ENHANCEMENT_POPULATION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
