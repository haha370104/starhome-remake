extends SceneTree

var _checks := 0
var _failures := 0


## 验证权威定价、只读预览、随机边界和不可伪造的加工后果。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	var service := AuthoritativeCommerceService.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "initialization")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	player.inventory.add_reward(items.create("beginner_engine", {"instance_id": "target", "processing": {"increments": {"drive": 3}}}).value)
	player.inventory.add_reward(items.create("equipment_forging_drive", {"instance_id": "chip", "quantity": 3}).value)
	var requirement: Dictionary = items.forging_rules.channels[2].requirements[0]
	player.inventory.add_reward(items.create(requirement.definition_id, {"instance_id": "alloy", "quantity": 100}).value)
	var state: PlayerStateRecord = mapper.to_record(player).value
	var before := state.to_dictionary()
	var command := {"type": "query_equipment_forging", "instance_id": "target", "material_id": "chip", "material_quantity": 3,
		"inventory_revision": state.inventory_revision, "confirm_processing_loss": true, "forging": {"extensions": {"2": 50}}, "price": 0, "roll": 0}
	var queried := service.execute(state, command)
	_check(queried.is_ok and not queried.value.changed and state.to_dictionary() == before, "read only")
	var preview: Dictionary = queried.value.panel_bundle.equipment_forging.preview
	_check(preview.can_execute and preview.chance == 0.95 and preview.text.contains("清除全部普通加工"), "original probability and risk")
	_check(not preview.has("success_candidate") and not preview.has("failure_candidate"), "safe network payload")
	_check(queried.value.panel_bundle.equipment_forging.offers.size() == 10, "eight chips two missing alloys")
	command.type = "forge_equipment"
	command.confirm_processing_loss = false
	_check(not service.execute(state, command).is_ok, "explicit confirmation")
	command.confirm_processing_loss = true
	var result := service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "isolated transaction")
	player = mapper.to_domain(result.value.candidate).value
	var engine := player.inventory.find("target") as Equipment
	_check(engine.processing.bonus("drive") == 0 and engine.forging.extensions.get(2, 0) in [0, 1], "no forged extensions")
	_check(player.inventory.currency == 900000 and player.inventory.count_definition(requirement.definition_id) == 0, "exact fee and materials")
	_check(not service.execute(result.value.candidate, command).is_ok, "no replay")
	var bought := service.execute(result.value.candidate, {"type": "buy_equipment_forging_material", "definition_id": "forging_zirconium_scandium_alloy", "quantity": 100, "inventory_revision": player.inventory.revision, "price": 0})
	_check(bought.is_ok and bought.value.candidate.currency == 877000, "supply uses original price")
	_check(not service.execute(result.value.candidate, {"type": "buy_equipment_forging_material", "definition_id": "iron_piece", "quantity": 1, "inventory_revision": player.inventory.revision}).is_ok, "shop whitelist")
	print("Equipment forging authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 汇总服务断言。
## [param condition] 预期条件。
## [param message] 故障说明。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
