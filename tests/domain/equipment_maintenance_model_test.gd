extends SceneTree

var _checks: int = 0
var _failures: int = 0


## 验证维护、速修和不可维修边界，不开启运行期磨损。
func _initialize() -> void:
	var items := ItemCatalog.new()
	_check(items.initialize().is_ok, "catalog")
	var engine: Equipment = items.create("beginner_engine", {"durability": 100}).value
	var quote := engine.maintenance_preview()
	_check(quote.is_ok and quote.value.after == 891 and quote.value.maximum_after == 891, "ordinary maximum loss is explicit")
	engine.maintain()
	_check(engine.durability == 891 and engine.max_durability == 891, "maintenance updates instance")
	_check(not engine.maintain().is_ok, "full durability rejected")
	engine.wear(400)
	var tool := items.maintenance_rules.repair_tool("maintenance_elecrepairbox1")
	_check(engine.maintenance_preview(tool).value.after == 791, "point repair")
	engine.maintain(tool)
	_check(engine.durability == 791 and engine.max_durability == 891, "quick preserves maximum")
	engine.maintain(items.maintenance_rules.repair_tool("maintenance_quickrepairbox1"))
	_check(engine.durability == 891, "percent repair clamps")
	engine.wear(900)
	engine.locked = true
	_check(not engine.maintain(tool).is_ok, "locked rejected")
	engine.locked = false
	_check(engine.maintain(tool).is_ok and engine.durability == 300, "broken equipment repairable")
	var clothing: Equipment = items.create("male_sleeveless_shirt", {"durability": 1}).value
	_check(clothing.maintenance_profile.required_skill_level == 35 and clothing.maintenance_profile.experience == 14, "clothing original skill and experience")
	_check(not clothing.maintenance_preview(tool).is_ok, "vehicle box cannot repair clothing")
	clothing.maintain()
	_check(clothing.durability == 64 and clothing.max_durability == 64, "tailoring preserves original maximum")
	var chassis_profile := items.maintenance_rules.profile("recruit_tank")
	_check(chassis_profile.wear_enabled and not chassis_profile.no_wear and chassis_profile.wear_thresholds.vehicle_movement == 120, "durable vehicle body wears after 120 moving seconds")
	_check(chassis_profile.wear_thresholds.vehicle_damage == 1, "vehicle damage wear is allocated in full durability units")
	var mining_arm: Equipment = items.create("glory_equipment_collector_ac947ee094", {"durability": 2}).value
	_check(mining_arm is VehicleMiningArm and mining_arm.maintenance_profile.wear_enabled, "mining arm has runtime wear policy")
	mining_arm.record_use("mining")
	_check(mining_arm.durability == 2 and mining_arm.usage.progress.get("mining", 0) == 1, "first successful mining cycle keeps usage without wear")
	mining_arm.record_use("mining")
	_check(mining_arm.durability == 1 and mining_arm.usage.progress.get("mining", -1) == 0, "second successful mining cycle wears the arm")
	mining_arm.record_use("mining", 2)
	_check(mining_arm.durability == 0, "fourth successful mining cycle breaks the arm")
	mining_arm.record_use("mining")
	_check(mining_arm.durability == 0 and mining_arm.usage.progress.get("mining", -1) == 0, "broken mining arm cannot accumulate use")
	var mining_profiles := 0
	var space_collectors := 0
	for id: String in items.definition_ids():
		var item: GameItem = items.create(id, {}).value
		if item is VehicleMiningArm:
			mining_profiles += 1
			_check(item.maintenance_profile != null and item.maintenance_profile.wear_enabled and item.maintenance_profile.wear_thresholds.get("mining") == 2, "ground mining arm has two-cycle wear: " + id)
		if id.begins_with("glory_equipment_space_collector_"):
			space_collectors += 1
			_check(item is VehicleEquipment and not item is VehicleMiningArm, "space collector retains space classification: " + id)
			var space_arm := item as Equipment
			_check(space_arm.max_durability > 1 and space_arm.maintenance_profile != null and space_arm.maintenance_profile.wear_enabled and space_arm.maintenance_profile.wear_event == "mining", "durable space collector has mining wear: " + id)
			var maximum := space_arm.max_durability
			space_arm.record_use("shot", 20)
			space_arm.record_use("movement", 60)
			space_arm.record_use("damage", 100)
			_check(space_arm.durability == maximum and space_arm.usage.progress.is_empty(), "space collector only wears on mining: " + id)
			space_arm.record_use("mining")
			_check(space_arm.durability == maximum and space_arm.usage.progress.get("mining", 0) == 1, "first space mining cycle accumulates usage: " + id)
			var restored: Equipment = items.create(id, space_arm.to_view_dictionary()).value
			restored.record_use("mining")
			_check(restored.durability == maximum - 1 and restored.usage.progress.get("mining", -1) == 0, "second space mining cycle wears after restore: " + id)
			_check(not restored.maintenance_preview().is_ok, "missing repair material does not grant free regular maintenance: " + id)
			restored.maintain(tool)
			_check(restored.durability == maximum, "space collector remains quick-repairable: " + id)
			restored.durability = 1
			_check(restored.record_use("mining", 2) and restored.durability == 0, "space collector reports breaking on mining: " + id)
			restored.record_use("mining")
			_check(restored.durability == 0 and restored.usage.progress.get("mining", -1) == 0, "broken space collector stops accumulating use: " + id)
	_check(mining_profiles == 16 and space_collectors == 6, "all ground and space collector classifications checked")
	var invalid_wear := {"schema_version": 1, "wear_thresholds": {"mining": 2}, "equipment": [{"definition_id": "test.space_arm", "family": "vehicle", "wear_event": "unsupported"}]}
	_check(not EquipmentMaintenanceRules.from_dictionary(invalid_wear).is_ok, "unknown wear event is rejected")
	invalid_wear.equipment[0].wear_event = "mining"
	invalid_wear.wear_thresholds.clear()
	_check(not EquipmentMaintenanceRules.from_dictionary(invalid_wear).is_ok, "wear event without threshold is rejected")
	var forbidden := 0
	for id: String in items.definition_ids():
		var profile := items.maintenance_rules.profile(id)
		if profile == null:
			continue
		var item: Equipment = items.create(id, {}).value
		_check(item != null, "profile creates equipment")
		for cost: Dictionary in profile.materials:
			_check(items.create(cost.definition_id, {}).is_ok, "repair material exists")
		if not profile.regular_allowed:
			item.durability = 0
			_check(not item.maintenance_preview().is_ok, "forbidden maintenance")
			forbidden += 1
	_check(forbidden > 0, "special and armor exclusions present")
	_check("yian_harbor_hall_floor_1" in items.maintenance_rules.maintenance_maps and "glory_nft_bl_d03" not in items.maintenance_rules.maintenance_maps, "trusted maintenance locations")
	print("Equipment maintenance model: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 记录规则与状态边界断言。
## [param condition] 实际结果。
## [param message] 诊断信息。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
