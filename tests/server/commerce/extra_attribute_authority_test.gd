extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0


## 验证权威加工、失败扣费、重放防护、购买及客户端投影。
func _initialize() -> void:
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize().is_ok, "initialize")
	_mapper = PlayerStateMapper.new(_items)
	var player := _player()
	var command := {"type": "process_extra_attribute", "instance_id": "inventory.spare_engine", "material_id": "extra_ratefluorite",
		"inventory_revision": player.inventory.revision, "points": 99999, "price": 0, "success_chance": 1}
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var processed := _service.execute(state, command)
	_check(processed.is_ok and state.to_dictionary() == before, "isolated candidate")
	if not processed.is_ok: quit(1); return
	player = _mapper.to_domain(processed.value.candidate).value
	var engine: Equipment = player.inventory.find(command.instance_id)
	_check(engine.extra_attributes.level("fluorite:5") == 1 and engine.drive == 20 and engine.bound, "authority increment and binding")
	_check(player.inventory.currency == 900000 and player.inventory.find(command.material_id).quantity == 2, "exact cost")
	_check(not _service.execute(processed.value.candidate, command).is_ok, "replay rejected")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(processed.value.panel_bundle), "client bundle")
	_check(current.inventory.find(command.instance_id).stat("movement_speed") == 1, "client derived stat agrees")
	command.type = "query_extra_attributes"
	command.state_revision = -999
	var query := _service.execute(processed.value.candidate, command)
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.extra_attributes.preview.before == 1, "query ignores unrelated save revision")
	_check(query.value.panel_bundle.extra_attributes.offers.size() == 12, "twelve material offers")
	var purchase := {"type": "buy_extra_attribute_material", "definition_id": "extra_ratefluorite", "quantity": 2,
		"inventory_revision": player.inventory.revision, "price": 1}
	var bought := _service.execute(processed.value.candidate, purchase)
	_check(bought.is_ok and bought.value.candidate.currency == 860000, "server purchase price")
	_check(not _service.execute(bought.value.candidate, purchase).is_ok, "purchase replay")
	for level: int in [10, 20]:
		player = _player()
		engine = player.inventory.find(command.instance_id)
		engine.extra_attributes = ExtraAttributes.restore({"levels": {"fluorite:5": level}}).value
		var failed := PlayerExtraAttributeActions.execute(player, engine.instance_id, command.material_id, player.inventory.revision, 0.99)
		_check(failed.is_ok and not failed.value.success, "failure processed")
		_check(engine.extra_attributes.level("fluorite:5") == (10 if level == 10 else 19), "failure band outcome")
		_check(player.inventory.currency == 900000 and player.inventory.find(command.material_id).quantity == 2, "failure paid exactly once")
	for problem: String in ["locked", "damaged", "locked_material", "missing", "currency", "wrong", "stale", "installed", "maximum", "roll"]:
		player = _player()
		engine = player.inventory.find(command.instance_id)
		var material_id := String(command.material_id)
		var revision := player.inventory.revision
		var id := engine.instance_id
		var roll := 0.5
		if problem == "locked": engine.locked = true
		if problem == "damaged": engine.durability = 0
		if problem == "locked_material": player.inventory.find(material_id).locked = true
		if problem == "missing": player.inventory.find(_items.extra_attribute_rules.material(material_id).materials[0].definition_id).quantity = 1
		if problem == "currency": player.inventory.currency = 99999
		if problem == "wrong": material_id = "unknown"
		if problem == "stale": revision -= 1
		if problem == "installed": id = player.vehicle.loadout.at(3).instance_id
		if problem == "maximum": engine.extra_attributes = ExtraAttributes.restore({"levels": {"fluorite:5": 30}}).value
		if problem == "roll": roll = NAN
		before = _mapper.to_record(player).value.to_dictionary()
		var rejected := PlayerExtraAttributeActions.execute(player, id, material_id, revision, roll)
		_check(not rejected.is_ok and before == _mapper.to_record(player).value.to_dictionary(), "atomic reject " + problem)
	print("Extra attribute authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 创建拥有三次加工材料的隔离聚合。
## 返回可加工的玩家。
func _player() -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	var material_id := "extra_ratefluorite"
	var requirements: Array[Dictionary] = _items.extra_attribute_rules.material(material_id).materials.duplicate(true)
	requirements.append({"definition_id": material_id, "quantity": 1})
	for cost: Dictionary in requirements:
		var item := _items.create(cost.definition_id, {"instance_id": cost.definition_id, "quantity": 3 if cost.definition_id == material_id else int(cost.quantity) * 2, "bound": true})
		_check(item.is_ok and player.inventory.add_reward(item.value).is_ok, "give cost")
	return player


## 累计事务断言。
## [param condition] 检查结果。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
