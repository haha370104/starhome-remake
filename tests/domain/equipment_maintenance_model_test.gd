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
	_check(items.maintenance_rules.profile("recruit_tank").no_wear, "chassis remains nonwearing")
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
	_check("yian_harbor_hall_floor_1" in items.maintenance_rules.maintenance_maps and "buli_d03_field_zone" not in items.maintenance_rules.maintenance_maps, "trusted maintenance locations")
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
