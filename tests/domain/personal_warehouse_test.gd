extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper


## 用隔离玩家验证整件状态、部分堆叠、失败回滚、扩容及旧存档兼容。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "依赖")
	mapper = PlayerStateMapper.new(catalog)
	_test_full_states()
	_test_partial_and_capacity()
	_test_expansion_and_invalid_state()
	print("Personal warehouse: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 对复杂装备、载入的记忆、裂纹及全部发生器做存入、JSON重读、取出。
func _test_full_states() -> void:
	var samples: Array[GameItem] = []
	var chassis: VehicleEquipment = catalog.create("recruit_tank", {"instance_id": "stored.chassis", "bound": true,
		"processing": {"increments": {"max_health": 1}}, "extra_attributes": {"levels": {"fluorite:3": 1}},
		"strengthening": {"level": 3}, "forging": {"extensions": {"1": 50, "3": 3}},
		"usage": {"progress": {"movement": 3.5}}}).value
	chassis.sockets.settle_open(0, true, "")
	chassis.sockets.inlay(0, catalog.create("bright_health_crystal", {"instance_id": "embedded", "bound": true, "crystal_cracks": 2}).value)
	chassis.durability -= 5
	samples.append(chassis)
	var memory: EquipmentMemoryModule = catalog.create("equipment_memory_sockets", {"instance_id": "stored.memory"}).value
	memory.memory = EquipmentMemory.capture(chassis, 6).value
	samples.append(memory)
	samples.append(catalog.create("glory_equipment_gun8_e7ce1423fa", {"instance_id": "stored.quality", "equipment_quality": {"version": 1, "grade": 3}}).value)
	samples.append(catalog.create("starter_missile", {"instance_id": "stored.missile", "magazine": {"remaining": 12},
		"processing": {"increments": {"base_attack": 2, "ammunition_capacity": 50}}, "forging": {"extensions": {"6": 20}}}).value)
	samples.append(catalog.create("bright_firepower_crystal", {"instance_id": "stored.crystal", "quantity": 7, "crystal_cracks": 2}).value)
	var clothing_id: String = catalog.clothing_improvement_rules.slots.keys()[0]
	var attribute: String = catalog.clothing_improvement_rules.channels.keys()[0]
	samples.append(catalog.create(clothing_id, {"instance_id": "stored.clothing",
		"clothing_improvement": {"attribute": attribute, "level": 55},
		"enhancement": {"prefix": "tiger", "prefix_quality": 4, "trait": "repair", "trait_quality": 3, "gem": "movement_speed", "gem_stage": 7}}).value)
	for id: String in catalog.generator_rules.profiles:
		var generator: Equipment = catalog.create(id, {"instance_id": "stored.generator"}).value
		if generator.magazine.remaining > 0: generator.magazine.consume()
		samples.append(generator)
	for item: GameItem in samples:
		_check(item != null, "样本有效")
		if item == null: continue
		var player := _player()
		_check(player.inventory.add_reward(item).is_ok, "入包")
		var before := _item_state(item)
		var revision := player.inventory.revision
		_check(player.warehouse.transfer(player.inventory, 1, true, item.instance_id, item.quantity, revision, 0, "split").is_ok, "存入")
		_check(player.inventory.find(item.instance_id) == null and player.warehouse.find(item.instance_id) == item, "整件转移同一对象")
		_check(not player.warehouse.transfer(player.inventory, 1, true, item.instance_id, 1, revision, 0, "replay").is_ok, "重发拒绝")
		var saved := mapper.to_record(player)
		_check(saved.is_ok, "保存全部字段")
		if not saved.is_ok: continue
		var parsed := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(saved.value.to_dictionary())))
		_check(parsed.is_ok, "真实JSON读取")
		var restored := mapper.to_domain(parsed.value)
		_check(restored.is_ok, "重建具体类型与规则")
		if not restored.is_ok: continue
		player = restored.value
		var stored := player.warehouse.find(item.instance_id)
		_check(_item_state(stored) == before, "保存不丢实例状态")
		_check(player.warehouse.transfer(player.inventory, 1, false, item.instance_id, item.quantity, player.inventory.revision, player.warehouse.revision, "split").is_ok, "取出")
		_check(player.warehouse.find(item.instance_id) == null and _item_state(player.inventory.find(item.instance_id)) == before, "取出不复制且全部状态一致")


