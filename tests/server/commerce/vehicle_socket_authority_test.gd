extends SceneTree

var _items := ItemCatalog.new()
var _fixture := PlayerPanelServiceFixture.new()
var _service := AuthoritativeCommerceService.new()
var _mapper: PlayerStateMapper
var _checks := 0
var _failures := 0


## 运行隔离玩家的开槽、镶嵌、摘取、扩孔及战斗属性回归。
func _initialize() -> void:
	_check(_items.initialize().is_ok and _fixture.initialize().is_ok and _service.initialize().is_ok, "initialize")
	_mapper = PlayerStateMapper.new(_items)
	_test_transactions()
	_test_failures()
	_test_opening()
	_test_stats()
	print("Vehicle socket authority: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 创建独立的有资金玩家，不访问游戏存档。
## 返回测试聚合。
func _player() -> Player:
	var player: Player = _mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	return player


## 通过正式目录向测试背包加入物品。
## [param player] 测试聚合。
## [param definition] 定义身份。
## [param id] 实例身份。
## [param quantity] 数量。
## 返回已加入物品。
func _give(player: Player, definition: String, id: String, quantity: int = 1) -> GameItem:
	var item: GameItem = _items.create(definition, {"instance_id": id, "quantity": quantity}).value
	_check(player.inventory.add_reward(item).is_ok, "give " + id)
	return item


## 验证服务端结算不信任价格、品质和玩家身份，重放被版本拒绝。
func _test_transactions() -> void:
	var player := _player()
	var target: VehicleEquipment = player.inventory.find("inventory.spare_engine")
	target.sockets.settle_open(0, true, "none")
	var crystal := _give(player, "bright_health_crystal", "crystal", 2) as VehicleCrystal
	crystal.bound = true
	crystal.cracks = 2
	var state: PlayerStateRecord = _mapper.to_record(player).value
	var before := state.to_dictionary()
	var command := {"type": "inlay_vehicle_crystal", "instance_id": target.instance_id,
		"material_id": crystal.instance_id, "socket_index": 0, "inventory_revision": player.inventory.revision,
		"price": 0, "cracks": 0, "account_id": "other"}
	var result := _service.execute(state, command)
	_check(result.is_ok and state.to_dictionary() == before, "isolated authoritative settlement")
	if not result.is_ok:
		return
	var candidate: PlayerStateRecord = result.value.candidate
	var restored: Player = _mapper.to_domain(candidate).value
	var updated: VehicleEquipment = restored.inventory.find(target.instance_id)
	_check(updated.sockets.slot_at(0).cracks == 2 and updated.bound, "ignore client cracks, propagate binding")
	_check(restored.inventory.find("crystal").quantity == 1, "consume exactly one")
	_check(not _service.execute(candidate, command).is_ok, "reject replay")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(result.value.panel_bundle), "valid client snapshot")
	_check((current.inventory.find(target.instance_id) as VehicleEquipment).sockets.slot_at(0).cracks == 2, "client state agrees")
	command.type = "query_vehicle_sockets"
	var query := _service.execute(candidate, command)
	_check(query.is_ok and not query.value.changed, "queries do not commit")
	_check(query.value.panel_bundle.vehicle_sockets.preview.can_extract, "query previews extraction")
	var extracted := PlayerVehicleSocketActions.extract(restored, target.instance_id, 0, false, false, restored.inventory.revision, _items, "returned")
	_check(extracted.is_ok and (restored.inventory.find("returned") as VehicleCrystal).cracks == 3, "normal removal adds crack")
	_check(updated.sockets.slot_at(0).opened and updated.sockets.slot_at(0).crystal_id.is_empty(), "removal keeps open hole")
	PlayerVehicleSocketActions.inlay(restored, target.instance_id, "returned", 0, restored.inventory.revision)
	before = _mapper.to_record(restored).value.to_dictionary()
	_check(not PlayerVehicleSocketActions.extract(restored, target.instance_id, 0, false, false, restored.inventory.revision, _items, "lost").is_ok, "fourth removal requires confirmation")
	_check(_mapper.to_record(restored).value.to_dictionary() == before, "unconfirmed removal unchanged")
	_give(restored, "vehicle_precise_hammer", "hammer")
	_check(PlayerVehicleSocketActions.extract(restored, target.instance_id, 0, true, false, restored.inventory.revision, _items, "protected").is_ok, "hammer removal")
	_check((restored.inventory.find("protected") as VehicleCrystal).cracks == 3 and restored.inventory.find("hammer") == null, "hammer consumed, existing cracks stay")
	PlayerVehicleSocketActions.inlay(restored, target.instance_id, "protected", 0, restored.inventory.revision)
	_check(PlayerVehicleSocketActions.extract(restored, target.instance_id, 0, false, true, restored.inventory.revision, _items, "destroyed").value.destroyed_crystal, "confirmed destruction")
	_check(restored.inventory.find("destroyed") == null, "destroyed crystal not credited")
	var advanced := _give(restored, "glory_equipment_tank14_e168c47216", "advanced") as VehicleEquipment
	_give(restored, "vehicle_armed_chip", "chips", 16)
	for index: int in 2:
		_check(PlayerVehicleSocketActions.expand(restored, advanced.instance_id, restored.inventory.revision).is_ok, "expand " + str(index))
	_check(advanced.sockets.capacity() == 10 and restored.inventory.find("chips") == null, "exact chip payment")
	var buy := {"type": "buy_vehicle_workshop_material", "definition_id": "vehicle_precise_hammer",
		"quantity": 3, "inventory_revision": restored.inventory.revision, "price": 0}
	var purchased := _service.execute(_mapper.to_record(restored).value, buy)
	_check(purchased.is_ok and purchased.value.candidate.currency == restored.inventory.currency - 6000, "server shop price")
	_check(not _service.execute(purchased.value.candidate, buy).is_ok, "purchase replay")
	buy.definition_id = "recruit_tank"
	_check(not _service.execute(_mapper.to_record(restored).value, buy).is_ok, "purchase whitelist")


