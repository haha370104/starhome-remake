class_name CombatDefinitionCatalog
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const VehicleAssemblyCalculator := preload("res://scripts/domain/combat/vehicle_assembly_calculator.gd")
const DEFAULT_CATALOG_PATH := "res://data/gameplay/stage3/catalog_v1.json"
const CONTROLLED_DATA_ROOT := "res://data/gameplay/stage3/"
const SUPPORTED_SCHEMA_VERSION := 1
const STARTER_ABILITY_ID := "energy_cannon.primary"

var content_version := ""
var _starter_loadout: Dictionary = {}
var _equipment_by_id: Dictionary = {}
var _monsters_by_id: Dictionary = {}
var _d04_encounter: Dictionary = {}


## Loads the committed stage-three catalog through its controlled root document.
## Returns an immutable-query catalog or a stable file/schema validation failure.
static func load_default() -> DomainResult:
	return load_file(DEFAULT_CATALOG_PATH)


## Loads one controlled catalog at [param catalog_path] and all three declared documents.
## [param catalog_path] Catalog path restricted to the stage-three gameplay data directory.
## Returns an immutable-query catalog or a stable validation failure.
## Design: Referenced paths cannot escape the controlled directory or silently omit a required document.
static func load_file(catalog_path: String) -> DomainResult:
	if not _is_controlled_json_path(catalog_path):
		return DomainResult.failure(&"combat.catalog_path_not_allowed", "catalog path is outside the controlled stage-three directory")
	var root_result := _read_json_dictionary(catalog_path)
	if not root_result.is_ok:
		return root_result
	var root: Dictionary = root_result.value
	var header_result := _validate_document_header(root, "catalog")
	if not header_result.is_ok:
		return header_result
	var references: Variant = root.get("definitions")
	if not references is Dictionary:
		return DomainResult.failure(&"combat.invalid_catalog", "catalog definitions must be a dictionary")
	var documents: Dictionary = {}
	for key: String in ["starter_loadout", "monsters", "d04_encounters"]:
		var path := String(references.get(key, ""))
		if not _is_controlled_json_path(path):
			return DomainResult.failure(&"combat.catalog_path_not_allowed", "definition path is outside the controlled stage-three directory")
		var document_result := _read_json_dictionary(path)
		if not document_result.is_ok:
			return document_result
		documents[key] = document_result.value
	var catalog: CombatDefinitionCatalog = load(
		"res://scripts/domain/combat/combat_definition_catalog.gd"
	).new()
	var configured := catalog._configure(root, documents)
	return DomainResult.ok(catalog) if configured.is_ok else configured


## Builds the formal starter vehicle assembly for [param driving_skill_level].
## [param driving_skill_level] Server-owned skill value used by propulsion scaling.
## [param movement_config] Explicit reconstructed movement formula configuration.
## Returns calculated combat stats plus separately preserved equipment-hardiness facts.
## Design: Only chassis `max_health` becomes combat health; equipment hardiness never contributes.
func starter_vehicle_assembly(
	driving_skill_level: int,
	movement_config: Dictionary,
) -> DomainResult:
	var chassis_id := String(_starter_loadout["vehicle_id"])
	var chassis: Dictionary = _equipment_by_id[chassis_id]
	var chassis_stats: Dictionary = chassis["stats"]
	var calculator_chassis := {
		"weight": chassis_stats["weight"],
		"max_health": chassis_stats["max_health"],
		"max_durability": chassis_stats["max_durability"],
		"working_energy_capacity": chassis_stats["working_energy_capacity"],
		"reserve_energy_capacity": chassis_stats["reserve_energy_capacity"],
		"power_output": chassis_stats["output_power"],
	}
	var components: Array[Dictionary] = []
	var equipment_hardiness: Dictionary = {chassis_id: int(chassis_stats["max_durability"])}
	for raw_id: Variant in _starter_loadout["equipped_item_ids"]:
		var equipment_id := String(raw_id)
		var equipment: Dictionary = _equipment_by_id[equipment_id]
		var stats: Dictionary = equipment["stats"]
		var component := {
			"weight": stats["weight"],
			"max_durability": stats["max_durability"],
		}
		if String(equipment["kind"]) == "vehicle_engine":
			component["propulsion"] = stats["drive"]
			component["required_driving_level"] = stats["required_skill_level"]
		components.append(component)
		equipment_hardiness[equipment_id] = int(stats["max_durability"])
	var result := VehicleAssemblyCalculator.calculate(
		calculator_chassis, components, driving_skill_level, movement_config
	)
	if not result.is_ok:
		return result
	var assembly: Dictionary = result.value
	assembly["vehicle_id"] = chassis_id
	assembly["equipment_hardiness"] = equipment_hardiness
	assembly["unknown_fields"] = ["beginner_engine.server_energy_drain_interval_seconds"]
	return DomainResult.ok(assembly)


