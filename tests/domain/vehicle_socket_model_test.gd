extends SceneTree

var _checks: int = 0
var _failures: int = 0


## 验证孔槽资格、失败回退、裂纹和存档边界；不读写玩家存档。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "catalog")
	var tank: VehicleEquipment = catalog.create("recruit_tank", {"instance_id": "tank"}).value
	_check(tank.sockets.capacity() == 8 and tank.sockets.opened_count() == 0, "old save has eight closed holes")
	var gun: VehicleEquipment = catalog.create("recruit_energy_cannon", {}).value
	_check(gun.sockets.capacity() == 0, "recruit cannon is explicitly ineligible")
	var rules := catalog.socket_rules
	var profile := rules.profile(tank.definition_id)
	var high := rules.solvent("high_grade_density_solvent")
	_check(is_equal_approx(tank.sockets.preview_open(0, profile, high, rules).value, 0.8), "first high solvent chance")
	_check(not tank.sockets.preview_open(-1, profile, high, rules).is_ok, "negative hole")
	_check(not tank.sockets.preview_open(8, profile, high, rules).is_ok, "locked expansion")
	tank.sockets.settle_open(0, true, "none")
	var crystal: VehicleCrystal = catalog.create("bright_firepower_crystal", {"instance_id": "crystal", "crystal_cracks": 3, "bound": true}).value
	_check(tank.sockets.inlay(0, crystal).is_ok, "inlay")
	_check(not tank.sockets.inlay(0, crystal).is_ok, "occupied hole")
	_check(tank.sockets.slot_at(0).cracks == 3 and tank.sockets.slot_at(0).bound, "preserve cracks and binding")
	var external := tank.sockets.slot_at(0)
	external.cracks = 0
	_check(tank.sockets.slot_at(0).cracks == 3, "defensive copy")
	var saved := tank.sockets.to_dictionary()
	var restored: VehicleEquipment = catalog.create("recruit_tank", {"vehicle_sockets": saved}).value
	_check(restored.sockets.to_dictionary() == saved, "roundtrip")
	_check(not catalog.create("recruit_energy_cannon", {"vehicle_sockets": saved}).is_ok, "ineligible save rejected")
	saved.slots[0].crystal_id = "unknown"
	_check(not catalog.create("recruit_tank", {"vehicle_sockets": saved}).is_ok, "unknown crystal rejected")
	tank.sockets.settle_open(1, false, "close_last_socket")
	_check(tank.sockets.opened_count() == 0 and tank.sockets.slot_at(0).crystal_id.is_empty(), "failure removes opened hole and crystal")
	_check(tank.sockets.settle_open(0, false, "destroy_equipment"), "destruction propagated")
	for index: int in 4:
		tank.sockets.settle_open(index, true, "none")
	_check(not tank.sockets.preview_open(4, profile, high, rules).is_ok, "no invented fifth probability")
	_check(tank.sockets.preview_open(4, profile, rules.solvent("vehicle_density_solvent_i"), rules).is_ok, "fixed I solvent supports later holes")
	_check(not tank.sockets.expand(profile).is_ok, "no expansion for recruit")
	var advanced: VehicleEquipment = catalog.create("glory_equipment_tank14_e168c47216", {}).value
	_check(advanced.sockets.capacity() == 8, "expansion initially locked")
	_check(advanced.sockets.expand(rules.profile(advanced.definition_id)).is_ok, "ninth hole")
	_check(advanced.sockets.expand(rules.profile(advanced.definition_id)).is_ok, "tenth hole")
	_check(not advanced.sockets.expand(rules.profile(advanced.definition_id)).is_ok, "no eleventh hole")
	var duplicate: VehicleCrystal = crystal.copy_stack("other", 1)
	_check(duplicate.cracks == 3 and duplicate.bound and duplicate.can_stack_with(crystal), "split keeps identity")
	duplicate.cracks = 0
	_check(not duplicate.can_stack_with(crystal), "cannot launder cracks by merging")
	for invalid: Variant in [-1, 4, 0.5, "1", null, INF]:
		_check(not catalog.create("bright_firepower_crystal", {"crystal_cracks": invalid}).is_ok, "reject invalid cracks")
	_check(not catalog.create("low_grade_gel", {"crystal_cracks": 1}).is_ok, "no cracks on ordinary material")
	_check(not VehicleSockets.restore({"version": 1, "slots": [{"opened": false, "crystal_id": "x"}]}).is_ok, "closed crystal invalid")
	_check(not VehicleSockets.restore({"version": 2, "slots": []}).is_ok, "unknown version")
	_test_persistence(catalog)
	print("Vehicle socket model: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 验证装备、背包晶石、JSON 和客户端快照均保留状态。
## [param catalog] 正式物品目录。
func _test_persistence(catalog: ItemCatalog) -> void:
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "isolated player fixture")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	var chassis := player.vehicle.loadout.at(0)
	chassis.sockets.settle_open(0, true, "none")
	var crystal: VehicleCrystal = catalog.create("bright_health_crystal", {"instance_id": "loose", "crystal_cracks": 2, "bound": true, "quantity": 2}).value
	_check(chassis.sockets.inlay(0, crystal).is_ok, "installed chassis inlay fixture")
	_check(player.inventory.add_reward(crystal).is_ok, "loose cracked crystal fixture")
	var spare: VehicleEquipment = player.inventory.find("inventory.spare_engine")
	spare.sockets.settle_open(0, true, "none")
	_check(spare.sockets.inlay(0, crystal).is_ok, "backpack equipment fixture")
	var record := mapper.to_record(player)
	_check(record.is_ok, "record mapping")
	var parsed := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(record.value.to_dictionary())))
	_check(parsed.is_ok, "JSON record")
	var restored: Player = mapper.to_domain(parsed.value).value
	_check(restored.vehicle.loadout.at(0).sockets.slot_at(0).cracks == 2, "equipped persistence")
	_check((restored.inventory.find("inventory.spare_engine") as VehicleEquipment).sockets.slot_at(0).bound, "backpack equipment persistence")
	_check((restored.inventory.find("loose") as VehicleCrystal).cracks == 2, "loose crystal persistence")
	var current := CurrentPlayer.new()
	_check(current.apply_bundle(PlayerPanelProjector.new(catalog).build_bundle(restored)), "client accepts bundle")
	_check(current.vehicle.loadout.at(0).sockets.slot_at(0).cracks == 2, "client equipped state")
	_check((current.inventory.find("loose") as VehicleCrystal).cracks == 2, "client loose state")
	var clean: VehicleCrystal = catalog.create("bright_health_crystal", {"instance_id": "clean", "bound": true}).value
	_check(restored.inventory.add_reward(clean).is_ok, "different cracks reward")
	_check(restored.inventory.find("loose").quantity == 2 and restored.inventory.find("clean") != null, "reward cannot merge different cracks")


## 记录断言并继续覆盖其他独立边界。
## [param condition] 实际结果。
## [param message] 失败诊断。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
