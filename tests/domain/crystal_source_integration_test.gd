extends SceneTree

var _checks := 0
var _failures := PackedStringArray()
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper


## 验证真实装配、综合等级、战斗计算、背包仓库和客户端快照完整往返。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "dependencies")
	mapper = PlayerStateMapper.new(catalog)
	for id: String in catalog.crystal_source_rules.profiles:
		_test_equipment(id)
	_test_cores()
	print("Crystal source integration: %d checks, %d failures" % [_checks, _failures.size()])
	for failure: String in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 对八款普通和赠品逐一装配、换方案、进仓库并经过真实JSON边界。
## [param id] 独立定义。
func _test_equipment(id: String) -> void:
	var player: Player = mapper.to_domain(fixture._state).value
	var profile := catalog.crystal_source_rules.profiles[id]
	var item: VehicleEquipment = catalog.create(id, {"instance_id": "source.equipment",
		"crystal_source": {"version": 1, "quality": 15, "growth": 15, "slots": [
			{"definition_id": "crystal_source_core_red_5", "cracks": 2, "bound": true}, {}, {}]}}).value
	_check(item != null and item.accepts_location(profile.location), "stable location")
	_check(catalog.create(id, {}).value.bound == profile.bound and item.bound, "gift and embedded binding inherited")
	_check(player.inventory.add_reward(item).is_ok, "put in bag")
	var before := _state(player)
	_check(not player.equip_vehicle_item(item.instance_id, profile.location, player.inventory.revision, player.vehicle.loadout.revision).is_ok and _state(player) == before, "manual level rejects atomically")
	var desired: Array = []
	for equipped: VehicleEquipment in player.vehicle.loadout.items():
		desired.append({"instance_id": equipped.instance_id, "definition_id": equipped.definition_id, "location": equipped.equipment_location, "display_name": equipped.display_name})
	desired.append({"instance_id": item.instance_id, "definition_id": id, "location": profile.location, "display_name": item.display_name})
	_check(not VehicleLoadoutExchange.apply(player, desired, player.inventory.revision, player.vehicle.loadout.revision, false).is_ok and _state(player) == before, "preset level rejects atomically")
	player.level = 400
	if profile.attribute in ["rocket_attack", "missile_attack"]:
		var secondary_id := "starter_rocket_launcher" if profile.attribute == "rocket_attack" else "starter_missile"
		player.vehicle.loadout.equip(catalog.create(secondary_id, {"instance_id": "test.secondary"}).value, 13, player.vehicle.loadout.revision)
	var base := player.vehicle.calculate_stats()
	player.vehicle.health = 35
	player.vehicle.working_energy = 13
	player.vehicle.reserve_energy = 2345
	_check(player.equip_vehicle_item(item.instance_id, profile.location, player.inventory.revision, player.vehicle.loadout.revision).is_ok, "equip at exact level")
	_check(player.vehicle.health == 35 and player.vehicle.working_energy == 13 and player.vehicle.reserve_energy == 2345, "special equipment never heals or restores energy")
	var stats := player.vehicle.calculate_stats()
	for attribute: String in ["max_health", "energy_cannon_attack", "rocket_attack", "missile_attack"]:
		_check(int(stats[attribute]) - int(base[attribute]) == item.special_bonus(attribute), "actual shared combat stat " + attribute)
	var saved := mapper.to_record(player)
	_check(saved.is_ok, "equipped save")
	var restored: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(saved.value.to_dictionary()))).value).value
	var restored_item := restored.vehicle.loadout.at(profile.location)
	_check(restored_item.crystal_source.to_dictionary() == item.crystal_source.to_dictionary(), "equipped JSON facts")
	_check(restored.vehicle.calculate_stats() == player.vehicle.calculate_stats(), "saved derived combat parity")
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(fixture._service.build_bundle(mapper.to_record(restored).value)), "client projection accepts")
	_check(client.vehicle.loadout.at(profile.location).crystal_source.to_dictionary() == item.crystal_source.to_dictionary(), "client growth facts")
	var condition := EquipmentConditionLoadout.new(player).duplicate_loadout()
	var copied := condition._items[item.instance_id] as VehicleEquipment
	_check(copied.special_bonus("energy_cannon_attack") == item.special_bonus("energy_cannon_attack") and copied.crystal_source != item.crystal_source, "simulation copies independent growth")
	copied.crystal_source.quality = 0
	_check(item.crystal_source.quality == 15, "simulation no shared mutable growth")
	_check(player.unequip_vehicle_item(profile.location, player.inventory.revision, player.vehicle.loadout.revision).is_ok, "unequip")
	_check(player.vehicle.health == 35 and player.vehicle.working_energy == 13, "unequip preserves absolute resources")
	_check(player.warehouse.transfer(player.inventory, 1, true, item.instance_id, 1, player.inventory.revision, player.warehouse.revision, "unused").is_ok, "deposit")
	var warehoused: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(JSON.parse_string(_state(player))).value).value
	_check(warehoused.warehouse.find(item.instance_id).crystal_source.to_dictionary() == item.crystal_source.to_dictionary(), "warehouse full facts")
	_check(warehoused.warehouse.transfer(warehoused.inventory, 1, false, item.instance_id, 1, warehoused.inventory.revision, warehoused.warehouse.revision, "unused").is_ok, "withdraw")
	var bag: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(JSON.parse_string(_state(warehoused))).value).value
	_check(bag.inventory.find(item.instance_id).crystal_source.to_dictionary() == item.crystal_source.to_dictionary(), "inventory JSON facts")
	item.durability = 0
	_check(item.special_bonus(profile.attribute) == 0, "damaged has no effect")
	_check(not catalog.create("iron_piece", {"crystal_source": item.crystal_source.to_dictionary()}).is_ok, "foreign item state rejected")
	_check(catalog.create(id, {}).value.crystal_source.to_dictionary().is_empty(), "old save default empty")
	_check(not catalog.create(id, {"vehicle_sockets": {"slots": [{"opened": true}]}}).is_ok, "cannot use ordinary sockets")