## Builds the authoritative starter energy-cannon definition for [param simulation_hz].
## [param simulation_hz] Fixed server tick rate used to convert 0.8 seconds to cooldown ticks.
## Returns a definition keyed by `energy_cannon.primary` without inventing activation power.
## Design: The confirmed base attack is used directly while the missing retired-server formula stays explicit.
func starter_energy_cannon(simulation_hz: int) -> DomainResult:
	if simulation_hz <= 0:
		return DomainResult.failure(&"combat.invalid_simulation_hz", "simulation frequency must be positive")
	var equipment: Dictionary = _equipment_by_id["recruit_energy_cannon"]
	var stats: Dictionary = equipment["stats"]
	var interval := float(stats["attack_interval_seconds"])
	var cooldown_ticks := roundi(interval * float(simulation_hz))
	if cooldown_ticks <= 0:
		return DomainResult.failure(&"combat.invalid_weapon_definition", "attack interval resolves to no server ticks")
	return DomainResult.ok({
		"ability_id": STARTER_ABILITY_ID,
		"weapon_id": String(equipment["id"]),
		"minimum_damage": int(stats["base_attack"]),
		"maximum_damage": int(stats["base_attack"]),
		"working_energy_cost": float(stats["working_energy_per_shot"]),
		"activation_power": null,
		"range": float(stats["range"]),
		"upgrade_range_limit": float(stats["range_limit"]),
		"cooldown_ticks": cooldown_ticks,
		"damage_model": &"confirmed_base_attack_direct",
		"unknown_fields": ["activation_power", "server_damage_formula", "server_projectile_speed"],
	})


## Expands the formal D04 encounter into lifecycle definitions for [param map_instance_id].
## [param map_instance_id] Runtime instance identity assigned by the authoritative map server.
## Returns one stable lifecycle definition per configured population member.
## Design: Anchors remain authoritative inputs; later spawn sampling may use the preserved radius.
func d04_monster_lifecycles(map_instance_id: String) -> DomainResult:
	if map_instance_id.is_empty():
		return DomainResult.failure(&"combat.invalid_map_instance", "D04 lifecycle generation requires a map instance")
	if not bool(_d04_encounter["enabled"]):
		return DomainResult.ok([])
	var result: Array[Dictionary] = []
	for raw_group: Variant in _d04_encounter["spawn_groups"]:
		var group: Dictionary = raw_group
		var species_id := String(group["monster_id"])
		var species: Dictionary = _monsters_by_id[species_id]
		var stats: Dictionary = species["stats"]
		var combat: Dictionary = species["combat"]
		var anchor_values: Array = group["anchor"]
		var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1]))
		for spawn_index: int in range(int(group["population"])):
			result.append({
				"monster_id": "%s.%s.%d" % [_d04_encounter["encounter_id"], group["group_id"], spawn_index],
				"species_id": species_id,
				"map_instance_id": map_instance_id,
				"position": anchor,
				"spawn_anchor": anchor,
				"spawn_radius": float(group["spawn_radius"]),
				"spawn_index": spawn_index,
				"max_health": int(stats["max_health"]),
				"base_attack": int(stats["base_attack"]),
				"respawn_seconds": float(combat["respawn_seconds"]),
				"unknown_fields": _unknown_monster_fields(stats),
			})
	return DomainResult.ok(result)


## Retrieves a defensive copy of equipment [param equipment_id].
## [param equipment_id] Stable equipment ID declared by the starter document.
## Returns the full evidence-bearing definition, or an empty dictionary when unknown.
func equipment_definition(equipment_id: String) -> Dictionary:
	var definition: Variant = _equipment_by_id.get(equipment_id)
	return definition.duplicate(true) if definition is Dictionary else {}


## Retrieves a defensive copy of monster species [param species_id].
## [param species_id] Stable monster ID declared by the monster document.
## Returns the full evidence-bearing definition, or an empty dictionary when unknown.
func monster_definition(species_id: String) -> Dictionary:
	var definition: Variant = _monsters_by_id.get(species_id)
	return definition.duplicate(true) if definition is Dictionary else {}


## Validates and indexes the root [param catalog] with [param documents].
## [param catalog] Already parsed catalog root.
## [param documents] Required parsed documents keyed by their catalog role.
## Returns success after one-time initialization or a stable schema failure.
func _configure(catalog: Dictionary, documents: Dictionary) -> DomainResult:
	content_version = String(catalog.get("content_version", ""))
	for key: String in ["starter_loadout", "monsters", "d04_encounters"]:
		var document: Dictionary = documents[key]
		var header_result := _validate_document_header(document, key)
		if not header_result.is_ok:
			return header_result
		if String(document["content_version"]) != content_version:
			return DomainResult.failure(&"combat.catalog_version_mismatch", "catalog documents must share one content version")
	_starter_loadout = documents["starter_loadout"].duplicate(true)
	_d04_encounter = documents["d04_encounters"].duplicate(true)
	var equipment_result := _index_definitions(_starter_loadout.get("definitions"), _equipment_by_id, "equipment")
	if not equipment_result.is_ok:
		return equipment_result
	var monster_document: Dictionary = documents["monsters"]
	var monster_result := _index_definitions(monster_document.get("definitions"), _monsters_by_id, "monster")
	if not monster_result.is_ok:
		return monster_result
	return _validate_runtime_links()


