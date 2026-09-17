extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0


## 验证护甲换代、销毁确认、保存和重复请求，以及背包满时的原位替换。
func _initialize() -> void:
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize().is_ok, "initialize")
	_mapper = PlayerStateMapper.new(_items)
	var player := _player(4)
	var armor := player.inventory.find("armor") as VehicleEquipment
	armor.sockets.settle_open(0, true, "")
	armor.sockets.inlay(0, _items.create("bright_health_crystal", {"instance_id": "crystal", "crystal_cracks": 2, "bound": true}).value)
	armor.max_durability -= 10
	armor.durability -= 80
	var socket := armor.sockets.slot_at(0).to_dictionary()
	var command := {"type": "refine_armor", "instance_id": "armor", "material_id": "stone", "material_quantity": 4,
		"inventory_revision": player.inventory.revision, "confirm_destruction": true}
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var result := _service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "isolated transaction")
	if not result.is_ok: push_error(result.error_message); quit(1); return
	player = _mapper.to_domain(result.value.candidate).value
	armor = player.inventory.find("armor")
	_check(armor.armor_refinement_profile.level == 5 and armor.stat("armor") == 45 and armor.weight == 140, "next source definition")
	_check(armor.sockets.slot_at(0).to_dictionary() == socket and armor.sockets.capacity() == 4, "crystal preservation")
	_check(armor.bound and player.inventory.find("stone").quantity == 16 and player.inventory.currency == 1000000, "cost and binding")
	_check(player.inventory.revision == state.inventory_revision + 1, "single inventory transaction")
	_check(not _service.execute(result.value.candidate, command).is_ok, "replay rejected")
	_check(not result.value.panel_bundle.armor_refinement.preview.has("candidate"), "no domain objects over network")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(result.value.panel_bundle) and current.inventory.find("armor").armor_refinement_profile.level == 5, "client factory replacement")
	var query := _service.execute(result.value.candidate, {"type": "query_armor_refinement", "instance_id": "armor", "material_id": "stone", "material_quantity": 4})
	_check(query.is_ok and not query.value.changed and query.value.panel_bundle.armor_refinement.offers.size() == 9, "query and acquisition chain")
	_check(JSON.parse_string(JSON.stringify(query.value.panel_bundle)).armor_refinement.preview.has("chance"), "serializable preview")
	var buy := _service.execute(result.value.candidate, {"type": "buy_armor_refinement_item", "definition_id": "armor_refinement_chip", "quantity": 2, "inventory_revision": player.inventory.revision, "price": 1})
	_check(buy.is_ok and buy.value.candidate.currency == 980000, "server purchase pricing")
	for level: int in [1, 4, 7]:
		player = _player(level)
		var failed := PlayerArmorRefinementActions.execute(player, _items, "armor", "stone", 1, player.inventory.revision, true, 0.99)
		_check(failed.is_ok and failed.value.destroyed and not failed.value.success, "original destruction outcome")
		_check(player.inventory.find("armor") == null and player.inventory.find("stone").quantity == 19, "destroy and pay once")
		_check(_mapper.to_record(player).is_ok, "destroyed item stays absent in save")
	for problem: String in ["confirmation", "locked", "damaged", "installed", "missing", "wrong", "quantity", "stale", "roll"]:
		player = _player(4)
		armor = player.inventory.find("armor")
		var revision := player.inventory.revision
		if problem == "locked": armor.locked = true
		if problem == "damaged": armor.durability = 0
		if problem == "missing": player.inventory.find("stone").quantity = 1
		if problem == "wrong":
			player.inventory.remove_for_transfer("stone")
			player.inventory.add_reward(_items.create("armor_refinement_back_stone", {"instance_id": "stone", "quantity": 4}).value)
		if problem == "installed":
			player.inventory.remove_for_transfer("armor")
			player.vehicle.loadout.equip(armor, 5, player.vehicle.loadout.revision)
		before = _mapper.to_record(player).value.to_dictionary()
		var rejected := PlayerArmorRefinementActions.execute(player, _items, "armor", "stone", 0 if problem == "quantity" else 4,
			revision - 1 if problem == "stale" else player.inventory.revision, problem != "confirmation", NAN if problem == "roll" else 0.0)
		_check(not rejected.is_ok and _mapper.to_record(player).value.to_dictionary() == before, "atomic reject " + problem)
	player = _player(4)
	while player.inventory.items().size() < player.inventory.capacity:
		player.inventory.add_reward(_items.create("beginner_engine", {"instance_id": "filler" + str(player.inventory.items().size())}).value)
	_check(PlayerArmorRefinementActions.execute(player, _items, "armor", "stone", 4, player.inventory.revision, true, 0).is_ok, "full inventory replacement")
	_check(player.inventory.items().size() == player.inventory.capacity, "no extra output slot required")
	print("Armor refinement authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 构造指定阶级且具有二十颗匹配材料的隔离玩家。
## [param level] 第一至第七阶。
## 返回独立玩家。
func _player(level: int) -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	for profile: ArmorRefinementRules.Profile in _items.armor_refinement_rules.profiles.values():
		if profile.level == level and profile.location == 5 and not profile.gift_bound:
			_check(player.inventory.add_reward(_items.create(profile.definition_id, {"instance_id": "armor"}).value).is_ok, "give armor")
			break
	_check(player.inventory.add_reward(_items.create("armor_refinement_front_stone" if level >= 4 else "armor_refinement_chip", {"instance_id": "stone", "quantity": 20, "bound": true}).value).is_ok, "give material")
	return player


## 记录事务断言。
## [param condition] 实际结果。
## [param label] 诊断。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
