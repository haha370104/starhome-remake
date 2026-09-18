extends SceneTree

var checks := 0
var failures := PackedStringArray()
var items := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var service := AuthoritativeCommerceService.new()
var mapper: PlayerStateMapper


## 验证颜色供给、费用来源、真实转移销毁和失败原子性。
func _initialize() -> void:
	_check(items.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "dependencies")
	mapper = PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 10000000)
	player.amethyst = AmethystWallet.new(1000)
	var state: PlayerStateRecord = mapper.to_record(player).value
	for offer_id: String in items.sama_rules.offers:
		var offer := items.sama_rules.offers[offer_id]
		var quantity := 1 if items.sama_rules.profiles.has(offer.definition_id) else 999
		var before := state.to_dictionary()
		var bought := service.execute(state, {"type":"buy_sama", "definition_id":offer_id, "quantity":quantity, "inventory_revision":state.inventory_revision, "price":0, "color":3})
		_check(bought.is_ok and state.to_dictionary() == before, "isolated purchase")
		if not bought.is_ok:
			push_error(bought.error_message)
			quit(1)
			return
		_check(bought.value.candidate.currency == state.currency - quantity * offer.unit_price, "server supplied price")
		state = bought.value.candidate
	var query := service.execute(state, {"type":"query_sama"})
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.sama.offers.size() == 19, "read only complete supply")
	player = mapper.to_domain(state).value
	var bodies: Array[VehicleEquipment] = []
	for item: GameItem in player.inventory.items():
		if item is VehicleEquipment and item.sama_profile != null: bodies.append(item)
	_check(bodies.size() == 16, "four original colors per part")
	for item: VehicleEquipment in bodies:
		for mode: String in ["growth", "quality"]:
			var command := {"type":"query_sama", "mode":mode, "instance_id":item.instance_id, "inventory_revision":state.inventory_revision, "confirmed":true, "growth":10, "costs":[]}
			var before := state.to_dictionary()
			query = service.execute(state, command)
			var preview: Dictionary = query.value.panel_bundle.sama.preview
			_check(preview.can_execute and not preview.has("candidate") and state.to_dictionary() == before and not query.value.changed, "nonmutating quote")
			command.type = "change_sama"
			command.confirmed = false
			_check(not service.execute(state, command).is_ok, "confirmation")
			command.confirmed = true
			var changed := service.execute(state, command)
			_check(changed.is_ok and state.to_dictionary() == before, "candidate isolation")
			if not changed.is_ok: continue
			_check(not service.execute(changed.value.candidate, command).is_ok, "stale replay")
			var old_player: Player = mapper.to_domain(state).value
			var next: Player = mapper.to_domain(changed.value.candidate).value
			for cost: Dictionary in preview.costs:
				_check(old_player.inventory.count_definition(cost.definition_id) - next.inventory.count_definition(cost.definition_id) == cost.quantity, "exact cost")
			state = changed.value.candidate
		var grown: VehicleEquipment = mapper.to_domain(state).value.inventory.find(item.instance_id)
		_check(grown.sama.growth == 1 and grown.sama.quality == 1 and grown.bound, "one stage and quality; binding from core")
	player = mapper.to_domain(state).value
	var donor: VehicleEquipment = player.inventory.find(bodies[0].instance_id)
	var target: VehicleEquipment = player.inventory.find(bodies[-1].instance_id)
	var transfer := {"type":"change_sama", "mode":"transfer", "instance_id":target.instance_id, "material_id":donor.instance_id, "inventory_revision":state.inventory_revision, "confirmed":true}
	var before := state.to_dictionary()
	var done := service.execute(state, transfer)
	_check(done.is_ok and state.to_dictionary() == before, "cross-part transfer candidate")
	if done.is_ok:
		var moved: Player = mapper.to_domain(done.value.candidate).value
		_check(moved.inventory.find(donor.instance_id) == null and moved.inventory.find(target.instance_id).sama.color == 3, "destroy donor, keep target color")
		_check(moved.amethyst.balance() == 0 and moved.inventory.find(target.instance_id).bound, "exact amethyst and binding")
		_check(not service.execute(done.value.candidate, transfer).is_ok, "transfer cannot replay")
	for bad: Variant in [1.5, "1", true, -1, 0]:
		_check(not service.execute(state, {"type":"buy_sama", "definition_id":"sama_dynamic_core", "quantity":bad, "inventory_revision":state.inventory_revision}).is_ok, "invalid quantity")
	_check(not service.execute(state, {"type":"buy_sama", "definition_id":donor.definition_id, "inventory_revision":state.inventory_revision}).is_ok, "base id cannot bypass offer color")
	for failure_kind: String in ["wallet", "same", "locked", "broken", "downgrade_color"]:
		var candidate: Player = mapper.to_domain(state).value
		var from_item := candidate.inventory.find(donor.instance_id) as VehicleEquipment
		var to_item := candidate.inventory.find(target.instance_id) as VehicleEquipment
		var source_id := donor.instance_id
		match failure_kind:
			"wallet": candidate.amethyst = AmethystWallet.new(999)
			"same": source_id = target.instance_id
			"locked": from_item.locked = true
			"broken": to_item.durability = 0
			"downgrade_color":
				from_item.sama.color = 3
				to_item.sama.color = 0
		before = mapper.to_record(candidate).value.to_dictionary()
		_check(not PlayerSamaActions.execute(candidate, items, to_item.instance_id, "transfer", source_id, candidate.inventory.revision, true).is_ok, "reject " + failure_kind)
		_check(mapper.to_record(candidate).value.to_dictionary() == before, "atomic " + failure_kind)
	print("Sama authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 汇总权威交易断言。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