## Indexes [param raw_definitions] into [param destination] with unique IDs.
## [param raw_definitions] JSON array of definition dictionaries.
## [param destination] Private catalog index populated only after validation.
## [param context] Diagnostic name used by stable errors.
## Returns success or a malformed/duplicate definition failure.
func _index_definitions(raw_definitions: Variant, destination: Dictionary, context: String) -> DomainResult:
	if not raw_definitions is Array:
		return DomainResult.failure(&"combat.invalid_catalog", "%s definitions must be an array" % context)
	for raw_definition: Variant in raw_definitions:
		if not raw_definition is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "%s definition must be a dictionary" % context)
		var definition: Dictionary = raw_definition
		var definition_id := String(definition.get("id", ""))
		if definition_id.is_empty() or destination.has(definition_id):
			return DomainResult.failure(&"combat.invalid_catalog", "%s definition ID is empty or duplicated" % context)
		if not definition.get("stats") is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "%s stats must be a dictionary" % context)
		destination[definition_id] = definition.duplicate(true)
	return DomainResult.ok()


## Validates loadout, encounter and unknown-field links after indexing.
## Returns success when every runtime reference is explicit and well formed.
func _validate_runtime_links() -> DomainResult:
	var vehicle_id := String(_starter_loadout.get("vehicle_id", ""))
	if not _equipment_by_id.has(vehicle_id) or String(_equipment_by_id[vehicle_id].get("kind")) != "vehicle_chassis":
		return DomainResult.failure(&"combat.invalid_catalog", "starter chassis reference is unresolved")
	var equipped: Variant = _starter_loadout.get("equipped_item_ids")
	if not equipped is Array or not equipped.has("beginner_engine") or not equipped.has("recruit_energy_cannon"):
		return DomainResult.failure(&"combat.invalid_catalog", "starter equipped-item references are incomplete")
	for raw_id: Variant in equipped:
		if not _equipment_by_id.has(String(raw_id)):
			return DomainResult.failure(&"combat.invalid_catalog", "starter equipment reference is unresolved")
	var groups: Variant = _d04_encounter.get("spawn_groups")
	if String(_d04_encounter.get("map_id", "")) != "d04_field_zone" or not groups is Array:
		return DomainResult.failure(&"combat.invalid_catalog", "D04 encounter identity or spawn groups are invalid")
	for raw_group: Variant in groups:
		if not raw_group is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "D04 spawn group must be a dictionary")
		var group: Dictionary = raw_group
		var anchor: Variant = group.get("anchor")
		if not _monsters_by_id.has(String(group.get("monster_id", ""))) \
			or not anchor is Array or anchor.size() != 2 \
			or int(group.get("population", 0)) <= 0 or float(group.get("spawn_radius", -1.0)) < 0.0:
			return DomainResult.failure(&"combat.invalid_catalog", "D04 spawn group contains unresolved or invalid data")
	for species: Dictionary in _monsters_by_id.values():
		var stats: Dictionary = species["stats"]
		if not stats.has("defense") or stats["defense"] != null \
			or not stats.has("move_speed") or stats["move_speed"] != null:
			return DomainResult.failure(&"combat.invalid_catalog", "unknown monster defense and speed must remain explicit nulls")
	return DomainResult.ok()


## Collects explicit unknown stat names from [param stats].
## [param stats] Validated monster stat dictionary whose nulls carry unknown semantics.
## Returns names of null fields without assigning runtime defaults.
static func _unknown_monster_fields(stats: Dictionary) -> Array[String]:
	var fields: Array[String] = []
	for field_name: String in ["defense", "move_speed"]:
		if stats.get(field_name) == null:
			fields.append(field_name)
	return fields


## Validates schema metadata on [param document] from [param context].
## [param document] Parsed JSON root dictionary.
## [param context] Human-readable document role used in failures.
## Returns success only for supported schema and non-empty content version.
static func _validate_document_header(document: Dictionary, context: String) -> DomainResult:
	if int(document.get("schema_version", -1)) != SUPPORTED_SCHEMA_VERSION:
		return DomainResult.failure(&"combat.unsupported_catalog_schema", "%s schema version is unsupported" % context)
	if String(document.get("content_version", "")).is_empty():
		return DomainResult.failure(&"combat.invalid_catalog", "%s content version is missing" % context)
	return DomainResult.ok()


## Reads a JSON dictionary from controlled [param path].
## [param path] Existing stage-three JSON resource path.
## Returns the parsed dictionary or a stable I/O/JSON failure.
static func _read_json_dictionary(path: String) -> DomainResult:
	if not FileAccess.file_exists(path):
		return DomainResult.failure(&"combat.catalog_file_missing", "catalog document does not exist: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return DomainResult.failure(&"combat.invalid_catalog_json", "catalog document root must be a JSON object: %s" % path)
	return DomainResult.ok(parsed)


## Reports whether [param path] is a normalized controlled stage-three JSON path.
## [param path] Candidate Godot resource path from a catalog reference.
## Returns true only inside the allowed root without parent traversal.
static func _is_controlled_json_path(path: String) -> bool:
	return path.begins_with(CONTROLLED_DATA_ROOT) \
		and path.ends_with(".json") \
		and not path.contains("..")
