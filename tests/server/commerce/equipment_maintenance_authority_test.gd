extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0


## 验证维护材料原子消费、速修范围、裁缝经验切面及重放拒绝。
func _initialize() -> void:
	var rewards: RewardPipeline = RewardPolicyLoader.from_document({"schema_version": 1, "rules": [
		{"id": "tailoring_test", "channel": "experience", "skill_ids": ["tailoring"], "multiplier": 2}]}).value
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize(rewards).is_ok, "services")
	_mapper = PlayerStateMapper.new(_items)
	_test_regular()
	_test_quick()
	_test_failures()
	print("Equipment maintenance authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 构建隔离基地玩家。
## 返回测试聚合。
func _player() -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.map_id = "yian_harbor_hall_floor_1"
	player.inventory.currency = 100000
	return player


## 加入测试物品。
## [param player] 测试玩家。
## [param definition] 物品定义。
## [param id] 实例。
## [param amount] 数量。
## 返回物品。
func _give(player: Player, definition: String, id: String, amount: int = 1) -> GameItem:
	var item: GameItem = _items.create(definition, {"instance_id": id, "quantity": amount}).value
	_check(player.inventory.add_reward(item).is_ok, "give " + id)
	return item


## 使用真实付费引擎与服装，核对费用、保存和源于原字段的裁缝经验。
func _test_regular() -> void:
	var player := _player()
	var engine := _give(player, "glory_equipment_engine8_df38922e4b", "engine") as VehicleEngine
	engine.durability = 0
	engine.processing.apply(_items.processing_rules.profile(engine.definition_id), _items.processing_rules.material("item:material:02212ea88168"))
	for cost: Dictionary in engine.maintenance_profile.materials:
		_give(player, cost.definition_id, cost.definition_id, cost.quantity)
	var command := {"type": "maintain_equipment", "instance_id": engine.instance_id, "inventory_revision": player.inventory.revision,
		"currency": 0, "maximum_after": 1000000, "state_revision": -500}
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var result := _service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "transaction does not modify committed state")
	if not result.is_ok: return
	var restored: Player = _mapper.to_domain(result.value.candidate).value
	var after := restored.inventory.find("engine") as VehicleEngine
	_check(after.durability == 1247 and after.max_durability == 1247, "one percent maximum loss")
	_check(after.processing.bonus("drive") == 2, "processing retained")
	_check(restored.inventory.currency == 99960, "server fee")
	for cost: Dictionary in engine.maintenance_profile.materials:
		_check(restored.inventory.find(cost.definition_id) == null, "materials paid exactly")
	_check(not _service.execute(result.value.candidate, command).is_ok, "replay rejected")
	command.type = "query_equipment_maintenance"
	_check(not _service.execute(result.value.candidate, command).value.changed, "queries do not persist")
	player = _player()
	player.skills = SkillBook.new({"tailoring": 35})
	var shirt := _give(player, "male_sleeveless_shirt", "shirt") as Clothing
	shirt.durability = 1
	for cost: Dictionary in shirt.maintenance_profile.materials:
		_give(player, cost.definition_id, cost.definition_id, cost.quantity)
	result = _service.execute(_mapper.to_record(player).value, {"type": "maintain_equipment", "instance_id": "shirt", "inventory_revision": player.inventory.revision})
	_check(result.is_ok, "tailoring repair")
	restored = _mapper.to_domain(result.value.candidate).value
	_check(restored.skills.current_experience("tailoring") == 28, "repair experience uses reward multiplier")
	_check((restored.inventory.find("shirt") as Clothing).max_durability == 64, "clothing maximum unchanged")


## 群修只扣一箱，锁定目标跳过，离子箱只能修背包装备。
func _test_quick() -> void:
	var player := _player()
	player.vehicle.loadout.at(1).durability = 0
	player.vehicle.loadout.at(3).durability = 500
	var tool := _give(player, "maintenance_quickrepairbox2", "group", 2)
	tool.bound = true
	var result := _service.execute(_mapper.to_record(player).value, {"type": "quick_repair_equipment", "material_id": "group", "inventory_revision": player.inventory.revision})
	_check(result.is_ok, "group repair")
	var restored: Player = _mapper.to_domain(result.value.candidate).value
	_check(restored.vehicle.loadout.at(1).durability == 900 and restored.vehicle.loadout.at(3).durability == 900, "all repairable installed restored")
	_check(restored.vehicle.loadout.at(1).bound and restored.inventory.find("group").quantity == 1, "one box, binding retained")
	_give(restored, "maintenance_ionrepairbox1", "ion")
	var engine := restored.inventory.find("inventory.spare_engine") as Equipment
	engine.durability = 0
	_check(PlayerEquipmentMaintenanceActions.quick_repair(restored, engine.instance_id, "ion", restored.inventory.revision, _items.maintenance_rules).is_ok, "ion backpack repair")
	_check(engine.durability == 900 and restored.inventory.find("ion") == null, "ion consumed once")
	var coins := restored.inventory.currency
	result = _service.execute(_mapper.to_record(restored).value, {"type": "buy_maintenance_tool", "definition_id": "maintenance_elecrepairbox1", "quantity": 2, "inventory_revision": restored.inventory.revision, "price": 0})
	_check(result.is_ok and result.value.candidate.currency == coins - 1000, "tool purchase server pricing")


## 拒绝野外常规维护、满耐久、锁定和不正确工具范围，状态全部保持。
func _test_failures() -> void:
	for problem: String in ["field", "full", "locked", "wrong_scope", "missing", "stale"]:
		var player := _player()
		var engine := player.inventory.find("inventory.spare_engine") as Equipment
		engine.durability = 100
		_give(player, "maintenance_quickrepairbox1", "quick")
		if problem == "field": player.map_id = "buli_d03_field_zone"
		if problem == "full": engine.durability = engine.max_durability
		if problem == "locked": engine.locked = true
		var command := {"type": "quick_repair_equipment" if problem in ["wrong_scope", "missing"] else "maintain_equipment",
			"instance_id": engine.instance_id, "material_id": "missing" if problem == "missing" else "quick",
			"inventory_revision": player.inventory.revision - (1 if problem == "stale" else 0)}
		var state: PlayerStateRecord = _mapper.to_record(player).value
		var before := state.to_dictionary()
		_check(not _service.execute(state, command).is_ok and state.to_dictionary() == before, "atomic rejection " + problem)


## 记录业务边界断言。
## [param condition] 实际结果。
## [param message] 诊断信息。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
