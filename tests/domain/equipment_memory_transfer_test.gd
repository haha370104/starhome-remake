extends SceneTree

var items := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper
var checks := 0
var failures := 0


## 验证成长移动的唯一性、独立类型、保存、晶石和事务失败无副作用。
func _initialize() -> void:
	_check(items.initialize().is_ok and fixture.initialize().is_ok, "初始化")
	mapper = PlayerStateMapper.new(items)
	for kind: int in [1, 3, 4, 5, 6]:
		var player := _player(kind)
		var old: VehicleEquipment = player.inventory.find("source")
		var before := old.to_view_dictionary()
		var selected := EquipmentMemory.capture(old, kind)
		var revision := player.inventory.revision
		var result := _execute(player, "source", "extract", true, 0.99999)
		_check(result.is_ok and result.value.success, "稳压提取必成")
		if not result.is_ok: push_error(result.error_message); continue
		_check(player.inventory.revision == revision + 1, "原子版本")
		var source: VehicleEquipment = player.inventory.find("source")
		var module: EquipmentMemoryModule = player.inventory.find("module")
		_check(not EquipmentMemory.capture(source, kind).is_ok and module.memory.to_dictionary() == selected.value.to_dictionary(), "成长只存在模块")
		_check(source.durability == before.durability and source.max_durability == before.max_durability, "耐久保留")
		_check(module.bound, "源绑定传播")
		var saved := mapper.to_record(player)
		player = mapper.to_domain(PlayerStateRecord.from_dictionary(saved.value.to_dictionary()).value).value
		_check(player.inventory.find("module").memory.to_dictionary() == module.memory.to_dictionary(), "保存载荷")
		var current := CurrentPlayer.new(items)
		_check(current.apply_bundle(fixture._service.build_bundle(saved.value)) and current.inventory.find("module").memory.has_growth(), "客户端载荷")
		var transfer := _execute(player, "target", "transfer", true, 0.99999)
		_check(transfer.is_ok and player.inventory.find("module") == null, "转移消费指定模块")
		if not transfer.is_ok: push_error(transfer.error_message); continue
		var target: VehicleEquipment = player.inventory.find("target")
		_check(EquipmentMemory.capture(target, kind).value.equipment_state() == selected.value.equipment_state(), "目标完整承接")
		_check(target.bound, "目标绑定传播")
		_check(not _execute(player, "target", "transfer", false, 0).is_ok, "重复转移不能复制")
		player = _player(kind)
		before = player.inventory.find("source").to_view_dictionary()
		var failed := _execute(player, "source", "extract", false, 0.8)
		_check(failed.is_ok and not failed.value.success and player.inventory.find("module") == null, "提取失败消费模块")
		_check(player.inventory.find("source").to_view_dictionary() == before, "提取失败源完全不变")
		player = _player(kind)
		_execute(player, "source", "extract", true, 0)
		before = player.inventory.find("target").to_view_dictionary()
		failed = _execute(player, "target", "transfer", false, 0.8)
		_check(failed.is_ok and not failed.value.success and player.inventory.find("target").to_view_dictionary() == before and player.inventory.find("module") == null, "转移失败只销毁模块")
		player = _player(kind)
		player.inventory.find("module").locked = true
		before = mapper.to_record(player).value.to_dictionary()
		_check(not _execute(player, "source", "extract", true, 0).is_ok and mapper.to_record(player).value.to_dictionary() == before, "锁定无副作用")
	var player := _player(1)
	_execute(player, "source", "extract", true, 0)
	var before: Dictionary = mapper.to_record(player).value.to_dictionary()
	_check(not _execute(player, "inventory.spare_engine", "transfer", true, 0).is_ok and mapper.to_record(player).value.to_dictionary() == before, "不同装备类型拒绝")
	player = _player(5)
	player.inventory.find("target").strengthening.level = 1
	_execute(player, "source", "extract", true, 0)
	before = mapper.to_record(player).value.to_dictionary()
	_check(not _execute(player, "target", "transfer", true, 0).is_ok and mapper.to_record(player).value.to_dictionary() == before, "禁止覆盖已有同类成长")
	player = _player(6)
	while player.inventory.items().size() < player.inventory.capacity:
		player.inventory.add_reward(items.create("beginner_engine", {"instance_id": "filler" + str(player.inventory.items().size())}).value)
	_check(_execute(player, "source", "extract", true, 0).is_ok and _execute(player, "target", "transfer", true, 0).is_ok, "满包原位交换")
	print("Equipment memory transfer: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


## 创建有对应成长的战车以及空白目标和模块。
## [param kind] 当前模块类型。
## 返回独立测试聚合。
func _player(kind: int) -> Player:
	var player: Player = mapper.to_domain(fixture._state).value
	var id := "recruit_tank"
	if kind == 4:
		for profile: EquipmentMemoryRules.Profile in items.memory_rules.profiles.values():
			if profile.kind == 1 and kind in profile.extract_types and kind in profile.transfer_types: id = profile.definition_id; break
	var state := {"instance_id": "source", "bound": true}
	match kind:
		1: state["processing"] = {"increments": {"max_health": 1}}
		3: state["extra_attributes"] = {"levels": {"fluorite:3": 1}}
		4: state["extra_attributes"] = {"levels": {"brilliant:3": 1}}
		5: state["strengthening"] = {"level": 3}
	var source: VehicleEquipment = items.create(id, state).value
	if kind == 6:
		source.sockets.settle_open(0, true, "")
		source.sockets.inlay(0, items.create("bright_health_crystal", {"instance_id": "crystal", "bound": true, "crystal_cracks": 2}).value)
	source.durability -= 5
	_check(player.inventory.add_reward(source).is_ok, "来源")
	_check(player.inventory.add_reward(items.create(id, {"instance_id": "target"}).value).is_ok, "目标")
	var semantic: String = {1: "processing", 3: "fluorite", 4: "brilliant", 5: "strengthening", 6: "sockets"}[kind]
	_check(player.inventory.add_reward(items.create("equipment_memory_" + semantic, {"instance_id": "module"}).value).is_ok, "模块")
	_check(player.inventory.add_reward(items.create("equipment_memory_stabilizer", {"instance_id": "stabilizer", "quantity": 4}).value).is_ok, "稳压剂")
	return player


## 调用正式聚合操作，固定测试随机样本。
## [param player] 测试玩家。
## [param id] 装备身份。
## [param mode] 操作方式。
## [param stabilized] 是否使用稳压剂。
## [param roll] 随机样本。
## 返回操作结果。
func _execute(player: Player, id: String, mode: String, stabilized: bool, roll: float) -> DomainResult:
	return PlayerEquipmentMemoryActions.execute(player, items, id, "module", mode, stabilized, player.inventory.revision, true, roll)


## 累计行为断言。
## [param condition] 当前结果。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(label)