## 验证满包、锁定、错误材料、越界和安装中加工不发生部分扣费。
func _test_failures() -> void:
	for problem: String in ["full", "locked", "wrong", "out_of_range", "installed", "stale"]:
		var player := _player()
		var item: VehicleEquipment = player.inventory.find("inventory.spare_engine")
		item.sockets.settle_open(0, true, "none")
		var stone := _give(player, "bright_health_crystal", "stone") as VehicleCrystal
		if problem == "full":
			item.sockets.inlay(0, stone)
			player.inventory.capacity = player.inventory.items().size()
		if problem == "locked":
			item.locked = true
		if problem == "wrong":
			stone = null
		var state: PlayerStateRecord = _mapper.to_record(player).value
		var before := state.to_dictionary()
		var command := {"type": "extract_vehicle_crystal" if problem == "full" else "inlay_vehicle_crystal",
			"instance_id": "equipment.chassis" if problem == "installed" else item.instance_id,
			"material_id": "inventory.training_shirt" if problem == "wrong" else "stone",
			"socket_index": 99 if problem == "out_of_range" else 0,
			"inventory_revision": -1 if problem == "stale" else player.inventory.revision}
		_check(not _service.execute(state, command).is_ok and state.to_dictionary() == before, "atomic rejection " + problem)


## 用固定随机样本覆盖成功、丢孔和销毁，不靠概率碰运气。
func _test_opening() -> void:
	var player := _player()
	var item: VehicleEquipment = player.inventory.find("inventory.spare_engine")
	_give(player, "vehicle_density_solvent_i", "risky", 2)
	_give(player, "high_grade_density_solvent", "safe", 2)
	_give(player, "item:material:78f2a523a761", "low")
	var result := PlayerVehicleSocketActions.open_socket(player, item.instance_id, "safe", 0, player.inventory.revision, 0.0, false)
	_check(result.is_ok and item.sockets.opened_count() == 1, "opening success")
	result = PlayerVehicleSocketActions.open_socket(player, item.instance_id, "safe", 1, player.inventory.revision, 0.99, false)
	_check(result.is_ok and item.sockets.opened_count() == 1, "safe failure keeps hole")
	result = PlayerVehicleSocketActions.open_socket(player, item.instance_id, "low", 1, player.inventory.revision, 0.99, true)
	_check(result.is_ok and item.sockets.opened_count() == 0, "low failure closes hole")
	var revision := player.inventory.revision
	_check(not PlayerVehicleSocketActions.open_socket(player, item.instance_id, "risky", 0, revision, 0.99, false).is_ok, "destruction confirmation")
	_check(player.inventory.revision == revision, "no unconfirmed payment")
	result = PlayerVehicleSocketActions.open_socket(player, item.instance_id, "risky", 0, revision, 0.99, true)
	_check(result.is_ok and result.value.destroyed_equipment and player.inventory.find(item.instance_id) == null, "confirmed equipment destruction")


