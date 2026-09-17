extends SceneTree

var checks := 0
var failures := PackedStringArray()
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper
var equipment_id := "glory_equipment_newequip_shan_e010f43b10"


## 验证费用、风险确认、版本、失败退级、摘取损毁及成功容量的原子边界。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "dependencies")
	mapper = PlayerStateMapper.new(catalog)
	_test_growth()
	_test_inlay()
	_test_composition()
	print("Crystal source actions: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 使用真实材料测试低阶成功、高阶失败、保护以及材料不足和重发。
func _test_growth() -> void:
	for sample: Array in [["quality", 0, false, 0.99, 1], ["quality", 13, false, 0.99, 0], ["quality", 13, true, 0.99, 13], ["growth", 14, false, 0.99, 15]]:
		var player := _player()
		var item := _equipment(player)
		item.crystal_source.set(String(sample[0]), sample[1])
		var quote := PlayerCrystalSourceActions.growth_quote(player, catalog, item.instance_id, sample[0], sample[2])
		_check(quote.is_ok and not quote.value.can_execute, "missing materials shown")
		var before := _state(player)
		_check(not PlayerCrystalSourceActions.grow(player, catalog, item.instance_id, sample[0], sample[2], true, player.inventory.revision, sample[3]).is_ok and _state(player) == before, "missing materials unchanged")
		for cost: Dictionary in quote.value.requirements: _add(player, cost.definition_id, cost.quantity, true)
		before = _state(player)
		var revision := player.inventory.revision
		_check(not PlayerCrystalSourceActions.grow(player, catalog, item.instance_id, sample[0], sample[2], false, revision, sample[3]).is_ok and _state(player) == before, "confirmation required")
		var result := PlayerCrystalSourceActions.grow(player, catalog, item.instance_id, sample[0], sample[2], true, revision, sample[3])
		_check(result.is_ok and result.value.after == sample[4], "actual upgrade outcome")
		var current := player.inventory.find(item.instance_id) as VehicleEquipment
		_check(current.bound and current != item and player.inventory.revision == revision + 1, "bound independent replacement one revision")
		for cost: Dictionary in quote.value.requirements: _check(player.inventory.count_definition(cost.definition_id) == 0, "exact costs")
		before = _state(player)
		_check(not PlayerCrystalSourceActions.grow(player, catalog, item.instance_id, sample[0], sample[2], true, revision, sample[3]).is_ok and _state(player) == before, "replay no charge")
		_check(item.crystal_source.get(String(sample[0])) == sample[1], "original candidate not mutated")


## 跟踪同一颗两裂核心摘出、重新镶嵌与三裂损毁，并验证满包不清孔。
func _test_inlay() -> void:
	var player := _player()
	var item := _equipment(player)
	var core := _add(player, "crystal_source_core_red_3", 2, true) as CrystalSourceCore
	core.cracks = 2
	_check(PlayerCrystalSourceActions.inlay(player, catalog, item.instance_id, core.instance_id, 0, player.inventory.revision).is_ok, "inlay")
	_check(item.bound and core.quantity == 1 and item.crystal_source.slots[0].cracks == 2, "binding and exact core")
	var before := _state(player)
	_check(not PlayerCrystalSourceActions.inlay(player, catalog, item.instance_id, core.instance_id, 1, player.inventory.revision).is_ok and _state(player) == before, "duplicate color unchanged")
	player.inventory.capacity = player.inventory.items().size()
	before = _state(player)
	_check(not PlayerCrystalSourceActions.extract(player, catalog, item.instance_id, 0, false, player.inventory.revision, "extracted").is_ok and _state(player) == before, "full bag cannot lose core")
	player.inventory.capacity = 40
	_check(PlayerCrystalSourceActions.extract(player, catalog, item.instance_id, 0, false, player.inventory.revision, "extracted").is_ok, "extract into space")
	var extracted := player.inventory.find("extracted") as CrystalSourceCore
	_check(extracted.cracks == 3 and extracted.bound and item.crystal_source.slots[0].definition_id.is_empty(), "third crack retained")
	_check(PlayerCrystalSourceActions.inlay(player, catalog, item.instance_id, extracted.instance_id, 0, player.inventory.revision).is_ok, "inlay three crack core")
	before = _state(player)
	_check(not PlayerCrystalSourceActions.extract(player, catalog, item.instance_id, 0, false, player.inventory.revision, "never").is_ok and _state(player) == before, "explicit destruction confirmation")
	_check(PlayerCrystalSourceActions.extract(player, catalog, item.instance_id, 0, true, player.inventory.revision, "never").is_ok and player.inventory.find("never") == null and item.crystal_source.slots[0].definition_id.is_empty(), "destroy retains empty socket")
	item.locked = true
	_check(not PlayerCrystalSourceActions.target(player, item.instance_id).is_ok, "locked equipment")


## 覆盖每一阶原版概率、稳定剂上限、裂纹继承及满包两种随机结果。
func _test_composition() -> void:
	for level in range(1, 5):
		for succeed: bool in [true, false]:
			var player := _player()
			var core := _add(player, catalog.crystal_source_rules.core_at("yellow", level).definition_id, 6, true) as CrystalSourceCore
			core.cracks = 2
			var quote := PlayerCrystalSourceActions.composition_quote(player, catalog, core.instance_id, 0, "composed")
			_check(quote.is_ok and quote.value.can_execute and quote.value.cracks == 2, "composition quote")
			var revision := player.inventory.revision
			_check(PlayerCrystalSourceActions.compose(player, catalog, core.instance_id, 0, revision, true, "composed", 0.0 if succeed else 0.99).is_ok, "composition settled")
			_check(core.quantity == 1 and player.inventory.revision == revision + 1, "five inputs exactly")
			var product := player.inventory.find("composed") as CrystalSourceCore
			_check((product != null and product.profile.level == level + 1 and product.cracks == 2 and product.bound) if succeed else product == null, "success output or failure no output")
			var before := _state(player)
			_check(not PlayerCrystalSourceActions.compose(player, catalog, core.instance_id, 0, revision, true, "replay", 0).is_ok and _state(player) == before, "composition replay")
	var player := _player()
	var core := _add(player, "crystal_source_core_black_4", 6) as CrystalSourceCore
	_add(player, "crystal_source_core_stabilizer", 7)
	var quote := PlayerCrystalSourceActions.composition_quote(player, catalog, core.instance_id, 7, "perfect")
	_check(quote.value.chance == 1.0 and quote.value.maximum_stabilizers == 7, "seven stabilizers guarantees level five")
	_check(not PlayerCrystalSourceActions.composition_quote(player, catalog, core.instance_id, 8, "overpaid").is_ok, "no excess stabilizer waste")
	_check(PlayerCrystalSourceActions.compose(player, catalog, core.instance_id, 7, player.inventory.revision, true, "perfect", 0.999).is_ok and player.inventory.find("perfect").profile.level == 5, "guaranteed synthesis")
	_check(player.inventory.count_definition("crystal_source_core_stabilizer") == 0, "stabilizers consumed")
	player = _player()
	core = _add(player, "crystal_source_core_red_1", 6)
	player.inventory.capacity = 1
	var before := _state(player)
	for roll: float in [0.0, 0.99]:
		_check(not PlayerCrystalSourceActions.compose(player, catalog, core.instance_id, 0, player.inventory.revision, true, "blocked", roll).is_ok and _state(player) == before, "capacity preflight even failed roll")
	core.quantity = 5
	_check(PlayerCrystalSourceActions.compose(player, catalog, core.instance_id, 0, player.inventory.revision, true, "fits", 0).is_ok and player.inventory.items().size() == 1, "consumed stack frees output slot")


## 创建只保留默认车体的空背包隔离玩家。
## 返回测试聚合。
func _player() -> Player:
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory.restore_items([])
	return player


## 给测试玩家加入一件未成长的晶源体。
## [param player] 隔离玩家。
## 返回待加工的真实物品。
func _equipment(player: Player) -> VehicleEquipment:
	return _add(player, equipment_id, 1)


## 通过目录和正常库存入口添加测试材料。
## [param player] 玩家。[param id] 定义。[param amount] 数量。[param bound] 绑定。
## 返回实际加入的物品。
func _add(player: Player, id: String, amount: int, bound: bool = false) -> GameItem:
	var first: GameItem
	var remaining := amount
	while remaining > 0:
		var item: GameItem = catalog.create(id, {"instance_id": "test.%d" % player.inventory.revision, "quantity": remaining, "bound": bound}).value
		item.quantity = mini(remaining, item.max_stack)
		remaining -= item.quantity
		_check(player.inventory.add_reward(item).is_ok, "fixture item " + id)
		if first == null: first = item
	return first


## 经正式保存映射比较操作前后的全部事实。
## [param player] 测试聚合。
## 返回JSON状态。
func _state(player: Player) -> String:
	return JSON.stringify(mapper.to_record(player).value.to_dictionary())


## 收集断言，失败后继续其他独立测试。
## [param condition] 预期条件。[param message] 失败描述。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