## 覆盖部分存取、多堆合并、余量不足、锁定和绑定裂纹隔离。
func _test_partial_and_capacity() -> void:
	var player := _player()
	var input: GameItem = catalog.create("low_grade_gel", {"instance_id": "gel", "quantity": 80}).value
	player.inventory.add_reward(input)
	var bank := player.warehouse._cabinets[0]
	bank.capacity = 2
	for pair: Array in [["a", 20], ["b", 30]]:
		bank.add_reward(catalog.create("low_grade_gel", {"instance_id": pair[0], "quantity": input.max_stack - int(pair[1])}).value)
	_check(player.warehouse.transfer(player.inventory, 1, true, "gel", 50, player.inventory.revision, 0, "split.1").is_ok, "满柜仍可填满两个堆叠余量")
	_check(input.quantity == 30 and bank.items().size() == 2 and bank.count_definition("low_grade_gel") == input.max_stack * 2, "数量守恒")
	var before := _player_state(player)
	_check(not player.warehouse.transfer(player.inventory, 1, true, "gel", 1, player.inventory.revision, player.warehouse.revision, "split.2").is_ok and _player_state(player) == before, "满柜拒绝不先扣数量")
	input.locked = true
	before = _player_state(player)
	_check(not player.warehouse.transfer(player.inventory, 1, true, "gel", 1, player.inventory.revision, player.warehouse.revision, "split.3").is_ok and _player_state(player) == before, "锁定拒绝")
	player = _player()
	var crystal: VehicleCrystal = catalog.create("bright_firepower_crystal", {"instance_id": "crystal", "quantity": 7, "bound": true, "crystal_cracks": 2}).value
	player.inventory.add_reward(crystal)
	_check(player.warehouse.transfer(player.inventory, 1, true, "crystal", 3, player.inventory.revision, 0, "crystal.part").is_ok, "部分晶石存入")
	var part := player.warehouse.find("crystal.part") as VehicleCrystal
	_check(crystal.quantity == 4 and part.quantity == 3 and part.cracks == 2 and part.bound, "部分存取保留裂纹绑定")
	_check(player.warehouse.transfer(player.inventory, 1, false, part.instance_id, 3, player.inventory.revision, 1, "unused").is_ok and crystal.quantity == 7, "取回合并且不复制")
	player.inventory.capacity = 1
	player.warehouse._cabinets[0].add_reward(catalog.create("beginner_engine", {"instance_id": "engine"}).value)
	before = _player_state(player)
	_check(not player.warehouse.transfer(player.inventory, 1, false, "engine", 1, player.inventory.revision, player.warehouse.revision, "unused").is_ok and _player_state(player) == before, "满包取出失败保持仓库")
	_check(not player.warehouse.transfer(player.inventory, 2, true, "crystal", 1, player.inventory.revision, player.warehouse.revision, "split").is_ok, "未开通柜不可存入")
	for amount: int in [0, -1, 8]:
		_check(not player.warehouse.transfer(player.inventory, 1, true, "crystal", amount, player.inventory.revision, player.warehouse.revision, "split").is_ok, "非法数量拒绝")


## 扩容保留价格和上限；旧档初始化一个空柜，损坏与跨容器复制明确拒绝。
func _test_expansion_and_invalid_state() -> void:
	var rules: WarehouseRules = WarehouseRules.load_default().value
	_check(rules.expansion_cost == 1888 and rules.allows("yian_harbor_city") and not rules.allows("d04_field_zone"), "原版费用与地点规则")
	var player := _player()
	player.amethyst = AmethystWallet.new(1888 * 5)
	for index in 5:
		_check(player.warehouse.expand(player.amethyst, rules, index).is_ok, "逐柜开通")
		_check(not player.warehouse.expand(player.amethyst, rules, index).is_ok, "扩容重发拒绝")
	_check(player.warehouse.cabinet_count() == 6 and player.amethyst.balance() == 0, "六柜准确收费")
	_check(not player.warehouse.expand(player.amethyst, rules, 5).is_ok, "六柜封顶")
	var raw := fixture._state.to_dictionary()
	raw.erase("warehouse")
	var old := PlayerStateRecord.from_dictionary(raw)
	_check(old.is_ok and mapper.to_domain(old.value).value.warehouse.cabinet_count() == 1, "旧档一空柜")
	for invalid: Variant in [null, [], {"version": 2}, {"version": 1, "revision": 0, "cabinets": []}, {"version": 1, "revision": 0.5, "cabinets": [[]]}, {"version": 1, "revision": 0, "cabinets": [[], [], [], [], [], [], []]}]:
		_check(not PersonalWarehouseRecord.from_dictionary(invalid).is_ok, "损坏仓库拒绝")
	var duplicate: Dictionary = raw.inventory_stacks[0].duplicate(true)
	raw["warehouse"] = {"version": 1, "revision": 0, "cabinets": [[duplicate]]}
	_check(not PlayerStateRecord.from_dictionary(raw).is_ok, "跨背包和仓库身份复制拒绝")
	duplicate["stack_id"] = "warehouse.copy"
	for count: Variant in [0, -1, 1.5, true]:
		duplicate["quantity"] = count
		_check(not PersonalWarehouseRecord.from_dictionary({"version": 1, "revision": 0, "cabinets": [[duplicate]]}).is_ok, "数量不得截断或接受布尔值")


## 提供有真实装配但空背包的隔离玩家。
## 返回可保存的独立聚合。
func _player() -> Player:
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new()
	return player


## 排除合法落点变化后比较全部实例事实。
## [param item] 当前待检查物品。
## 返回确定性JSON文本。
func _item_state(item: GameItem) -> String:
	var state: Dictionary = InventoryStackRecord.from_item(item, 0).value.to_dictionary()
	state.erase("position_px")
	return JSON.stringify(state)


## 捕获双方容器和钱包，检查拒绝是否污染其他状态。
## [param player] 测试玩家。
## 返回完整存档文本。
func _player_state(player: Player) -> String:
	return JSON.stringify(mapper.to_record(player).value.to_dictionary())


## 汇总单项状态验证。
## [param condition] 实际条件。
## [param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
