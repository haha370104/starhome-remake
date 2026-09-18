extends SceneTree

var checks := 0
var failures := PackedStringArray()
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper


## 验证真实目录、装配、战斗属性以及保存和客户端的共同中枢状态。
func _initialize() -> void:
	var initialized := catalog.initialize()
	_check(initialized.is_ok, "catalog initializes")
	if not initialized.is_ok:
		push_error(initialized.error_message)
		quit(1)
		return
	_check(fixture.initialize().is_ok, "authority fixture")
	mapper = PlayerStateMapper.new(catalog)
	_chips()
	for id: String in catalog.central_rules.profiles: _accessory(id)
	print("Central integration: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 覆盖对应零件条件、进化后永久加成及真实武器装配中的一致结果。
func _chips() -> void:
	var player: Player = mapper.to_domain(fixture._state).value
	var initial := player.vehicle.calculate_stats()
	for id: String in CentralRules.CHIP_IDS:
		var module := catalog.central_rules.modules["central_%s_module_1" % id]
		_check(player.central.use_module(module).is_ok, "activate chip")
		var item := catalog.create("central_%s_module_1" % id, {"bound": false}).value as GameItem
		_check(item.bound and item.max_stack == 1, "module binding cannot be disabled")
	_check(player.central == player.vehicle.central, "one shared central state")
	_check(player.central.active("tank", player.vehicle.loadout), "chassis controls tank chip")
	_check(player.central.active("engine", player.vehicle.loadout), "engine controls engine chip")
	_check(player.central.active("gun", player.vehicle.loadout), "energy cannon controls gun chip")
	_check(not player.central.active("missile", player.vehicle.loadout), "missing missile chip inactive")
	var cannon := player.vehicle.loadout.at(1)
	player.vehicle.loadout._equipped.erase(1)
	_check(not player.central.active("gun", player.vehicle.loadout), "removed cannon inactive")
	var mining := VehicleMiningArm.new({"id":"test_mining", "kind":"mining_arm", "equipment_location":1}, {"instance_id":"test_mining"})
	player.vehicle.loadout.restore(mining)
	_check(not player.central.active("gun", player.vehicle.loadout), "mining arm cannot activate cannon chip")
	player.vehicle.loadout._equipped.erase(1)
	player.vehicle.loadout.restore(cannon)
	cannon.durability = 0
	_check(not player.central.active("gun", player.vehicle.loadout), "broken cannon inactive")
	cannon.durability = cannon.max_durability
	var armor_bonus := player.central.bonus("defense", player.vehicle.loadout, catalog.central_rules)
	for location in [5,6,7,8]:
		var armor := VehicleEquipment.new({"id":"test_armor", "equipment_location":location}, {"instance_id":"armor_%d" % location})
		player.vehicle.loadout.restore(armor)
	_check(player.central.bonus("defense", player.vehicle.loadout, catalog.central_rules) == armor_bonus + 10, "four armor pieces contribute one chip")
	for location in [5,6,7,8]: player.vehicle.loadout._equipped.erase(location)
	player.vehicle.reconcile_loadout_state(false)
	var pre_evolution := player.vehicle.calculate_stats()
	_check(pre_evolution.max_health == initial.max_health + 500 and pre_evolution.energy_cannon_attack == initial.energy_cannon_attack + 50, "only active level one components contribute")
	for id: String in CentralRules.CHIP_IDS: player.central.use_module(catalog.central_rules.modules["central_%s_module_3" % id])
	_check(player.central.evolve().is_ok, "evolve")
	player.vehicle.reconcile_loadout_state(false)
	var evolved := player.vehicle.calculate_stats()
	_check(evolved.max_health == initial.max_health + 5000 and evolved.energy_cannon_attack == initial.energy_cannon_attack + 350, "shared evolved totals")
	var restored := _roundtrip(player)
	_check(restored.central.to_dictionary() == player.central.to_dictionary() and restored.vehicle.calculate_stats() == evolved, "permanent state and derived values roundtrip")
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(fixture._service.build_bundle(mapper.to_record(restored).value)), "client accepts central state")
	_check(client.central.to_dictionary() == player.central.to_dictionary() and client.vehicle.calculate_stats() == evolved, "client and authority agree")
	var malformed := fixture._state.to_dictionary()
	malformed.central = {"evolved":true}
	_check(not PlayerStateRecord.from_dictionary(malformed).is_ok, "reject evolved state without six chips")


