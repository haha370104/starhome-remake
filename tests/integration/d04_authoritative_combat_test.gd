extends SceneTree

const BridgeScript := preload("res://scripts/client/debug/offline_combat_authority_bridge.gd")
const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")

var failures: Array[String] = []
var assertions := 0


## Verifies D04 configured populations, server-owned vehicle resources, attack settlement and zero-damage evidence handling.
func _initialize() -> void:
	var bridge: OfflineCombatAuthorityBridge = BridgeScript.new()
	root.add_child(bridge)
	var loader = MapDefinitionLoaderScript.new()
	var definition = loader.load_file("res://data/maps/d04_field_zone.json")
	_expect(definition != null, "D04 definition should load")
	var navigation = DiamondNavigationScript.new()
	_expect(
		navigation.load_from(
			definition.navigation_data_path,
			definition.navigation_grid_size,
			definition.navigation_cell_size,
		),
		"D04 navigation should load",
	)
	var configured := bridge.configure_map(
		"d04_field_zone",
		"d04_field_zone.instance.1",
		Vector2(2412, 2400),
		navigation,
	)
	_expect(configured == OK and bridge.module != null, "offline adapter should reuse the authoritative D04 module")
	if bridge.module != null:
		_test_population_and_resources(bridge)
		_test_authoritative_player_attack(bridge)
		_test_zero_attack_is_not_invented(bridge)
	bridge.free()
	if failures.is_empty():
		print("D04_AUTHORITATIVE_COMBAT_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## Checks all four species, configured population and initial vehicle health/energy in [param bridge].
## [param bridge] Configured in-process authority adapter.
func _test_population_and_resources(bridge: OfflineCombatAuthorityBridge) -> void:
	var snapshot := bridge.module.snapshot_for_actor(BridgeScript.LOCAL_ACTOR_ID)
	_expect(snapshot.monsters.size() == 16, "D04 should spawn four configured members of each base species")
	var species: Dictionary = {}
	for monster: Dictionary in snapshot.monsters:
		species[String(monster.species_id)] = int(species.get(String(monster.species_id), 0)) + 1
	_expect(species == {
		"om_adult": 4,
		"om_larva": 4,
		"photosensitive_orb": 4,
		"toxic_gel": 4,
	}, "D04 populations should remain entirely data-driven")
	_expect(snapshot.local_vehicle.health == 70 and snapshot.local_vehicle.max_health == 70, "starter chassis should own 70 health")
	_expect(
		is_equal_approx(snapshot.local_vehicle.working_energy, 100.0)
		and is_equal_approx(snapshot.local_vehicle.working_energy_capacity, 100.0),
		"starter vehicle should expose 100 current working energy",
	)
	var first_id: String = snapshot.monsters[0].entity_id
	var first_position: Vector2 = bridge.module.monster_for(first_id).position
	bridge.module.advance_ticks(60)
	_expect(
		not bridge.module.monster_for(first_id).position.is_equal_approx(first_position),
		"unengaged monsters should roam under deterministic authority ticks",
	)


## Fires at one nearby monster through [param bridge] and verifies authority-owned damage and cost.
## [param bridge] Configured authority adapter whose player coordinate can be moved by validated navigation.
func _test_authoritative_player_attack(bridge: OfflineCombatAuthorityBridge) -> void:
	var target_id: String = bridge.module.monsters.keys()[0]
	var target = bridge.module.monster_for(target_id)
	bridge.update_player_position(target.position + Vector2(100, 0))
	var before_health: int = target.health
	var result := bridge.request_attack(target_id)
	_expect(result.ok, "nearby configured monster should accept a strict target-only attack")
	_expect(target.health == before_health - 7, "new recruit cannon should apply its server-owned base attack 7")
	var vehicle = bridge.module.vehicle_state_for(BridgeScript.LOCAL_ACTOR_ID)
	_expect(is_equal_approx(vehicle.working_energy, 90.0), "successful shot should consume 10 working energy")


## Places the player beside toxic gel and verifies its recovered zero attack remains zero in [param bridge].
## [param bridge] Configured authority adapter containing all D04 species.
func _test_zero_attack_is_not_invented(bridge: OfflineCombatAuthorityBridge) -> void:
	var toxic_id := ""
	for monster_id: String in bridge.module.monster_runtime:
		if String(bridge.module.monster_runtime[monster_id].species_id) == "toxic_gel":
			toxic_id = monster_id
			break
	_expect(not toxic_id.is_empty(), "toxic gel runtime should be present")
	if toxic_id.is_empty():
		return
	var toxic = bridge.module.monster_for(toxic_id)
	bridge.update_player_position(toxic.position + Vector2(40, 0))
	var vehicle = bridge.module.vehicle_state_for(BridgeScript.LOCAL_ACTOR_ID)
	var before_health: int = vehicle.health
	bridge.module.advance_ticks(40)
	_expect(vehicle.health == before_health, "toxic gel must not invent unknown corrosive damage over its confirmed zero base attack")


## Records one assertion [param condition] and failure [param message].
## [param condition] Required test condition.
## [param message] Diagnostic appended when the condition is false.
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