## 核心裂纹穿过拆分、仓库、存档和客户端边界，非法跨类型数据拒绝。
func _test_cores() -> void:
	var player: Player = mapper.to_domain(fixture._state).value
	var core: CrystalSourceCore = catalog.create("crystal_source_core_black_4", {"instance_id": "source.core", "quantity": 8, "bound": true, "crystal_source_cracks": 3}).value
	_check(player.inventory.add_reward(core).is_ok, "core added")
	_check(player.warehouse.transfer(player.inventory, 1, true, core.instance_id, 3, player.inventory.revision, 0, "source.part").is_ok, "core partial transfer")
	var restored: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(JSON.parse_string(_state(player))).value).value
	_check(restored.inventory.find(core.instance_id).quantity == 5 and restored.inventory.find(core.instance_id).cracks == 3, "backpack core saved")
	_check(restored.warehouse.find("source.part").quantity == 3 and restored.warehouse.find("source.part").cracks == 3, "warehouse core saved")
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(fixture._service.build_bundle(mapper.to_record(restored).value)) and client.inventory.find(core.instance_id).cracks == 3, "core client facts")
	for invalid: Variant in [-1, 4, 0.5, INF, "2", true]:
		_check(not catalog.create(core.definition_id, {"crystal_source_cracks": invalid}).is_ok, "invalid core cracks")
	_check(not catalog.create("iron_piece", {"crystal_source_cracks": 1}).is_ok, "no foreign core cracks")
	_check(not catalog.create(core.definition_id, {"crystal_cracks": 1}).is_ok, "ordinary cracks cannot enter source cores")


## 通过正式映射获取完整快照，用于原子失败和真实JSON验证。
## [param player] 测试聚合。
## 返回序列化状态。
func _state(player: Player) -> String:
	return JSON.stringify(mapper.to_record(player).value.to_dictionary())


## 收集检查失败，保留独立覆盖。
## [param condition] 断言条件。[param label] 失败描述。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
