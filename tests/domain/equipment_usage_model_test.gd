extends SceneTree

var failures: Array[String] = []
var checks := 0


## 检查使用余量、维修资格、服装迁移和持久化，测试物品均独立创建。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "catalog")
	var gun: Equipment = catalog.create("recruit_energy_cannon", {"instance_id": "gun", "durability": 2}).value
	for index: int in 19:
		_check(not gun.record_use("shot"), "not broken before threshold")
	_check(gun.durability == 2, "19 shots accumulate only")
	gun.record_use("shot")
	_check(gun.durability == 1, "20 accepted shots wear one")
	gun.record_use("movement", 600)
	_check(gun.durability == 1, "unrelated usage ignored")
	_check(gun.record_use("shot", 20), "transition to broken")
	_check(not gun.record_use("shot", 20), "broken does not repeatedly invalidate")
	var engine: Equipment = catalog.create("beginner_engine", {"instance_id": "engine"}).value
	var maximum := engine.durability
	engine.record_use("movement", 59.95)
	var saved := engine.to_view_dictionary()
	var restored: Equipment = catalog.create(engine.definition_id, saved).value
	restored.record_use("movement", 0.05)
	_check(restored.durability == maximum - 1, "fractional seconds survive save")
	var chassis: Equipment = catalog.create("recruit_tank", {"instance_id": "tank"}).value
	chassis.record_use("vehicle_movement", 119.95)
	var saved_chassis: Equipment = catalog.create(chassis.definition_id, chassis.to_view_dictionary()).value
	saved_chassis.record_use("vehicle_movement", 0.05)
	_check(saved_chassis.durability == chassis.max_durability - 1, "vehicle body wears after 120 moving seconds across restore")
	var front_armor: Equipment = catalog.create("glory_equipment_frontarmor1_bedd1471a6", {"instance_id": "front"}).value
	var rear_armor: Equipment = catalog.create("glory_equipment_backarmor1_62474fcdc0", {"instance_id": "rear"}).value
	var condition := EquipmentConditionLoadout.new()
	condition._items["tank"] = chassis
	condition._items["front"] = front_armor
	condition._items["rear"] = rear_armor
	condition.record_vehicle_damage(10, [0.25, 0.75])
	_check(chassis.durability == chassis.max_durability - 1 and is_equal_approx(float(chassis.usage.progress.get("vehicle_damage", 0)), 0.05), "two armor pieces assign 60 percent of 1.75 wear to vehicle body")
	_check(is_equal_approx(float(rear_armor.usage.progress.get("vehicle_damage", 0)), 0.525), "random weights assign 0.525 wear to rear armor")
	_check(is_equal_approx(float(front_armor.usage.progress.get("vehicle_damage", 0)), 0.175), "random weights assign 0.175 wear to front armor")
	var durability_before_zero_damage := chassis.durability
	condition.record_vehicle_damage(0, [])
	_check(condition.snapshot()["tank"].durability == durability_before_zero_damage, "zero actual damage adds no wear")
	var one_point_hits: Equipment = catalog.create("recruit_tank", {"instance_id": "two_hits"}).value
	var repeated_hits := EquipmentConditionLoadout.new()
	repeated_hits._items["two_hits"] = one_point_hits
	repeated_hits.record_vehicle_damage(1, [])
	repeated_hits.record_vehicle_damage(1, [])
	_check(one_point_hits.durability == one_point_hits.max_durability - 1, "two one-point hits wear one plus accumulated damage over eight")
	_check(is_equal_approx(float(one_point_hits.usage.progress.get("vehicle_damage", 0)), 0.25), "two one-point hits retain 0.25 fractional wear")
	var destroyed_chassis: Equipment = catalog.create("recruit_tank", {"instance_id": "destroyed", "durability": 100}).value
	var destroyed_condition := EquipmentConditionLoadout.new()
	destroyed_condition._items["destroyed"] = destroyed_chassis
	destroyed_condition.record_vehicle_destroyed()
	_check(destroyed_chassis.durability == 54, "destroyed vehicle loses 20 plus rounded-up 2.5 percent body durability")
	_check(destroyed_condition.needs_durability_sync, "destruction wear requests persistence and panel synchronization")
	for raw: Variant in [{"progress": {"shot": -1}}, {"progress": {"shot": NAN}}, {"progress": {"unknown": 1}}, []]:
		_check(not EquipmentUsage.restore(raw).is_ok, "bad usage rejected")
	var raw_slot := {"owner_kind": "vehicle", "slot_id": "propulsion", "item_instance_id": "engine", "item_definition_id": engine.definition_id,
		"max_durability": engine.max_durability, "durability": engine.durability, "usage": engine.usage.to_dictionary()}
	var slot: EquipmentSlotRecord = EquipmentSlotRecord.from_dictionary(raw_slot).value
	_check(slot.duplicate_record().usage.progress == engine.usage.progress, "equipped record round trip")
	var stack := {"stack_id": "engine", "item_definition_id": engine.definition_id, "slot_index": 0, "quantity": 1,
		"max_durability": engine.max_durability, "durability": engine.durability, "usage": engine.usage.to_dictionary()}
	_check(InventoryStackRecord.from_dictionary(stack).value.duplicate_record().usage.progress == engine.usage.progress, "backpack round trip")
	var clothing := Clothing.new({"id": "shirt", "stats": {"wear_degree": 64}}, {"max_durability": 1, "durability": 1})
	_check(clothing.max_durability == 64 and clothing.durability == 64, "old 1/1 clothing migrated")
	var broken := Clothing.new({"id": "shirt", "stats": {"wear_degree": 64}}, {"max_durability": 1, "durability": 0})
	_check(broken.durability == 0, "broken clothing not healed by migration")
	print("Equipment usage model: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言结果。
## [param condition] 待验证结果。
## [param label] 失败定位描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
