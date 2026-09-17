extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0


## 验证十星真实交易、跨堆叠扣料、失败降级和重发隔离。
func _initialize() -> void:
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize().is_ok, "initialize")
	_mapper = PlayerStateMapper.new(_items)
	var player := _player(9)
	var engine: Equipment = player.inventory.find("inventory.spare_engine")
	var command := {"type": "strengthen_equipment", "instance_id": engine.instance_id,
		"material_id": engine.strengthening_profile.ultimate_material, "material_quantity": 9,
		"inventory_revision": player.inventory.revision, "price": 1, "star_level": 999}
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var result := _service.execute(state, command)
	_check(result.is_ok and before == state.to_dictionary(), "isolated candidate")
	if not result.is_ok: push_error(result.error_message); quit(1); return
	player = _mapper.to_domain(result.value.candidate).value
	engine = player.inventory.find(engine.instance_id)
	_check(engine.strengthening.level == 10 and engine.drive == 70 and engine.upgrade_level == 0 and engine.bound, "independent ten-star value")
	_check(player.inventory.currency == 900000, "original fee")
	_check(player.inventory.find(command.material_id).quantity == 11, "selected nine stones spent")
	_check(player.inventory.find(_items.strengthening_rules.additional_material).quantity == 2, "two additional catalysts spent")
	var total := 0
	for item: GameItem in player.inventory.items():
		if item.definition_id == engine.strengthening_profile.alloy_id: total += item.quantity
	_check(total == 300, "alloy consumed across stacks")
	_check(not _service.execute(result.value.candidate, command).is_ok, "replay rejected")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(result.value.panel_bundle) and current.inventory.find(engine.instance_id).strengthening.level == 10, "client receives stars")
	_check(not result.value.panel_bundle.equipment_strengthening.preview.can_execute, "ten stars terminal")
	var bought := _service.execute(result.value.candidate, {"type": "buy_equipment_strengthening_material", "definition_id": engine.strengthening_profile.ordinary_material,
		"quantity": 2, "inventory_revision": player.inventory.revision, "unit_price": 0})
	_check(bought.is_ok and bought.value.candidate.currency == 860000, "catalog purchase price")
	for level: int in [0, 4, 9]:
		player = _player(level)
		engine = player.inventory.find("inventory.spare_engine")
		var material := engine.strengthening_profile.ultimate_material if level == 9 else engine.strengthening_profile.ordinary_material
		var failed := PlayerEquipmentStrengtheningActions.execute(player, engine.instance_id, material, 1, player.inventory.revision, 0.99)
		_check(failed.is_ok and not failed.value.success and engine.strengthening.level == maxi(0, level - (2 if level == 9 else 1)), "source failure loss")
		_check(player.inventory.currency == 900000 and player.inventory.find(material).quantity == 19, "failure charged once")
	for problem: String in ["locked", "damaged", "installed", "stale", "material", "quantity", "currency", "missing"]:
		player = _player(0)
		engine = player.inventory.find("inventory.spare_engine")
		var id := engine.instance_id
		var material := engine.strengthening_profile.ordinary_material
		var quantity := 4
		var revision := player.inventory.revision
		if problem == "locked": engine.locked = true
		if problem == "damaged": engine.durability = 0
		if problem == "installed": id = player.vehicle.loadout.at(3).instance_id
		if problem == "stale": revision -= 1
		if problem == "material": material = _items.strengthening_rules.additional_material
		if problem == "quantity": quantity = 0
		if problem == "currency": player.inventory.currency = 0
		if problem == "missing":
			for item: GameItem in player.inventory.items():
				if item.definition_id == engine.strengthening_profile.alloy_id: item.locked = true
		before = _mapper.to_record(player).value.to_dictionary()
		var rejected := PlayerEquipmentStrengtheningActions.execute(player, id, material, quantity, revision, 0)
		_check(not rejected.is_ok and before == _mapper.to_record(player).value.to_dictionary(), "atomic " + problem)
	print("Equipment strengthening authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 构造含两次完整合金消耗的玩家，星级只写独立事实。
## [param level] 初始星级。
## 返回隔离聚合。
func _player(level: int) -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	var engine: Equipment = player.inventory.find("inventory.spare_engine")
	engine.strengthening.level = level
	engine.refresh_processed_stats()
	_give(player, engine.strengthening_profile.alloy_id, 600)
	_give(player, engine.strengthening_profile.ultimate_material if level == 9 else engine.strengthening_profile.ordinary_material, 20)
	_give(player, _items.strengthening_rules.additional_material, 4)
	return player


## 按原物品堆叠上限放入测试材料，验证大配方跨堆叠消费。
## [param player] 玩家。
## [param id] 材料定义。
## [param amount] 总数。
func _give(player: Player, id: String, amount: int) -> void:
	var remaining := amount
	var index := 0
	while remaining > 0:
		var item: GameItem = _items.create(id, {"instance_id": id if index == 0 else id + str(index), "bound": true}).value
		item.quantity = mini(remaining, item.max_stack)
		remaining -= item.quantity
		index += 1
		_check(player.inventory.add_reward(item).is_ok, "give")


## 累计断言。
## [param condition] 结果。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
