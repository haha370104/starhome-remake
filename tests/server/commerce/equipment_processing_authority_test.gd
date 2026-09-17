extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0


## 验证加工实际结算、失败原子性、重放防护以及战斗属性读取。
func _initialize() -> void:
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize().is_ok, "initialize")
	_mapper = PlayerStateMapper.new(_items)
	_test_transaction()
	_test_rejections()
	print("Equipment processing authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 创建具备引擎加工材料的隔离玩家。
## 返回可加工玩家。
func _player() -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.skills = SkillBook.new({"processing": 1000, "driving": 1000})
	var engine: Equipment = player.inventory.find("inventory.spare_engine")
	var profile := _items.processing_rules.profile(engine.definition_id)
	for cost: Dictionary in profile.attributes.drive.materials:
		_give(player, cost.definition_id, cost.quantity * 2)
	_give(player, "item:material:02212ea88168", 2)
	return player


## 增加测试材料，使用定义作为稳定测试实例标识。
## [param player] 测试玩家。
## [param definition] 材料定义。
## [param quantity] 数量。
func _give(player: Player, definition: String, quantity: int) -> void:
	_check(player.inventory.add_reward(_items.create(definition, {"instance_id": definition, "quantity": quantity}).value).is_ok, "give")


## 通过权威服务加工，忽略伪造增量和价格，装备状态与消耗只发生一次。
func _test_transaction() -> void:
	var player := _player()
	var target := player.inventory.find("inventory.spare_engine") as VehicleEngine
	target.sockets.settle_open(0, true, "none")
	var crystal: VehicleCrystal = _items.create("bright_health_crystal", {"crystal_cracks": 2}).value
	target.sockets.inlay(0, crystal)
	player.inventory.find("item:material:02212ea88168").bound = true
	var command := {"type": "process_equipment_attribute", "instance_id": target.instance_id,
		"material_id": "item:material:02212ea88168", "inventory_revision": player.inventory.revision,
		"points": 1000000, "price": 0, "success_chance": 1, "state_revision": -999}
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var result := _service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "isolated settlement")
	if not result.is_ok:
		push_error(result.error_message)
		return
	var restored: Player = _mapper.to_domain(result.value.candidate).value
	var engine := restored.inventory.find(target.instance_id) as VehicleEngine
	_check(engine.drive == 22 and engine.bound, "authoritative increment and binding")
	_check(engine.sockets.slot_at(0).cracks == 2 and engine.upgrade_level == 0, "unrelated state preserved")
	_check(restored.inventory.find(command.material_id).quantity == 1, "special consumed once")
	for cost: Dictionary in _items.processing_rules.profile(engine.definition_id).attributes.drive.materials:
		_check(restored.inventory.find(cost.definition_id).quantity == int(cost.quantity), "ordinary costs exact")
	_check(not _service.execute(result.value.candidate, command).is_ok, "replay rejected")
	command.type = "query_equipment_processing"
	var query := _service.execute(result.value.candidate, command)
	_check(query.is_ok and not query.value.changed, "query independent of autosave version")
	_check(query.value.panel_bundle.equipment_processing.preview.before == 22, "preview reflects persisted value")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(result.value.panel_bundle), "client applies")
	_check((current.inventory.find(target.instance_id) as VehicleEngine).drive == 22, "client stats agree")
	_check(_items.create("item:material:02212ea88168", {}).value is EquipmentProcessingMaterial, "material semantic type")
	_check(_items.create("item:material:02212ea88168", {}).value.copy_stack("copy", 1) is EquipmentProcessingMaterial, "split keeps type")
	var failed := _player()
	var failed_target: Equipment = failed.inventory.find(target.instance_id)
	failed_target.processing_rules.success_chance = 0.0
	var failure := PlayerEquipmentProcessingActions.execute(failed, target.instance_id, command.material_id, failed.inventory.revision, 0.1)
	_check(failure.is_ok and not failure.value.success and failed_target.processing.bonus("drive") == 0, "configured failure preserves stats")
	_check(failed.inventory.find(command.material_id).quantity == 1, "failure consumes material once")
	failed_target.processing_rules.success_chance = 1.0


## 对失败条件逐项验证不扣料、不改变装备或背包版本。
func _test_rejections() -> void:
	for problem: String in ["locked", "damaged", "skill", "missing", "wrong", "stale", "installed", "maximum"]:
		var player := _player()
		var target := player.inventory.find("inventory.spare_engine") as VehicleEngine
		var material_id := "item:material:02212ea88168"
		var revision := player.inventory.revision
		if problem == "locked": target.locked = true
		if problem == "damaged": target.durability = 0
		if problem == "skill": player.skills = SkillBook.new({"processing": 0})
		if problem == "missing": player.inventory.find(_items.processing_rules.profile(target.definition_id).attributes.drive.materials[0].definition_id).quantity = 1
		if problem == "wrong": material_id = "no_such_item"
		if problem == "stale": revision -= 1
		var id := target.instance_id
		if problem == "installed": id = player.vehicle.loadout.at(3).instance_id
		if problem == "maximum":
			for index: int in 4:
				target.processing.apply(_items.processing_rules.profile(target.definition_id), _items.processing_rules.material(material_id))
		var before: Dictionary = _mapper.to_record(player).value.to_dictionary()
		var processed := target.processing.to_dictionary()
		var result := PlayerEquipmentProcessingActions.execute(player, id, material_id, revision, 0.5)
		_check(not result.is_ok, "reject " + problem)
		_check(_mapper.to_record(player).value.to_dictionary() == before and target.processing.to_dictionary() == processed, "atomic " + problem)


## 记录断言。
## [param condition] 是否符合预期。
## [param message] 诊断信息。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
