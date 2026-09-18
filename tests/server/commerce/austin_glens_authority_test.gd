extends SceneTree

var checks := 0
var failures := PackedStringArray()
var items := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var service := AuthoritativeCommerceService.new()
var mapper: PlayerStateMapper


## 用真实权威商贸链路验证全部成长、永久符文、付款回滚和协议伪造拒绝。
func _initialize() -> void:
	_check(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "dependencies")
	mapper = PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 10000000)
	var state: PlayerStateRecord = mapper.to_record(player).value
	for id: String in items.austin_rules.offers:
		var amount := 1 if items.austin_rules.profiles.has(id) else 99
		var before := state.to_dictionary()
		var result := service.execute(state, {"type": "buy_austin_glens", "definition_id": id, "quantity": amount, "inventory_revision": state.inventory_revision, "price": 0})
		_check(result.is_ok and state.to_dictionary() == before, "isolated supply purchase")
		if not result.is_ok:
			push_error(result.error_message)
			quit(1)
			return
		_check(result.value.candidate.currency == state.currency - items.austin_rules.offers[id] * amount, "server price")
		state = result.value.candidate
	var queried := service.execute(state, {"type": "query_austin_glens"})
	_check(queried.is_ok and not queried.value.changed and queried.value.panel_bundle.austin_glens.offers.size() == 19, "read-only all supplies")
	for id: String in items.austin_rules.profiles:
		player = mapper.to_domain(state).value
		var equipment: VehicleEquipment
		for item: GameItem in player.inventory.items():
			if item.definition_id == id: equipment = item
		for mode: String in AustinGlensRules.OPERATIONS:
			var command := {"type": "query_austin_glens", "mode": mode, "instance_id": equipment.instance_id, "index": 0, "confirmed": true, "inventory_revision": state.inventory_revision, "after": 10, "costs": []}
			if mode == "inlay":
				var rune := items.austin_rules.rune_at(equipment.equipment_location, 0)
				for item: GameItem in mapper.to_domain(state).value.inventory.items():
					if item.definition_id == rune.definition_id: command.material_id = item.instance_id
			var before := state.to_dictionary()
			queried = service.execute(state, command)
			var preview: Dictionary = queried.value.panel_bundle.austin_glens.preview
			_check(state.to_dictionary() == before and not queried.value.changed and not preview.has("candidate"), "query cannot mutate or leak domain objects")
			_check(JSON.parse_string(JSON.stringify(queried.value.panel_bundle)) is Dictionary, "safe snapshot")
			command.type = "change_austin_glens"
			if mode == "additional" and equipment.austin_profile.effect.begins_with("pvp"):
				_check(not preview.can_execute and not service.execute(state, command).is_ok and state.to_dictionary() == before, "PvP growth unavailable without charge")
				continue
			_check(preview.can_execute, "valid growth preview " + mode)
			command.confirmed = false
			_check(not service.execute(state, command).is_ok, "confirmation required")
			command.confirmed = true
			var changed := service.execute(state, command)
			_check(changed.is_ok and state.to_dictionary() == before, "candidate-only mutation " + mode)
			if not changed.is_ok: continue
			_check(not service.execute(changed.value.candidate, command).is_ok, "stale replay rejected")
			var next_player: Player = mapper.to_domain(changed.value.candidate).value
			var previous_player: Player = mapper.to_domain(state).value
			for cost: Dictionary in preview.costs:
				_check(previous_player.inventory.count_definition(cost.definition_id) - next_player.inventory.count_definition(cost.definition_id) == cost.quantity, "exact material conservation")
			state = changed.value.candidate
		var grown := mapper.to_domain(state).value.inventory.find(equipment.instance_id) as VehicleEquipment
		_check(grown.austin_glens.color == 1 and grown.austin_glens.stage == 1 and grown.austin_glens.base == 1 and grown.austin_glens.blessed, "one step only; forged target ignored")
		_check(not grown.austin_glens.slots[0].rune_id.is_empty() and not grown.austin_glens.slots[1].opened, "correct slot only")
	player = mapper.to_domain(state).value
	var target: VehicleEquipment
	for item: GameItem in player.inventory.items():
		if item is VehicleEquipment and item.austin_profile != null: target = item
	var command := {"type": "change_austin_glens", "mode": "stage", "instance_id": target.instance_id, "confirmed": true, "inventory_revision": state.inventory_revision}
	for bad: Variant in [1.5, "2", true, -1]:
		var request := command.duplicate(true)
		request.index = bad
		_check(not service.execute(state, request).is_ok, "invalid index")
		request = {"type": "buy_austin_glens", "definition_id": "austin_space_crystal", "quantity": bad, "inventory_revision": state.inventory_revision}
		_check(not service.execute(state, request).is_ok, "invalid quantity")
	_check(not service.execute(state, {"type": "buy_austin_glens", "definition_id": "recruit_tank", "inventory_revision": state.inventory_revision}).is_ok, "whitelist")
	target.locked = true
	var before := mapper.to_record(player).value.to_dictionary() as Dictionary
	_check(not PlayerAustinActions.execute(player, items, target.instance_id, "stage", 0, "", player.inventory.revision, true).is_ok and mapper.to_record(player).value.to_dictionary() == before, "locked direct aggregate unchanged")
	target.locked = false
	player.inventory.restore_items([target])
	before = mapper.to_record(player).value.to_dictionary()
	_check(not PlayerAustinActions.execute(player, items, target.instance_id, "stage", 0, "", player.inventory.revision, true).is_ok and mapper.to_record(player).value.to_dictionary() == before, "missing materials no partial growth")
	print("Austin authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录服务断言及失败场景。
## [param condition] 验证结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
