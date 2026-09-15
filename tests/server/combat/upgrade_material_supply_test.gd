extends SceneTree

const FRAGMENT := "item:material:9713f13ede8d"
const CRAWLERS := ["glory_monster_046", "glory_monster_114"]
var failures: Array[String] = []
var checks := 0

class NavigationFixture:
	extends RefCounted
	var graph := AStar2D.new()


## 延迟到内容挂载和场景树可用后测试完整材料供应。
func _initialize() -> void:
	call_deferred("_run")


## 验证正式目录、概率分布、世界投影和等级采集约束。
func _run() -> void:
	var items := ItemCatalog.new()
	_expect(items.initialize().is_ok, "物品目录加载")
	var loaded := CombatDefinitionCatalog.load_default()
	_expect(loaded.is_ok, "正式战斗目录加载材料投放")
	if not loaded.is_ok:
		_finish()
		return
	var catalog: CombatDefinitionCatalog = loaded.value
	var material_rules := JsonConfigLoader.load_dictionary("res://data/gameplay/monster_material_drops_v1.json").value as Dictionary
	for row: Dictionary in material_rules.definitions:
		var actual := DropTable.new(catalog.monster_definition(row.monster_id).drops)
		for entry: Dictionary in actual.entries():
			_expect(not items.definition(entry.item_definition_id).is_empty(), "掉落物必须可实例化并入包")
			if entry.item_definition_id == FRAGMENT:
				_expect(row.monster_id in CRAWLERS, "碎片不能误投到其他机械怪物")
	for id: String in CRAWLERS:
		var entries: Array = catalog.monster_definition(id).drops
		var fragments: Array = entries.filter(func(row: Dictionary) -> bool: return row.item_definition_id == FRAGMENT)
		_expect(fragments.size() == 1, "每种爬虫恰好一条碎片规则，变体共享物种规则")
		var entry: Dictionary = fragments[0]
		_expect(entry.minimum_quantity == 1 and entry.maximum_quantity == 3 and is_equal_approx(entry.chance, 0.75), "四种数量的理论概率各25%")
		var table := DropTable.new(fragments)
		var random := RandomNumberGenerator.new()
		random.seed = 20260915
		var histogram := [0, 0, 0, 0]
		for _sample in range(40000):
			var rolled := table.roll(random)
			var quantity := 0 if rolled.is_empty() else int(rolled[0].quantity)
			if quantity < 0 or quantity > 3:
				_expect(false, "碎片数量不能越界")
				break
			histogram[quantity] += 1
		for count: int in histogram:
			_expect(absi(count - 10000) < 400, "固定种子采样四种结果均约25%")
		var mean := float(histogram[1] + 2 * histogram[2] + 3 * histogram[3]) / 40000.0
		_expect(absf(mean - 1.5) < 0.03, "真实随机结算均值接近1.5")
		print("CRAWLER_DROP %s histogram=%s mean=%.4f" % [id, histogram, mean])
	var gel: Array = catalog.monster_definition("glory_monster_009").drops
	_expect(gel.any(func(row: Dictionary) -> bool: return row.item_definition_id == "item:material:472d2fb951cb"), "恶性毒胶实际掉中级类胶")
	_expect(gel.any(func(row: Dictionary) -> bool: return row.item_definition_id == "item:material:fa5a837875bb"), "恶性毒胶实际掉高级类胶")
	_expect(catalog.monster_definition("om_adult").drops.size() == 2, "原新手怪物掉落保留")
	var spawned_crawler := false
	for map_id: String in catalog.monster_encounter_map_ids():
		var population := catalog.monster_lifecycles_for_map(map_id, "supply.test").value as Array
		for definition: Dictionary in population:
			if definition.species_id == "glory_monster_046":
				definition.position = Vector2(100, 100)
				var monster := MonsterLifecycle.new()
				_expect(monster.configure(definition, 20).is_ok and monster.drop_table.is_configured(), "地图生成的爬虫真正携带掉落领域对象")
				spawned_crawler = true
				break
		if spawned_crawler:
			break
	_expect(spawned_crawler, "普通爬虫在当前启用地图有实际种群")
	var daily := DailyActivityCatalog.new()
	_expect(daily.initialize(items).is_ok, "任务目录认识新增材料来源")
	_expect(daily.tasks.values().any(func(task: MercenaryDefinition) -> bool: return task.target_id == "item:material:472d2fb951cb"), "中级类胶收集委托进入可完成目录")
	print("AVAILABLE_DAILY_TASKS %d" % daily.tasks.size())
	await _test_mining()
	_finish()


