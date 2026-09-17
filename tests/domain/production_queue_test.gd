extends SceneTree

const IRON := "item:material:8f615d2ef879"
var checks := 0
var failures: Array[String] = []
var catalog := ItemCatalog.new()
var mapper: PlayerStateMapper
var recipe: ManufacturingRecipe
var rules: ProductionRules
var config: Dictionary


## 验证有状态订单的时序、版本、完整人物存档往返和非法输入。
func _initialize() -> void:
	_check(catalog.initialize().is_ok, "目录")
	mapper = PlayerStateMapper.new(catalog)
	rules = ProductionRules.load_default().value
	config = JsonConfigLoader.load_dictionary("res://data/gameplay/skill_progression.json").value
	recipe = ManufacturingRecipe.new({"recipe_id": "test.order", "station_id": "equipment_manufacturing",
		"product_definition_id": "beginner_engine", "skill_id": "manufacturing", "required_skill_level": 0,
		"skill_experience": 1, "materials": [{"definition_id": IRON, "quantity": 2}]})
	_test_lifecycle()
	_test_rejections()
	_test_restore_validation()
	for failure in failures: push_error(failure)
	print("Production queue: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


## 通过开始、等待、完成、暂停、重读、恢复与取消检验恰好一次结算。
func _test_lifecycle() -> void:
	var player := _player()
	var inventory_revision := player.inventory.revision
	_check(player.production.start(recipe, player, 3, 2, "order.one", rules, 0).is_ok, "创建三轮二档订单")
	_check(player.inventory.revision == inventory_revision and player.inventory.count_definition(IRON) == 50, "开始不扣料")
	_check(not player.production.start(recipe, player, 1, 1, "other", rules, 1).is_ok, "不允许并行订单")
	_check(not _complete(player, "early").is_ok, "未到时不能结算")
	_check(player.production.capture_remaining("order.one", 1, 500), "权威计时捕获")
	_check(player.production.revision == 1 and player.production.order.remaining_milliseconds == 500, "时钟不改变操作版本")
	var saved: PlayerStateRecord = mapper.to_record(player).value
	var serialized: Dictionary = JSON.parse_string(JSON.stringify(saved.to_dictionary()))
	player = mapper.to_domain(PlayerStateRecord.from_dictionary(serialized).value).value
	_check(player.production.order.remaining_milliseconds == 500 and player.production.order.speed == 2, "完整JSON保存剩余等待与速度")
	_check(not player.production.capture_remaining("old", 1, 0) and not player.production.capture_remaining("order.one", 0, 0), "旧时钟不可覆盖新订单")
	player.production.capture_remaining("order.one", 1, 0)
	var done := _complete(player, "first")
	_check(done.is_ok and not done.value.order_done and done.value.completed == 1, "完成第一轮")
	_check(player.inventory.count_definition(IRON) == 46 and player.inventory.count_definition("beginner_engine") == 2, "二档真实消耗和产物")
	_check(player.production.order.remaining_milliseconds == 2000 and player.production.revision == 2, "下一轮重新等待")
	_check(not _complete(player, "duplicate").is_ok and player.inventory.count_definition("beginner_engine") == 2, "重复完成不再次产出")
	player.production.capture_remaining("order.one", 2, 1200)
	_check(player.production.pause("切图暂停"), "切图暂停")
	_check(not player.production.pause("再暂停") and player.production.revision == 3, "重复暂停不增版本")
	var snapshot := mapper.to_record(player).value as PlayerStateRecord
	var clone := snapshot.duplicate_record()
	clone.production.cancel(3)
	_check(snapshot.production.order != null, "持久化候选之间不共享可变订单")
	player = mapper.to_domain(PlayerStateRecord.from_dictionary(snapshot.to_dictionary()).value).value
	_check(player.production.order.paused and player.production.order.completed == 1 and player.production.order.remaining_milliseconds == 1200, "重启保留暂停和已完成轮次")
	_check(not player.production.resume("other.map", 3).is_ok, "不能异地继续")
	_check(player.production.resume(player.map_id, 3).is_ok, "原地图继续")
	var before := player.inventory.revision
	var canceled := player.production.cancel(4)
	_check(canceled.is_ok and canceled.value.completed == 1 and canceled.value.canceled == 2, "取消只删除剩余轮次")
	_check(player.inventory.revision == before and player.inventory.count_definition("beginner_engine") == 2, "取消没有二次返还或撤销已完成产物")
	_check(not player.production.cancel(4).is_ok, "重复取消拒绝")
	_check(player.production.start(recipe, player, 1, 1, "order.two", rules, 5).is_ok, "取消后新订单")
	_check(not player.production.cancel(4).is_ok and player.production.order.id == "order.two", "旧取消不能删除新订单")
	player.production.capture_remaining("order.two", 6, 0)
	done = player.production.complete_cycle(player, recipe, catalog, "last", 0, config, [0.0])
	_check(done.is_ok and done.value.order_done and player.production.order == null and player.production.revision == 7, "最后一轮清空订单但保留版本")
	serialized = mapper.to_record(player).value.to_dictionary()
	serialized.erase("production")
	_check(PlayerStateRecord.from_dictionary(serialized).value.production.order == null, "旧档无订单字段兼容")


## 验证无效速度、版本、满包与失败周期不会推进订单或消耗材料。
func _test_rejections() -> void:
	var player := _player()
	for pair: Array in [[0, 1], [10001, 1], [1, 0], [1, 11]]:
		_check(not player.production.start(recipe, player, pair[0], pair[1], "invalid", rules, 0).is_ok, "次数速度拒绝")
	_check(player.production.order == null and player.production.revision == 0, "拒绝未修改队列")
	player.inventory.items()[0].locked = true
	_check(not player.production.start(recipe, player, 1, 1, "locked", rules, 0).is_ok, "锁定材料不能开始")
	player.inventory.items()[0].locked = false
	player.production.start(recipe, player, 3, 2, "full", rules, 0)
	player.production.capture_remaining("full", 1, 0)
	player.inventory.capacity = 2
	var before := player.inventory.revision
	_check(not _complete(player, "full.product").is_ok and player.production.revision == 1 and player.production.order.completed == 0, "满包不完成该轮")
	_check(player.inventory.revision == before and player.inventory.count_definition(IRON) == 50, "满包不扣材料")
	player.inventory.capacity = 40
	player.map_id = "other"
	_check(not _complete(player, "wrong.map").is_ok, "到期仍核验地点")
	player.map_id = player.production.order.map_id
	_check(not player.production.complete_cycle(player, recipe, catalog, "wrong.speed", 0, config, [0.0]).is_ok, "到期核验速度")
	_check(not player.production.capture_remaining("full", 1, -1) and not player.production.capture_remaining("full", 1, 2001), "时钟范围校验")
	player.inventory.items()[0].quantity = 1
	_check(not _complete(player, "missing").is_ok and player.production.order.completed == 0, "等待期间材料被用掉不扣半轮")


## 拒绝非法读盘数据，尤其JSON浮点、小数、布尔、无穷和已经完成的伪订单。
func _test_restore_validation() -> void:
	var player := _player()
	player.production.start(recipe, player, 3, 2, "valid", rules, 0)
	var raw := player.production.to_dictionary()
	_check(ProductionQueue.restore(JSON.parse_string(JSON.stringify(raw))).is_ok, "JSON数字可还原")
	for value: Variant in [true, "1", 1.5, INF, -1, 10001]:
		var invalid := raw.duplicate(true)
		invalid.order.cycles = value
		_check(not ProductionQueue.restore(invalid).is_ok, "非法轮数拒绝")
	for key: String in ["id", "recipe_id", "station_id", "map_id"]:
		var invalid := raw.duplicate(true)
		invalid.order.erase(key)
		_check(not ProductionQueue.restore(invalid).is_ok, "丢失字段拒绝：" + key)
	for change: Dictionary in [{"completed": 3}, {"remaining_milliseconds": 2001}, {"paused": 1}, {"speed": 11}, {"cycle_milliseconds": 0}]:
		var invalid := raw.duplicate(true)
		invalid.order.merge(change, true)
		_check(not ProductionQueue.restore(invalid).is_ok, "非法状态拒绝")
	for value: Variant in [[], null, 1]: _check(not ProductionQueue.restore(value).is_ok, "非对象拒绝")
	var snapshot: Dictionary = mapper.to_record(player).value.to_dictionary()
	snapshot.production.order.speed = -1
	_check(not PlayerStateRecord.from_dictionary(snapshot).is_ok, "非法订单拒绝整个玩家存档")
	var rule_data: Dictionary = JsonConfigLoader.load_dictionary("res://data/gameplay/production_rules_v1.json").value
	rule_data.cycle_milliseconds = 0.5
	_check(not ProductionRules.from_document(rule_data).is_ok, "非法部署周期拒绝")


## 建立可持久化的隔离测试角色，保留实际装备与完整状态映射。
## 返回持有50铁的玩家。
func _player() -> Player:
	var fixture := PlayerPanelServiceFixture.new()
	fixture.initialize()
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new()
	player.inventory.add_reward(catalog.create(IRON, {"instance_id": "iron", "quantity": 50}).value)
	return player


## 通过正式订单执行二档轮次。
## [param player] 当前订单所属人物。
## [param identity] 本轮测试产物的唯一身份。
## 返回实际结算结果。
func _complete(player: Player, identity: String) -> DomainResult:
	return player.production.complete_cycle(player, recipe, catalog, identity, 0, config, [0.0, 0.0])


## 累计时序和存档不变量断言。
## [param condition] 预期条件。
## [param label] 故障标签。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
