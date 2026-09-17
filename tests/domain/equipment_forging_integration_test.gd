extends SceneTree

var _checks := 0
var _failures := PackedStringArray()


## 逐件验证锻造上限、实际属性、共享目录隔离和存档往返。
func _initialize() -> void:
	var catalog := ItemCatalog.new()
	_check(catalog.initialize().is_ok, "catalog")
	for id: String in catalog.forging_rules.profiles:
		var profile: EquipmentForgingRules.Profile = catalog.forging_rules.profiles[id]
		for kind: int in profile.limits:
			var channel: EquipmentForgingRules.Channel = catalog.forging_rules.channels[kind]
			var original: Equipment = catalog.create(id, {}).value
			var forged: Equipment = catalog.create(id, {"forging": {"extensions": {str(kind): profile.limits[kind]}}}).value
			var bonus: int = profile.limits[kind] if channel.direct_bonus else 0
			_check(forged.stat(channel.attribute) == original.stat(channel.attribute) + bonus, "direct " + id)
			var base := original.processing_profile()
			var expanded := forged.processing_profile()
			if channel.expands_processing and base.attributes.has(channel.attribute):
				_check(expanded.attributes[channel.attribute].limit == base.attributes[channel.attribute].limit + profile.limits[kind], "expanded cap " + id)
				var view := forged.to_view_dictionary()
				var amount := int(expanded.attributes[channel.attribute].limit - expanded.attributes[channel.attribute].base)
				view.processing = {"increments": {channel.attribute: amount}}
				var processed := catalog.create(id, view)
				_check(processed.is_ok, "process beyond base " + id)
				view.forging = {}
				_check(not catalog.create(id, view).is_ok, "reject unbacked processing " + id)
			_check(original.forging.extensions.is_empty() and catalog.processing_rules.profile(id) == base, "shared catalog unchanged")
			var clone: Equipment = catalog.create(id, forged.to_view_dictionary()).value
			_check(clone.stat(channel.attribute) == forged.stat(channel.attribute), "no double bonus")
			if forged is VehicleWeapon: _check(forged.base_attack == int(forged.stat("base_attack")), "cached attack")
	var fixture := PlayerPanelServiceFixture.new()
	_check(fixture.initialize().is_ok, "fixture")
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	var gun: Equipment = catalog.create("glory_equipment_gun8_e7ce1423fa", {"instance_id": "forge.gun", "forging": {"extensions": {"5": 30}}, "processing": {"increments": {"base_attack": 31}}}).value
	_check(gun != null, "forged gun")
	player.vehicle.loadout.equip(gun, 1, player.vehicle.loadout.revision)
	player.vehicle.reconcile_loadout_state()
	var record: PlayerStateRecord = mapper.to_record(player).value
	var restored: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(record.to_dictionary()).value).value
	_check(restored.vehicle.loadout.at(1).forging.to_dictionary() == gun.forging.to_dictionary(), "equipped round trip")
	var conditions := EquipmentConditionLoadout.new(player).duplicate_loadout()
	_check(conditions._items[gun.instance_id].base_attack == gun.base_attack, "simulation clone")
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(PlayerPanelProjector.new(catalog, {}).build_bundle(restored)), "client bundle")
	player.vehicle.loadout.unequip(1, player.vehicle.loadout.revision)
	_check(player.inventory.add_reward(gun).is_ok, "move forged weapon to bag")
	var bag_record: PlayerStateRecord = mapper.to_record(player).value
	var bag: Player = mapper.to_domain(PlayerStateRecord.from_dictionary(bag_record.to_dictionary()).value).value
	_check(bag.inventory.find(gun.instance_id).forging.to_dictionary() == gun.forging.to_dictionary(), "inventory round trip")
	_check(not catalog.create("iron_piece", {"forging": {"extensions": {"5": 1}}}).is_ok, "reject forging material")
	print("Equipment forging integration: %d checks, %d failures" % [_checks, _failures.size()])
	for failure in _failures: push_error(failure)
	quit(0 if _failures.is_empty() else 1)


## 汇总可定位的断言。
## [param condition] 预期条件。
## [param label] 失败位置。
func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition: _failures.append(label)