## 比较面板与真正战斗装配，跨装备最高四颗以及暴击作用范围。
func _test_stats() -> void:
	var player := _player()
	var chassis := player.vehicle.loadout.at(0)
	var engine := player.vehicle.loadout.at(3)
	for index: int in 4:
		chassis.sockets.settle_open(index, true, "none")
		chassis.sockets.inlay(index, _items.create("item:material:a7bccd7c1408", {}).value)
	engine.sockets.settle_open(0, true, "none")
	engine.sockets.inlay(0, _items.create("bright_firepower_crystal", {}).value)
	_check(player.vehicle.loadout.socket_bonus("energy_cannon_attack") == 14, "top four across equipment: 5+3+3+3")
	engine.durability = 0
	_check(player.vehicle.loadout.socket_bonus("energy_cannon_attack") == 12, "broken equipment suppressed")
	engine.durability = engine.max_durability
	for pair: Array in [[4, "bright_health_crystal"], [5, "bright_defense_crystal"], [6, "bright_critical_crystal"], [7, "bright_critical_crystal"]]:
		chassis.sockets.settle_open(pair[0], true, "none")
		chassis.sockets.inlay(pair[0], _items.create(pair[1], {}).value)
	player.vehicle.reconcile_loadout_state(false)
	var stats := player.calculate_vehicle_stats()
	var catalog: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var loadout: Dictionary = catalog.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	_check(stats.max_health == 120 and player.vehicle.health == 70, "health gem no free healing")
	_check(stats.defense == loadout.assembly.defense and stats.defense == 13, "defense real combat")
	_check(stats.energy_cannon_attack == 21 and loadout.weapons["energy_cannon.primary"].minimum_damage == 21, "attack real combat")
	_check(is_equal_approx(loadout.weapons["energy_cannon.primary"].critical_chance, 0.05), "critical chance accumulated")
	_check(VehicleCrystalHit.resolve(100, "energy_cannon", 0.05, 1.5, 0.049) == 150, "critical hit")
	_check(VehicleCrystalHit.resolve(100, "energy_cannon", 0.05, 1.5, 0.05) == 100, "critical boundary")
	_check(VehicleCrystalHit.resolve(100, "missile", 1.0, 1.5, 0.0) == 100, "missile excluded")
	_check(VehicleCrystalHit.resolve(100, "rocket_launcher", 1.0, 1.5, 0.0) == 100, "rocket excluded")
	var combat := AuthoritativeCombatModule.new()
	combat.configure(20, 42, 0)
	_check(combat.register_vehicle("p", "map", Vector2.ZERO, loadout.assembly, loadout.weapons).is_ok, "register real weapons")
	_check(is_equal_approx(combat.actors.p.weapons["energy_cannon.primary"].critical_chance, 0.05), "normalizer preserves critical")
	combat.actors.p.cooldown_ready_ticks["energy_cannon.primary"] = 999
	combat.actors.p.vehicle_state.working_energy = 7
	_check(combat.refresh_achievement_loadout("p", loadout).is_ok, "runtime refresh")
	_check(combat.actors.p.vehicle_state.working_energy == 7 and combat.actors.p.cooldown_ready_ticks["energy_cannon.primary"] == 999, "refresh keeps energy and cooldown")


## 记录行为断言并输出可定位错误。
## [param condition] 实际结果。
## [param message] 诊断文本。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
