extends SceneTree

var checks := 0
var failures := PackedStringArray()
var catalog := ItemCatalog.new()
var fixture := PlayerPanelServiceFixture.new()
var mapper: PlayerStateMapper
var combat: CombatDefinitionCatalog


## 验证奥斯格兰穿戴、真实属性、运行副本、仓库和预设的完整状态链。
func _initialize() -> void:
	_check(catalog.initialize().is_ok and fixture.initialize().is_ok, "catalog and authority")
	mapper = PlayerStateMapper.new(catalog)
	combat = CombatDefinitionCatalog.load_default().value
	for id: String in catalog.austin_rules.profiles: _equipment(id)
	print("Austin integration: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 对四个独立槽位验证属性变化以及所有实例移动路径。
## [param id] 奥斯格兰定义。
func _equipment(id: String) -> void:
	var player: Player = mapper.to_domain(fixture._state).value
	var profile := catalog.austin_rules.profiles[id]
	var growth := AustinGlensGrowth.new()
	growth.color = 3
	growth.stage = 10
	growth.base = 10
	growth.additional = 10
	growth.blessed = true
	for index in 2:
		growth.change("unlock", profile, catalog.austin_rules, index)
		growth.change("inlay", profile, catalog.austin_rules, index, catalog.austin_rules.rune_at(profile.location, index).definition_id, true)
	var item: VehicleEquipment = catalog.create(id, {"instance_id": "austin.body", "austin_glens": growth.to_dictionary()}).value
	_check(item.bound and item.accepts_location(profile.location), "fixed slot and binding")
	_check(not item.accepts_location(profile.location + 1), "other slot rejected")
	_check(not item.to_view_dictionary().socket_eligible, "not an ordinary socket target")
	_check(not catalog.create("iron_piece", {"austin_glens": growth.to_dictionary()}).is_ok, "foreign material growth rejected")
	_check(not catalog.create("recruit_tank", {"austin_glens": growth.to_dictionary()}).is_ok, "foreign vehicle growth rejected")
	player.vehicle.loadout.equip(catalog.create("starter_missile", {"instance_id": "austin.missile"}).value, 13, player.vehicle.loadout.revision)
	var before := player.vehicle.calculate_stats()
	_check(player.inventory.add_reward(item).is_ok, "bag")
	player.vehicle.health = 29
	player.vehicle.working_energy = 17
	player.vehicle.reserve_energy = 300
	_check(player.equip_vehicle_item(item.instance_id, profile.location, player.inventory.revision, player.vehicle.loadout.revision).is_ok, "equip without invented level gate")
	_check(player.vehicle.health == 29 and player.vehicle.working_energy == 17 and player.vehicle.reserve_energy == 300, "equip preserves resources")
	var after := player.vehicle.calculate_stats()
	for attribute: String in AustinGlensRules.ATTRIBUTES:
		_check(after[attribute] - before[attribute] == item.special_bonus(attribute), "shared passive stat " + attribute)
	var runtime: Dictionary = combat.vehicle_combat_loadout(player, 20, {"base_speed_multiplier": 1500, "base_speed_cap": 240}).value
	_check(runtime.assembly.max_health == after.max_health and runtime.assembly.defense == after.defense, "actual health and defense")
	for weapon: Dictionary in runtime.weapons.values():
		_check(weapon.minimum_damage == after.energy_cannon_attack if weapon.skill_id == "energy_cannon" else weapon.minimum_damage == after.missile_attack, "actual cannon and missile damage")
	var copied := EquipmentConditionLoadout.new(player).duplicate_loadout()
	var copied_item := copied._items[item.instance_id] as VehicleEquipment
	_check(copied_item.austin_glens.to_dictionary() == growth.to_dictionary() and copied_item.austin_rules == catalog.austin_rules, "runtime facts and shared rules")
	copied_item.austin_glens.stage = 1
	_check(item.austin_glens.stage == 10, "runtime growth not aliased")
	var restored := _roundtrip(player)
	_check(restored.vehicle.loadout.at(profile.location).austin_glens.to_dictionary() == growth.to_dictionary(), "equipped JSON")
	_check(restored.vehicle.calculate_stats() == after, "derived stats restored")
	var client := CurrentPlayer.new(catalog)
	_check(client.apply_bundle(fixture._service.build_bundle(mapper.to_record(restored).value)), "client bundle")
	_check(client.vehicle.loadout.at(profile.location).austin_glens.to_dictionary() == growth.to_dictionary(), "client projected growth")
	_check(restored.unequip_vehicle_item(profile.location, restored.inventory.revision, restored.vehicle.loadout.revision).is_ok, "unequip")
	_check(restored.vehicle.health == 29 and restored.vehicle.working_energy == 17 and restored.vehicle.reserve_energy == 300, "unequip preserves absolute resources")
	_check(restored.warehouse.transfer(restored.inventory, 1, true, item.instance_id, 1, restored.inventory.revision, restored.warehouse.revision, "unused").is_ok, "warehouse deposit")
	restored = _roundtrip(restored)
	_check(restored.warehouse.find(item.instance_id).austin_glens.to_dictionary() == growth.to_dictionary(), "warehouse JSON")
	_check(restored.warehouse.transfer(restored.inventory, 1, false, item.instance_id, 1, restored.inventory.revision, restored.warehouse.revision, "unused").is_ok, "withdraw")
	var desired: Array = []
	for equipped: VehicleEquipment in restored.vehicle.loadout.items():
		desired.append({"instance_id": equipped.instance_id, "definition_id": equipped.definition_id, "location": equipped.equipment_location, "display_name": equipped.display_name})
	desired.append({"instance_id": item.instance_id, "definition_id": id, "location": profile.location, "display_name": item.display_name})
	_check(VehicleLoadoutExchange.apply(restored, desired, restored.inventory.revision, restored.vehicle.loadout.revision, false).is_ok, "preset equips same instance")
	_check(restored.vehicle.loadout.at(profile.location).austin_glens.to_dictionary() == growth.to_dictionary(), "preset keeps full growth")
	item.durability = 0
	for attribute: String in AustinGlensRules.ATTRIBUTES: _check(item.special_bonus(attribute) == 0, "damaged passive suppressed")


## 经真正JSON编解码恢复玩家，覆盖数字变成浮点的持久化边界。
## [param player] 当前玩家。
## 返回独立恢复的聚合根。
func _roundtrip(player: Player) -> Player:
	var saved := mapper.to_record(player)
	_check(saved.is_ok, "serialize")
	var parsed := PlayerStateRecord.from_dictionary(JSON.parse_string(JSON.stringify(saved.value.to_dictionary())))
	_check(parsed.is_ok, "JSON record")
	return mapper.to_domain(parsed.value).value


## 汇总端到端不变量。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
