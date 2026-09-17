extends SceneTree

var checks := 0
var failures := PackedStringArray()
var items := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var service := AuthoritativeCommerceService.new()
var mapper: PlayerStateMapper


## 用正式商贸路由验证所有晶源体命令、可信报价与只读预览。
func _initialize() -> void:
	_check(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "dependencies")
	mapper = PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 10000000)
	var state: PlayerStateRecord = mapper.to_record(player).value
	for id: String in items.crystal_source_rules.offers:
		var before := state.to_dictionary()
		var bought := service.execute(state, {"type": "buy_crystal_source", "definition_id": id, "quantity": 1, "inventory_revision": state.inventory_revision, "price": 0})
		_check(bought.is_ok and state.to_dictionary() == before, "isolated purchase " + id)
		_check(bought.value.candidate.currency == state.currency - items.crystal_source_rules.offers[id], "server price " + id)
		state = bought.value.candidate
	var queried := service.execute(state, {"type": "query_crystal_source"})
	_check(queried.is_ok and not queried.value.changed and queried.value.panel_bundle.crystal_source.offers.size() == 11, "all supplies read only")
	player = mapper.to_domain(state).value
	var equipment: VehicleEquipment
	var core: CrystalSourceCore
	for item: GameItem in player.inventory.items():
		if item is VehicleEquipment and item.equipment_location == 28: equipment = item
		if item is CrystalSourceCore and item.profile.color == "red": core = item
	core.cracks = 2
	core.bound = true
	state = mapper.to_record(player).value
	var command := {"type": "query_crystal_source", "instance_id": equipment.instance_id, "material_id": core.instance_id, "mode": "inlay", "index": 1, "inventory_revision": state.inventory_revision}
	queried = service.execute(state, command)
	_check(queried.is_ok and queried.value.panel_bundle.crystal_source.preview.can_execute, "inlay preview")
	_check(JSON.parse_string(JSON.stringify(queried.value.panel_bundle)) is Dictionary, "snapshot JSON")
	command.type = "inlay_crystal_source"
	var inlaid := service.execute(state, command)
	_check(inlaid.is_ok, "authoritative inlay")
	_check(not service.execute(inlaid.value.candidate, command).is_ok, "replay rejected")
	state = inlaid.value.candidate
	command.type = "query_crystal_source"
	command.mode = "extract"
	queried = service.execute(state, command)
	_check(queried.value.panel_bundle.crystal_source.preview.text.contains("2 → 3"), "extraction consequence")
	command.type = "extract_crystal_source"
	command.inventory_revision = state.inventory_revision
	var extracted := service.execute(state, command)
	_check(extracted.is_ok, "authoritative extract")
	state = extracted.value.candidate
	player = mapper.to_domain(state).value
	var quote := PlayerCrystalSourceActions.growth_quote(player, items, equipment.instance_id, "quality", false)
	for cost: Dictionary in quote.value.requirements:
		var remaining := int(cost.quantity) - player.inventory.count_consumable_definition(cost.definition_id)
		while remaining > 0:
			var material: GameItem = items.create(cost.definition_id, {"instance_id": CrystalSourceService.new_id(), "quantity": 1}).value
			material.quantity = mini(remaining, material.max_stack)
			remaining -= material.quantity
			player.inventory.add_reward(material)
	state = mapper.to_record(player).value
	command = {"type": "query_crystal_source", "instance_id": equipment.instance_id, "mode": "quality", "confirmed": true, "inventory_revision": state.inventory_revision,
		"quality": 15, "chance": 1, "roll": 0, "currency_cost": 0}
	queried = service.execute(state, command)
	var preview: Dictionary = queried.value.panel_bundle.crystal_source.preview
	_check(preview.can_execute and preview.after == 1 and preview.chance == 1.0 and not preview.has("success_candidate"), "growth ignores forged result")
	command.type = "grow_crystal_source"
	var grown := service.execute(state, command)
	_check(grown.is_ok and mapper.to_domain(grown.value.candidate).value.inventory.find(equipment.instance_id).crystal_source.quality == 1, "growth settled by authority")
	for invalid: Variant in [1.5, -1, "2", true]:
		var bad := {"type": "buy_crystal_source", "definition_id": core.definition_id, "quantity": invalid, "inventory_revision": state.inventory_revision}
		_check(not service.execute(state, bad).is_ok, "fractional quantity denied")
	_check(not service.execute(state, {"type": "buy_crystal_source", "definition_id": "recruit_tank", "quantity": 1, "inventory_revision": state.inventory_revision}).is_ok, "supply whitelist")
	_check(not service.execute(state, {"type": "buy_crystal_source", "definition_id": equipment.definition_id, "quantity": 2, "inventory_revision": state.inventory_revision}).is_ok, "unique equipment quantity")
	_check(not service.execute(state, {"type": "query_crystal_source", "index": 0.5}).is_ok, "fractional socket denied")
	player = mapper.to_domain(grown.value.candidate).value
	player.inventory.add_reward(items.create("crystal_source_core_black_4", {"instance_id": "compose.input", "quantity": 5, "crystal_source_cracks": 2}).value)
	player.inventory.add_reward(items.create("crystal_source_core_stabilizer", {"instance_id": "compose.stabilizers", "quantity": 6}).value)
	state = mapper.to_record(player).value
	command = {"type": "query_crystal_source", "mode": "compose", "material_id": "compose.input", "stabilizers": 7, "inventory_revision": state.inventory_revision}
	queried = service.execute(state, command)
	preview = queried.value.panel_bundle.crystal_source.preview
	_check(preview.can_execute and preview.chance == 1.0 and not preview.has("success_plan") and not preview.has("failure_plan"), "compose preview contains no mutable plans")
	command.type = "compose_crystal_source"
	_check(not service.execute(state, command).is_ok, "composition confirmation required")
	command.confirmed = true
	var composed := service.execute(state, command)
	_check(composed.is_ok and composed.value.operation.success, "authoritative composition")
	player = mapper.to_domain(composed.value.candidate).value
	_check(player.inventory.count_definition("crystal_source_core_black_5") == 1 and player.inventory.find("compose.input") == null, "five inputs one output")
	print("Crystal source authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总可定位的服务断言。
## [param condition] 断言条件。[param message] 故障描述。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
