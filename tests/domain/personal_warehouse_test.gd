extends SceneTree

var checks := 0
var failures: Array[String] = []
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper


## 用隔离玩家验证整件状态、部分堆叠、失败回滚、扩容及当前存档校验。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "依赖")
	mapper = PlayerStateMapper.new(catalog)
	_test_full_states()
	_test_free_position_and_capacity()
	_test_expansion_and_invalid_state()
	print("Personal warehouse: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 对复杂装备、载入的记忆、裂纹及全部发生器做存入、JSON重读、取出。
func _test_full_states() -> void:
	var samples: Array[GameItem] = []
	var processing_state := EquipmentProcessing.new().to_dictionary()
	processing_state["increments"] = {"max_health": 1}
	var extra_attributes_state := ExtraAttributes.new().to_dictionary()
	extra_attributes_state["levels"] = {"fluorite:3": 1}
	var strengthening_state := EquipmentStrengthening.new().to_dictionary()
	strengthening_state["level"] = 3
	var forging := EquipmentForging.new()
	forging.extensions = {1: 50, 3: 3}
	var forging_state := forging.to_dictionary()
	var usage_state := EquipmentUsage.new().to_dictionary()
	usage_state["progress"] = {"movement": 3.5}
	var chassis_result := catalog.create("recruit_tank", {"instance_id": "stored.chassis", "bound": true,
		"processing": processing_state, "extra_attributes": extra_attributes_state,
		"strengthening": strengthening_state, "forging": forging_state, "usage": usage_state})
	_check(chassis_result.is_ok, "创建完整状态的底盘: %s %s" % [chassis_result.error_code, chassis_result.error_message])
	if not chassis_result.is_ok: return
	var chassis: VehicleEquipment = chassis_result.value
	chassis.sockets.settle_open(0, true, "")
	var embedded := _create_item("bright_health_crystal", {"instance_id": "embedded", "bound": true, "crystal_cracks": 2}, "创建嵌入晶石") as VehicleCrystal
	if embedded == null: return
	_check(chassis.sockets.inlay(0, embedded).is_ok, "嵌入晶石")
	chassis.durability -= 5
	samples.append(chassis)
	var memory := _create_item("equipment_memory_sockets", {"instance_id": "stored.memory"}, "创建记忆模块") as EquipmentMemoryModule
	if memory == null: return
	var captured_memory := EquipmentMemory.capture(chassis, 6)
	_check(captured_memory.is_ok, "捕获装备记忆")
	if not captured_memory.is_ok: return
	memory.memory = captured_memory.value
	samples.append(memory)
	var quality_item := _create_item("glory_equipment_gun8_e7ce1423fa", {"instance_id": "stored.quality", "equipment_quality": {"version": 1, "grade": 3}}, "创建品质装备")
	if quality_item == null: return
	samples.append(quality_item)
	var magazine_state := WeaponMagazine.new().to_dictionary()
	magazine_state["remaining"] = 12
	var missile_processing_state := EquipmentProcessing.new().to_dictionary()
	missile_processing_state["increments"] = {"base_attack": 2, "ammunition_capacity": 50}
	var missile_forging := EquipmentForging.new()
	missile_forging.extensions = {6: 20}
	var missile_forging_state := missile_forging.to_dictionary()
	var missile := _create_item("starter_missile", {"instance_id": "stored.missile",
		"magazine": magazine_state, "processing": missile_processing_state, "forging": missile_forging_state}, "创建完整状态的导弹")
	if missile == null: return
	samples.append(missile)
	var firepower_crystal := _create_item("bright_firepower_crystal", {"instance_id": "stored.crystal", "quantity": 7, "crystal_cracks": 2}, "创建火力晶石")
	if firepower_crystal == null: return
	samples.append(firepower_crystal)
	var clothing_id: String = catalog.clothing_improvement_rules.slots.keys()[0]
	var attribute: String = catalog.clothing_improvement_rules.channels.keys()[0]
	var improvement_state := ClothingImprovement.new()
	improvement_state.attribute = attribute
	improvement_state.level = 55
	var enhancement_state := ClothingEnhancement.new()
	enhancement_state.prefix = "tiger"
	enhancement_state.prefix_quality = 4
	enhancement_state.trait_id = "repair"
	enhancement_state.trait_quality = 3
	enhancement_state.gem = "movement_speed"
	enhancement_state.gem_stage = 7
	var clothing := _create_item(clothing_id, {"instance_id": "stored.clothing",
		"clothing_improvement": improvement_state.to_dictionary(),
		"enhancement": enhancement_state.to_dictionary()}, "创建强化服装")
	if clothing == null: return
	samples.append(clothing)
	for id: String in catalog.generator_rules.profiles:
		var generator := _create_item(id, {"instance_id": "stored.generator"}, "创建发生器 " + id) as Equipment
		if generator == null: continue
		if generator.magazine.remaining > 0: generator.magazine.consume()
		samples.append(generator)
	for item: GameItem in samples:
		_check(item != null, "样本有效")
		if item == null: continue
		var player := _player()
		_check(player.inventory.add_reward(item).is_ok, "入包")
		var before := _item_state(item)
		var revision := player.inventory.revision
		_check(player.warehouse.transfer(player.inventory, 1, true, item.instance_id, Vector2i(117, 139), revision, 0).is_ok, "存入")
		_check(player.inventory.find(item.instance_id) == null and player.warehouse.find(item.instance_id) == item, "整件转移同一对象")
		_check(not player.warehouse.transfer(player.inventory, 1, true, item.instance_id, Vector2i.ZERO, revision, 0).is_ok, "重发拒绝")
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
		_check(_item_state(stored) == before and stored.position_px == Vector2i(117, 139), "保存不丢实例状态和自由落点")
		_check(player.warehouse.transfer(player.inventory, 1, false, item.instance_id, Vector2i(91, 103), player.inventory.revision, player.warehouse.revision).is_ok, "取出")
		_check(player.warehouse.find(item.instance_id) == null and _item_state(player.inventory.find(item.instance_id)) == before, "取出不复制且全部状态一致")


## 覆盖自由落点、重叠、容量、锁定及失败不改状态。
func _test_free_position_and_capacity() -> void:
	var player := _player()
	var input := _create_item("low_grade_gel", {"instance_id": "gel", "quantity": 80}, "创建类胶")
	if input == null: return
	player.inventory.add_reward(input)
	var bank := player.warehouse._cabinets[0]
	bank.add_reward(_create_item("low_grade_gel", {"instance_id": "existing", "quantity": 1}, "已有同类堆叠"))
	var center := bank.find("existing").position_px
	_check(player.warehouse.transfer(player.inventory, 1, true, "gel", center, player.inventory.revision, 0).is_ok, "允许重叠落点")
	_check(bank.find("gel") == input and input.quantity == 80 and bank.find("existing").quantity == 1 \
		and input.position_px == center, "整堆保留落点，不自动合并到其他物品")
	_check(player.warehouse.transfer(player.inventory, 1, false, "gel", Vector2i(73, 129), player.inventory.revision, player.warehouse.revision).is_ok, "取回自由落点")
	bank.capacity = 1
	var before := _player_state(player)
	_check(not player.warehouse.transfer(player.inventory, 1, true, "gel", center, player.inventory.revision, player.warehouse.revision).is_ok and _player_state(player) == before, "满柜拒绝不先扣数量")
	bank.capacity = InventoryLayout.ITEM_LIMIT
	input.locked = true
	before = _player_state(player)
	_check(not player.warehouse.transfer(player.inventory, 1, true, "gel", center, player.inventory.revision, player.warehouse.revision).is_ok and _player_state(player) == before, "锁定拒绝")
	input.locked = false
	player.inventory.capacity = 1
	before = _player_state(player)
	_check(not player.warehouse.transfer(player.inventory, 1, false, "existing", center, player.inventory.revision, player.warehouse.revision).is_ok and _player_state(player) == before, "满包取出失败保持仓库")
	_check(not player.warehouse.transfer(player.inventory, 2, true, "gel", center, player.inventory.revision, player.warehouse.revision).is_ok, "未开通柜不可存入")
	for position: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(InventoryLayout.MAIN_SIZE.x, 0), Vector2i(0, InventoryLayout.MAIN_SIZE.y)]:
		_check(not player.warehouse.transfer(player.inventory, 1, true, "gel", position, player.inventory.revision, player.warehouse.revision).is_ok and _player_state(player) == before, "越界拒绝且不改状态")