## 验证六槽与接合器/发生器互不覆盖，且装备成长在每条移动路径中保留。
## [param id] 附属装备定义。
func _accessory(id: String) -> void:
	var player: Player = mapper.to_domain(fixture._state).value
	var profile := catalog.central_rules.profiles[id]
	var item: VehicleEquipment = catalog.create(id, {"instance_id":"central.body", "central_growth":{"grade":18}}).value
	_check(item.accepts_location(profile.location) and profile.location >= 40, "separate stable slot")
	_check(not item.accepts_location(33) and not item.accepts_location(34), "no joint or generator slot conflict")
	_check(not item.to_view_dictionary().socket_eligible and item.icon_path.ends_with("_18.png"), "original icon, no unrelated sockets")
	_check(player.inventory.add_reward(item).is_ok, "supply body")
	var before_bag := player.inventory.revision
	_check(not player.equip_vehicle_item(item.instance_id, profile.location, before_bag, player.vehicle.loadout.revision).is_ok and player.inventory.revision == before_bag, "unevolved equip rejected atomically")
	var desired: Array = []
	for equipped: VehicleEquipment in player.vehicle.loadout.items():
		desired.append({"instance_id":equipped.instance_id, "definition_id":equipped.definition_id, "location":equipped.equipment_location, "display_name":equipped.display_name})
	desired.append({"instance_id":item.instance_id, "definition_id":id, "location":profile.location, "display_name":item.display_name})
	_check(not VehicleLoadoutExchange.apply(player, desired, player.inventory.revision, player.vehicle.loadout.revision, false).is_ok, "preset cannot bypass evolution")
	for chip_id: String in CentralRules.CHIP_IDS:
		player.central.use_module(catalog.central_rules.modules["central_%s_module_1" % chip_id])
		player.central.use_module(catalog.central_rules.modules["central_%s_module_3" % chip_id])
	player.central.evolve()
	player.vehicle.reconcile_loadout_state(false)
	player.vehicle.loadout.equip(catalog.create("starter_missile", {"instance_id":"central.missile"}).value, 13, player.vehicle.loadout.revision)
	var before := player.vehicle.calculate_stats()
	player.vehicle.health = 29
	player.vehicle.working_energy = 17
	player.vehicle.reserve_energy = 300
	_check(player.equip_vehicle_item(item.instance_id, profile.location, player.inventory.revision, player.vehicle.loadout.revision).is_ok, "evolved equip")
	_check(player.vehicle.health == 29 and player.vehicle.working_energy == 17 and player.vehicle.reserve_energy == 300, "equip preserves absolute resources")
	var after := player.vehicle.calculate_stats()
	for attribute: String in CentralRules.ATTRIBUTES:
		_check(after[attribute] - before[attribute] == item.special_bonus(attribute), "single shared attribute " + attribute)
	var combat: CombatDefinitionCatalog = CombatDefinitionCatalog.load_default().value
	var actual: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier":1500, "base_speed_cap":240}).value
	_check(actual.assembly.max_health == after.max_health and actual.assembly.defense == after.defense, "actual battle stats")
	for weapon: Dictionary in actual.weapons.values():
		_check(weapon.minimum_damage == after.energy_cannon_attack if weapon.skill_id == "energy_cannon" else weapon.minimum_damage == after.missile_attack, "actual weapon damage")
	var copied := EquipmentConditionLoadout.new(player).duplicate_loadout()
	var copied_item: VehicleEquipment = copied._items[item.instance_id]
	_check(copied_item.central_growth.grade == 18 and copied_item.central_rules == catalog.central_rules, "runtime copy retains rules")
	copied_item.central_growth.grade = 1
	_check(item.central_growth.grade == 18, "no runtime state alias")
	var restored := _roundtrip(player)
	_check(restored.vehicle.loadout.at(profile.location).central_growth.grade == 18 and restored.vehicle.calculate_stats() == after, "equipped JSON roundtrip")
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(fixture._service.build_bundle(mapper.to_record(restored).value)), "client equipped snapshot")
	_check(client.vehicle.loadout.at(profile.location).central_growth.grade == 18, "client equipped grade")
	_check(restored.unequip_vehicle_item(profile.location, restored.inventory.revision, restored.vehicle.loadout.revision).is_ok, "unequip")
	_check(restored.warehouse.transfer(restored.inventory, 1, true, item.instance_id, 1, restored.inventory.revision, restored.warehouse.revision, "unused").is_ok, "warehouse deposit")
	restored = _roundtrip(restored)
	_check(restored.warehouse.find(item.instance_id).central_growth.grade == 18, "warehouse JSON")
	_check(restored.warehouse.transfer(restored.inventory, 1, false, item.instance_id, 1, restored.inventory.revision, restored.warehouse.revision, "unused").is_ok, "warehouse withdrawal")
	_check(catalog.create("iron_piece", {"central_growth":{"grade":1}}).is_ok == false, "reject unrelated material growth")
	var durable := item.durability
	item.record_use("damage", 100000)
	_check(item.durability == durable, "original no durability wear")


## 经实际JSON边界恢复独立聚合。
## [param player] 玩家。
## 返回恢复的玩家。
func _roundtrip(player: Player) -> Player:
	var saved := mapper.to_record(player)
	_check(saved.is_ok, "serialize")
	var parsed := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(saved.value.to_dictionary())))
	_check(parsed.is_ok, "parse")
	var restored := mapper.to_domain(parsed.value)
	_check(restored.is_ok, "map to domain")
	return restored.value


## 汇总行为断言。
## [param condition] 条件。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