## 在真实矿源模块中验证五种矿物的地图投放、采掘门槛和产物，并检查地面可点击视图。
func _test_mining() -> void:
	var catalog: MiningCatalog = MiningCatalog.load_default().value
	var expected := {"硫矿": [150, "c07"], "磷矿": [200, "g06"], "钾矿": [250, "h07"], "镭矿": [300, "d08"], "铬矿": [300, "d08"]}
	var navigation := NavigationFixture.new()
	for i in range(400):
		navigation.graph.add_point(i, Vector2((i % 20) * 120 + 120, floori(i / 20.0) * 120 + 120))
	var world := Node2D.new()
	root.add_child(world)
	var display := MineralWorldController.new()
	root.add_child(display)
	var manifest: Dictionary = JsonConfigLoader.load_dictionary("res://assets/minerals/mining_asset_manifest.json").value
	_expect(display.configure(world, manifest) == OK, "矿源表现挂载荣耀资源")
	var snapshots: Array = []
	for id: String in catalog.mineral_ids():
		var mineral := catalog.mineral(id)
		if not expected.has(mineral.display_name):
			continue
		var rule: Array = expected[mineral.display_name]
		_expect(mineral.required_mining_level == rule[0], "矿源等级与设计阶梯一致")
		for region: String in ["bl", "bt"]:
			var map_id := "glory_nft_%s_%s" % [region, rule[1]]
			var module := AuthoritativeMiningModule.new()
			_expect(module.configure(catalog, map_id, "mine.test", 20, navigation).is_ok, "目标地图真实生成矿源")
			var found: MineSource
			for source: MineSource in module.sources.values():
				if source.mineral_id == id:
					found = source
					break
			_expect(found != null, "当前地图初始种群已生成目标矿物")
			if found == null:
				continue
			var position := found.position + Vector2(40, 0)
			_expect(module.begin_collection("miner", position, found.position, int(rule[0]) - 1, 1).error_code == &"mining.skill_too_low", "低一级不能采掘")
			_expect(module.begin_collection("miner", position, found.position, int(rule[0]), 2).is_ok, "达到等级可以采掘")
			module.advance_ticks(60)
			var cycles := module.drain_ready_cycles()
			_expect(cycles.size() == 1, "实际三秒周期产生结算")
			if not cycles.is_empty():
				var result := module.commit_cycle(cycles[0].token)
				_expect(result.is_ok and result.value.item_definition_id == mineral.item_definition_id, "产出对应矿石而非错误的元素成品")
		var index := snapshots.size()
		snapshots.append({"source_id": id, "mineral_id": id, "display_name": mineral.display_name,
			"position": [100 + index * 155, 170], "remaining": 50, "required_mining_level": rule[0], "visual_variant": 0})
		var label := Label.new()
		label.text = "%s · %d级" % [mineral.display_name, rule[0]]
		label.position = Vector2(50 + index * 155, 220)
		label.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_font.tres"))
		world.add_child(label)
	display.apply_snapshot({"mine_sources": snapshots})
	_expect(display.active_view_count() == 5, "五种矿源全部可见，硫磷钾不能出现隐形矿点")
	for row: Dictionary in snapshots:
		var view := display.view_for_source(row.source_id)
		if view != null:
			_expect(display.source_at(view.to_global(view.local_hit_rect().get_center())) == row.source_id, "矿源图像中心可点击和选择")
	if "--capture" in OS.get_cmdline_user_args():
		root.size = Vector2i(850, 350)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/upgrade-material-mines.png")
	display.queue_free()
	world.queue_free()
	await process_frame


## 记录业务行为断言。
## [param condition] 业务条件。
## [param message] 失败原因。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


## 输出本轮结果并结束测试进程。
func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("UPGRADE_MATERIAL_SUPPLY checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
