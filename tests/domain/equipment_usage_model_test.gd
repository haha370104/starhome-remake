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
	chassis.record_use("movement", 100000)
	_check(chassis.durability == chassis.max_durability, "no wear chassis")
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
