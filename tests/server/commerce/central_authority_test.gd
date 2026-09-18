extends SceneTree

var checks := 0
var failures := PackedStringArray()
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var service := AuthoritativeCommerceService.new()
var mapper: PlayerStateMapper
var state: PlayerStateRecord


## 验证全部供给、芯片消费、核心进化与六件十八阶升级均走隔离权威事务。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok and service.initialize().is_ok, "initialize")
	mapper = PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 10000000)
	state = mapper.to_record(player).value
	for id: String in catalog.central_rules.offers:
		var quantity := int(catalog.definition(id).get("max_stack", 1))
		var before := state.to_dictionary()
		var bought := service.execute(state, {"type":"buy_central", "definition_id":id, "quantity":quantity, "inventory_revision":state.inventory_revision, "price":0, "grade":18, "evolved":true})
		_check(bought.is_ok and state.to_dictionary() == before, "purchase candidate isolation")
		if not bought.is_ok:
			push_error(bought.error_message)
			quit(1)
			return
		_check(bought.value.candidate.currency == state.currency - quantity * catalog.central_rules.offers[id], "server price only")
		state = bought.value.candidate
	var query := service.execute(state, {"type":"query_central"})
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.central_workshop.offers.size() == 31, "complete read only supply")
	_check(query.value.panel_bundle.central.grades.gun == 0 and query.value.panel_bundle.central_workshop.chips.size() == 6, "permanent state separate from workshop")
	var before := state.to_dictionary()
	_check(not _change(_instance(catalog.central_rules.evolution_material)).is_ok and state.to_dictionary() == before, "evolution requires all six")
	for id: String in CentralRules.CHIP_IDS:
		before = state.to_dictionary()
		_check(not _change(_instance("central_%s_module_3" % id)).is_ok and state.to_dictionary() == before, "upgrade cannot activate")
		for grade in [1,2,3]: _use(_instance("central_%s_module_%d" % [id, grade]))
	_check(state.central.core_grade() == 3 and not state.central.evolved, "all three not yet evolved")
	_use(_instance(catalog.central_rules.evolution_material))
	_check(state.central.evolved, "permanent evolved core")
	for id: String in catalog.central_rules.profiles:
		var identity := _instance(id)
		for grade in 18:
			var old_player: Player = mapper.to_domain(state).value
			var material := catalog.central_rules.growth_materials[floori(grade / 3.0)]
			var count := old_player.inventory.count_definition(material)
			_use(identity)
			var current: Player = mapper.to_domain(state).value
			_check(current.inventory.find(identity).central_growth.grade == grade + 1, "exactly one stage")
			_check(current.inventory.count_definition(material) == count - 1, "one original material per stage")
		before = state.to_dictionary()
		_check(not _change(identity).is_ok and state.to_dictionary() == before, "eighteen cap atomic")
	for invalid: Variant in [1.5, "1", true, -1, 0, 21]:
		_check(not service.execute(state, {"type":"buy_central", "definition_id":"central_syancrystal", "quantity":invalid, "inventory_revision":state.inventory_revision}).is_ok, "bad quantity")
	_check(not service.execute(state, {"type":"buy_central", "definition_id":"central_gun_module_1", "quantity":2, "inventory_revision":state.inventory_revision}).is_ok, "unique item quantity")
	_check(not service.execute(state, {"type":"buy_central", "definition_id":"iron_piece", "inventory_revision":state.inventory_revision}).is_ok, "offer whitelist")
	_failure_paths()
	print("Central authority: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 针对缺料、锁定、伪造确认和已进化重复使用验证原对象保持不变。
func _failure_paths() -> void:
	var player: Player = mapper.to_domain(state).value
	player.inventory = Inventory.new(40, 0, 0)
	var item: VehicleEquipment = catalog.create("central_flamefire", {"instance_id":"missing-material"}).value
	player.inventory.add_reward(item)
	var snapshot := player.inventory.revision
	_check(not PlayerCentralActions.execute(player, catalog, item.instance_id, snapshot, true).is_ok and item.central_growth.grade == 0 and player.inventory.revision == snapshot, "missing material no partial mutation")
	player.inventory.add_reward(catalog.create("central_syancrystal", {"instance_id":"bound-material", "bound":true, "quantity":1}).value)
	item.locked = true
	_check(not PlayerCentralActions.execute(player, catalog, item.instance_id, player.inventory.revision, true).is_ok and player.inventory.count_definition("central_syancrystal") == 1, "locked no consumption")
	item.locked = false
	_check(PlayerCentralActions.execute(player, catalog, item.instance_id, player.inventory.revision, true).is_ok and player.inventory.find(item.instance_id).bound, "bound material propagates")
	var evolved: GameItem = catalog.create(catalog.central_rules.evolution_material, {"instance_id":"repeated-evolution"}).value
	player.inventory.add_reward(evolved)
	snapshot = player.inventory.revision
	_check(not PlayerCentralActions.execute(player, catalog, evolved.instance_id, snapshot, true).is_ok and player.inventory.find(evolved.instance_id) == evolved and player.inventory.revision == snapshot, "duplicate evolution retains crystal")
	for invalid: Variant in ["yes", 1, []]:
		_check(not service.execute(state, {"type":"change_central", "instance_id":"x", "confirmed":invalid, "inventory_revision":state.inventory_revision}).is_ok, "invalid confirmation type")


## 执行成功流程并检查预览无副作用、确认和重发保护。
## [param id] 唯一实例。
func _use(id: String) -> void:
	var before := state.to_dictionary()
	var query := service.execute(state, {"type":"query_central", "instance_id":id})
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.central_workshop.preview.can_execute and state.to_dictionary() == before, "read only actual quote")
	var command := {"type":"change_central", "instance_id":id, "inventory_revision":state.inventory_revision, "confirmed":false, "grade":18, "costs":[], "evolved":true}
	_check(not service.execute(state, command).is_ok, "confirmation required")
	command.confirmed = true
	var result := service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "isolated mutation")
	if not result.is_ok:
		push_error(result.error_message)
		return
	_check(result.value.candidate.currency == state.currency, "no invented extra fee")
	state = result.value.candidate
	_check(not service.execute(state, command).is_ok, "stale repeat rejected")


## 查询当前持有的定义实例。
## [param definition_id] 目录定义。
## 返回身份，无持有时为空。
func _instance(definition_id: String) -> String:
	for stack: InventoryStackRecord in state.inventory_stacks:
		if stack.item_definition_id == definition_id: return stack.stack_id
	return ""


## 使用当前版本尝试加工，失败用例不会采纳候选。
## [param id] 目标身份。
## 返回权威结果。
func _change(id: String) -> DomainResult:
	return service.execute(state, {"type":"change_central", "instance_id":id, "inventory_revision":state.inventory_revision, "confirmed":true})


## 汇总事务断言。
## [param condition] 条件。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