## 扩容保留价格和上限；缺仓库字段、损坏数据与跨容器复制均拒绝。
func _test_expansion_and_invalid_state() -> void:
	var rules: WarehouseRules = WarehouseRules.load_default().value
	_check(rules.expansion_cost == 1888 and rules.allows("yian_harbor_city") and not rules.allows("glory_nft_bl_d04"), "原版费用与地点规则")
	var player := _player()
	player.amethyst = AmethystWallet.new(1888 * 5)
	for index in 5:
		_check(player.warehouse.expand(player.amethyst, rules, index).is_ok, "逐柜开通")
		_check(not player.warehouse.expand(player.amethyst, rules, index).is_ok, "扩容重发拒绝")
	_check(player.warehouse.cabinet_count() == 6 and player.amethyst.balance() == 0, "六柜准确收费")
	_check(not player.warehouse.expand(player.amethyst, rules, 5).is_ok, "六柜封顶")
	var raw := fixture._state.to_dictionary()
	raw.erase("warehouse")
	_check(not PlayerStateRecord.from_dictionary(raw).is_ok, "当前玩家存档缺仓库状态必须拒绝")
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
	player.warehouse.materialize()
	return player


## 创建物品并记录工厂失败，调用方在访问物品前处理空结果。
func _create_item(definition_id: String, state: Dictionary, label: String) -> GameItem:
	var result := catalog.create(definition_id, state)
	_check(result.is_ok, "%s: %s %s" % [label, result.error_code, result.error_message])
	return result.value if result.is_ok else null


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
