extends SceneTree

var _checks := 0
var _failures := 0


## 遍历全部精工资格、原版概率和下一阶属性，并验证晶石与磨损不丢失。
func _initialize() -> void:
	var items := ItemCatalog.new()
	_check(items.initialize().is_ok, "catalog")
	var rules := items.armor_refinement_rules
	_check(rules.profiles.size() == 40, "all original profiles")
	var chips: ArmorRefinementMaterial = items.create("armor_refinement_chip", {"instance_id": "chip"}).value
	for profile: ArmorRefinementRules.Profile in rules.profiles.values():
		var armor: VehicleEquipment = items.create(profile.definition_id, {"instance_id": "armor"}).value
		_check(armor.armor_refinement_profile == profile, "typed profile")
		if profile.level == 8:
			_check(not rules.preview(profile, chips, 10).is_ok, "terminal")
			continue
		var material_id: String = "armor_refinement_" + (["front_stone", "back_stone", "left_stone", "right_stone"][profile.location - 5] if profile.level >= 4 else "chip")
		var material: ArmorRefinementMaterial = items.create(material_id, {"instance_id": "material"}).value
		var maximum := 4 if profile.level >= 4 else 10
		for quantity: int in range(1, maximum + 1):
			var quote := rules.preview(profile, material, quantity)
			_check(quote.is_ok and quote.value.after == profile.level + 1, "next tier")
			var expected: float = [0.1, 0.3, 0.6, 1.0][quantity - 1] if profile.level >= 4 else minf(1, (30 + pow(quantity - 1, 2)) / 100.0)
			_check(is_equal_approx(quote.value.chance, expected), "original chances")
		_check(not rules.preview(profile, material, 0).is_ok and not rules.preview(profile, material, 100).is_ok, "quantity bounds")
		var wrong: ArmorRefinementMaterial = items.create("armor_refinement_" + ("back_stone" if profile.location == 5 else "front_stone"), {"instance_id": "wrong"}).value
		_check(not rules.preview(profile, wrong, 1).is_ok, "material matching")
		if profile.level >= 4: _check(not rules.preview(profile, chips, 10).is_ok and not rules.preview(profile, material, 5).is_ok, "high armor restrictions")
		armor.max_durability -= 11
		armor.durability = armor.max_durability - 80
		if armor.sockets.capacity() > 0:
			armor.sockets.settle_open(0, true, "")
			var crystal: VehicleCrystal = items.create("bright_health_crystal", {"instance_id": "crystal", "crystal_cracks": 2, "bound": true}).value
			_check(armor.sockets.inlay(0, crystal).is_ok, "socket fixture")
		var before := armor.to_view_dictionary()
		var target: VehicleEquipment = items.create(profile.next_definition_id, {"instance_id": "template"}).value
		var state := ArmorRefinement.replacement_state(armor, target, true)
		_check(state.is_ok and before == armor.to_view_dictionary(), "isolated conversion")
		var converted := items.create(profile.next_definition_id, state.value)
		_check(converted.is_ok, "strict transformed factory")
		if not converted.is_ok: continue
		var result: VehicleEquipment = converted.value
		_check(result.instance_id == armor.instance_id and result.bound and result.armor_refinement_profile.level == profile.level + 1, "identity and tier")
		_check(result.max_durability == target.max_durability - 11 and result.durability == result.max_durability - 80, "no free repair")
		_check(result.upgrade_level == 0 and result.strengthening.level == 0, "independent growth")
		_check(result.sockets.capacity() == profile.level, "new original slot capacity")
		if armor.sockets.capacity() > 0:
			_check(result.sockets.slot_at(0).to_dictionary() == armor.sockets.slot_at(0).to_dictionary(), "crystal, cracks and binding preserved")
		_check(not result.sockets.slot_at(result.sockets.capacity() - 1).opened, "new slot stays closed")
	print("Armor refinement: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 记录领域断言。
## [param condition] 实际结果。
## [param label] 诊断标签。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(label)
