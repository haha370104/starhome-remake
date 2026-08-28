extends SceneTree

const CatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const MonsterLifecycleScript := preload("res://scripts/domain/combat/monster_lifecycle.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")
const MAP_INSTANCE_ID := "d04.instance.catalog-test"

var failures: Array[String] = []
var assertions := 0


## 初始化当前模块或独立测试夹具。
func _initialize() -> void:
	_test_controlled_load_and_read_only_queries()
	_test_formal_starter_definitions()
	_test_d04_lifecycle_definitions()
	_test_catalog_to_authoritative_module_seam()
	if failures.is_empty():
		print("COMBAT_DEFINITION_CATALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 执行 `test_controlled_load_and_read_only_queries` 对应的模块操作。
func _test_controlled_load_and_read_only_queries() -> void:
	var rejected: Variant = CatalogScript.load_file("res://data/maps/map_directory.json")
	_expect(not rejected.is_ok and rejected.error_code == &"combat.catalog_path_not_allowed", "catalog must reject paths outside its controlled root")
	var loaded: Variant = CatalogScript.load_default()
	_expect(loaded.is_ok, "committed stage-three catalog should load")
	if not loaded.is_ok:
		return
	var catalog: Variant = loaded.value
	_expect(catalog.content_version == "stage3_v1", "catalog content version should be explicit")
	var chassis: Dictionary = catalog.equipment_definition("recruit_tank")
	_expect(int(chassis["stats"]["max_health"]) == 70, "catalog should expose confirmed chassis health")
	chassis["stats"]["max_health"] = 999
	_expect(int(catalog.equipment_definition("recruit_tank")["stats"]["max_health"]) == 70, "query results must not mutate catalog state")
	_expect(catalog.equipment_definition("missing").is_empty(), "unknown equipment query should be empty")
	_expect(catalog.monster_definition("missing").is_empty(), "unknown monster query should be empty")


## 执行 `test_formal_starter_definitions` 对应的模块操作。
func _test_formal_starter_definitions() -> void:
	var catalog: Variant = CatalogScript.load_default().value
	var assembly_result: Variant = catalog.starter_vehicle_assembly(
		10, {"base_speed_multiplier": 1500, "base_speed_cap": 240}
	)
	_expect(assembly_result.is_ok, "formal starter assembly should calculate")
	if not assembly_result.is_ok:
		return
	var assembly: Dictionary = assembly_result.value
	_expect(int(assembly["total_weight"]) == 140, "starter chassis, engine and cannon weights should total 140")
	_expect(int(assembly["max_health"]) == 70, "starter combat health must come only from the chassis")
	_expect(not assembly.has("max_durability"), "aggregate combat state must not expose equipment hardiness as health")
	var hardiness: Dictionary = assembly["equipment_hardiness"]
	_expect(int(hardiness["recruit_tank"]) == 1020, "chassis hardiness should remain separate evidence")
	_expect(int(hardiness["beginner_engine"]) == 900, "engine hardiness should remain separate evidence")
	_expect(int(hardiness["recruit_energy_cannon"]) == 900, "cannon hardiness should remain separate evidence")
	_expect(is_equal_approx(float(assembly["effective_propulsion"]), 20.0), "qualified driver should receive full confirmed engine drive")
	_expect(is_equal_approx(float(assembly["movement_speed"]), 214.0), "movement formula should use injected configuration and total weight")
	_expect(is_equal_approx(float(assembly["working_energy_capacity"]), 100.0), "working energy should come from chassis working capacity")
	_expect(is_equal_approx(float(assembly["reserve_energy_capacity"]), 10000.0), "reserve energy should remain a distinct chassis pool")
	_expect(is_equal_approx(float(assembly["power_output"]), 21.0), "output power should remain a distinct non-consumable budget")
	_expect(assembly["unknown_fields"].has("beginner_engine.server_energy_drain_interval_seconds"), "unknown engine drain cadence should remain explicit")
	var weapon_result: Variant = catalog.starter_energy_cannon(20)
	_expect(weapon_result.is_ok, "formal starter cannon should normalize")
	var weapon: Dictionary = weapon_result.value
	_expect(String(weapon["ability_id"]) == "energy_cannon.primary", "starter cannon should use stable ability ID")
	_expect(int(weapon["minimum_damage"]) == 7 and int(weapon["maximum_damage"]) == 7, "confirmed base attack should be the explicit direct model")
	_expect(is_equal_approx(float(weapon["working_energy_cost"]), 10.0), "confirmed shot cost should consume working energy")
	_expect(is_equal_approx(float(weapon["range"]), 250.0), "current attack range should remain 250")
	_expect(is_equal_approx(float(weapon["upgrade_range_limit"]), 400.0), "400 should remain only the equipment-growth limit")
	_expect(int(weapon["cooldown_ticks"]) == 16, "0.8 seconds at 20 Hz should map to 16 ticks")
	_expect(is_equal_approx(float(weapon["projectile_speed"]), 520.0), "server and client should share the reconstructed projectile speed")
	_expect(weapon["muzzle_offset"] == [0.0, -16.0], "authoritative sweep should share the visual muzzle offset")
	_expect(weapon["activation_power"] == null and weapon["unknown_fields"].has("activation_power"), "missing activation power must remain explicit unknown")


## 执行 `test_d04_lifecycle_definitions` 对应的模块操作。
func _test_d04_lifecycle_definitions() -> void:
	var catalog: Variant = CatalogScript.load_default().value
	var lifecycle_result: Variant = catalog.d04_monster_lifecycles(MAP_INSTANCE_ID)
	_expect(lifecycle_result.is_ok, "formal D04 encounter should expand")
	if not lifecycle_result.is_ok:
		return
	var lifecycles: Array = lifecycle_result.value
	_expect(lifecycles.size() == 16, "four D04 groups of four should produce sixteen lifecycle inputs")
	var identities: Dictionary = {}
	var population_by_species: Dictionary = {}
	for raw_definition: Variant in lifecycles:
		var definition: Dictionary = raw_definition
		identities[String(definition["monster_id"])] = true
		var species_id := String(definition["species_id"])
		population_by_species[species_id] = int(population_by_species.get(species_id, 0)) + 1
		_expect(String(definition["map_instance_id"]) == MAP_INSTANCE_ID, "each lifecycle should bind the requested map instance")
		_expect(not definition.has("defense") and not definition.has("move_speed"), "runtime definition must not invent defense or speed")
		_expect(definition["unknown_fields"].has("defense") and definition["unknown_fields"].has("move_speed"), "unknown monster stats should remain explicit")
		_expect(definition["projectile_hitbox"] is Dictionary, "each runtime monster should expose authoritative projectile geometry")
		var attack_archetype := StringName(definition.get("attack_archetype", ""))
		_expect(attack_archetype in [&"ranged_projectile", &"corrosive_projectile", &"contact_melee"], "each monster should expose its source-derived attack archetype")
		if attack_archetype == &"contact_melee":
			_expect(definition.get("runtime_projectile_speed") == null, "contact monsters should not invent a projectile speed")
		elif species_id in ["om_adult", "om_larva"]:
			_expect(
				is_equal_approx(float(definition.get("runtime_projectile_speed", 0.0)), 1000.0 / 2.4),
				"legacy line projectiles should use the recovered nMFly effective speed",
			)
		else:
			_expect(
				float(definition.get("runtime_projectile_speed", 0.0)) > 0.0,
				"duration-driven ranged effects still need explicit provisional authority timing",
			)
	var all_unique := identities.size() == lifecycles.size()
	_expect(all_unique, "expanded monster instance IDs should be unique")
	for species_id: String in ["om_adult", "om_larva", "photosensitive_orb", "toxic_gel"]:
		_expect(int(population_by_species.get(species_id, 0)) == 4, "D04 should preserve population four for %s" % species_id)
	var lifecycle: MonsterLifecycle = MonsterLifecycleScript.new()
	_expect(lifecycle.configure(lifecycles[0], 20).is_ok, "formal D04 definition should initialize MonsterLifecycle directly")
	_expect(lifecycle.max_health == int(lifecycles[0]["max_health"]), "monster lifecycle should preserve formal health semantics")


## 执行 `test_catalog_to_authoritative_module_seam` 对应的模块操作。
func _test_catalog_to_authoritative_module_seam() -> void:
	var catalog: Variant = CatalogScript.load_default().value
	var assembly: Dictionary = catalog.starter_vehicle_assembly(
		10, {"base_speed_multiplier": 1500, "base_speed_cap": 240}
	).value
	var weapon: Dictionary = catalog.starter_energy_cannon(20).value
	var monster: Dictionary = catalog.d04_monster_lifecycles(MAP_INSTANCE_ID).value[0]
	var module: AuthoritativeCombatModule = CombatModuleScript.new()
	_expect(module.configure(20, 24680, 0.0).is_ok, "formal combat module should configure")
	_expect(module.register_vehicle("player.catalog", MAP_INSTANCE_ID, Vector2(monster["position"]) + Vector2(100.0, 0.0), assembly, {weapon["ability_id"]: weapon}).is_ok, "formal starter vehicle and cannon should register")
	_expect(module.register_monster(monster).is_ok, "formal D04 lifecycle should register")
	var intent := UseAbilityIntentContract.new(
		MAP_INSTANCE_ID, weapon["ability_id"], Vector2(monster["position"]), 1
	).to_dictionary()
	var shot := module.handle_energy_cannon_attack("player.catalog", intent)
	_expect(shot.is_ok, "formal catalog definitions should spawn an authoritative projectile")
	if shot.is_ok:
		_expect(int(shot.value["damage"]) == 0, "projectile spawn must not report premature damage")
		_expect(int(shot.value["cooldown_ready_tick"]) == 16, "formal shot should schedule the reconstructed 0.8-second cooldown")
		_expect(module.monster_for(String(monster["monster_id"])).health == int(monster["max_health"]), "formal shot should preserve health before arrival")
		module.advance_ticks(int(shot.value["impact_tick"]) - module.current_tick)
		_expect(module.monster_for(String(monster["monster_id"])).health == int(monster["max_health"]) - 7, "formal impact should apply server-owned base attack at arrival")


## 执行 `expect` 对应的模块操作。
## [param condition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
