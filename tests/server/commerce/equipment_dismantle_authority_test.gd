extends SceneTree

var _checks := 0
var _failures := 0


## 正式服务不相信客户端品质、概率、费用和返还材料，确认后只消费当前真实实例。
func _initialize() -> void:
	var items := ItemCatalog.new()
	var fixture := PlayerPanelServiceFixture.new()
	var service := AuthoritativeCommerceService.new()
	_check(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "initialize")
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	var target := "glory_equipment_tank7_6dce9d1c52"
	player.inventory = Inventory.new(40, 0, 1000)
	player.inventory.add_reward(items.create(target, {"instance_id": "source"}).value)
	var state: PlayerStateRecord = mapper.to_record(player).value
	var command := {"type": "dismantle_equipment", "instance_id": "source", "inventory_revision": state.inventory_revision,
		"confirm_destruction": true, "quality": 3, "currency": 0, "probability": 1.0, "outputs": [{"definition_id": "iron_piece", "quantity": 999}]}
	_check(not service.execute(state, command).is_ok, "cannot forge white quality")
	player.inventory.find("source").quality.grade = 1
	state = mapper.to_record(player).value
	var before := state.to_dictionary()
	var query := command.duplicate(true)
	query.type = "query_equipment_dismantle"
	var result := service.execute(state, query)
	_check(result.is_ok and not result.value.changed and state.to_dictionary() == before, "read only preview")
	var preview: Dictionary = result.value.panel_bundle.equipment_dismantle.preview
	_check(preview.can_execute and preview.text.contains("无材料返还") and preview.text.contains("永久消失"), "visible risk")
	_check(not preview.has("plans") and JSON.stringify(result.value.panel_bundle).length() > 0, "wire boundary")
	command.confirm_destruction = false
	_check(not service.execute(state, command).is_ok, "requires confirmation")
	command.confirm_destruction = true
	result = service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "isolated candidate")
	_check(result.value.candidate.currency == 800, "authoritative cost")
	var next: Player = mapper.to_domain(result.value.candidate).value
	_check(next.inventory.find("source") == null and next.inventory.count_definition("iron_piece") == 0, "cannot forge output")
	var outcome: EquipmentDismantleRules.Outcome = items.dismantle_rules.profiles[target].outcomes[int(result.value.operation.outcome_index)]
	for material: Dictionary in outcome.materials:
		_check(next.inventory.count_definition(material.definition_id) == int(material.quantity), "original table output")
	_check(not service.execute(result.value.candidate, command).is_ok, "duplicate request")
	print("Equipment dismantle authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 记录事务断言。
## [param condition] 当前结果。
## [param message] 故障标签。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
