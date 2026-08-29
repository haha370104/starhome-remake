class_name CombatDefinitionCatalog
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const VehicleAssemblyCalculator := preload("res://scripts/domain/combat/vehicle_assembly_calculator.gd")
const DEFAULT_CATALOG_PATH := "res://data/gameplay/stage3/catalog_v1.json"
const CONTROLLED_DATA_ROOT := "res://data/gameplay/stage3/"
const SUPPORTED_SCHEMA_VERSION := 1
const STARTER_ABILITY_ID := "energy_cannon.primary"
const STARTER_ROCKET_ABILITY_ID := "rocket_launcher.primary"
const STARTER_MISSILE_ABILITY_ID := "missile.primary"

var content_version := ""
var _starter_loadout: Dictionary = {}
var _equipment_by_id: Dictionary = {}
var _monsters_by_id: Dictionary = {}
var _d04_encounter: Dictionary = {}


## 加载并校验 `load_default` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
static func load_default() -> DomainResult:
	return load_file(DEFAULT_CATALOG_PATH)


## 执行 `load_file` 对应的模块操作。
## [param catalog_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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


## 执行 `starter_vehicle_assembly` 对应的模块操作。
## [param driving_skill_level] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param movement_config] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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
	assembly["self_repair_base_strength"] = int(chassis_stats["repair_strength"])
	assembly["self_repair_energy_cost"] = float(chassis_stats["repair_energy_cost"])
	assembly["equipment_hardiness"] = equipment_hardiness
	assembly["unknown_fields"] = ["beginner_engine.server_energy_drain_interval_seconds"]
	return DomainResult.ok(assembly)


## 执行 `starter_energy_cannon` 对应的模块操作。
## [param simulation_hz] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
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
		"skill_id": "energy_cannon",
		"attack_mode": "line_projectile",
		"minimum_damage": int(stats["base_attack"]),
		"maximum_damage": int(stats["base_attack"]),
		"working_energy_cost": float(stats["working_energy_per_shot"]),
		"activation_power": null,
		"range": float(stats["range"]),
		"upgrade_range_limit": float(stats["range_limit"]),
		"cooldown_ticks": cooldown_ticks,
		"projectile_speed": float(stats["runtime_projectile_speed"]),
		"muzzle_offset": (stats["runtime_muzzle_offset"] as Array).duplicate(),
		"muzzle_forward_offset": float(stats["runtime_muzzle_forward_offset"]),
		"damage_model": &"confirmed_base_attack_direct",
		"unknown_fields": ["activation_power", "server_damage_formula", "original_server_projectile_speed"],
	})


## 规范化荣耀版初级火箭和初级导弹定义，供同一权威武器状态机消费。
func starter_secondary_weapons(simulation_hz: int) -> DomainResult:
	if simulation_hz <= 0:
		return DomainResult.failure(&"combat.invalid_simulation_hz", "simulation frequency must be positive")
	var result: Dictionary = {}
	for specification: Dictionary in [
		{
			"equipment_id": "starter_rocket_launcher",
			"ability_id": STARTER_ROCKET_ABILITY_ID,
			"skill_id": "rocket_launcher",
			"attack_mode": "rocket_aoe",
			"range_field": "range",
		},
		{
			"equipment_id": "starter_missile",
			"ability_id": STARTER_MISSILE_ABILITY_ID,
			"skill_id": "missile",
			"attack_mode": "homing_missile",
			"range_field": "lock_range",
		},
	]:
		var equipment: Dictionary = _equipment_by_id[specification["equipment_id"]]
		var stats: Dictionary = equipment["stats"]
		var weapon := {
			"ability_id": specification["ability_id"],
			"weapon_id": specification["equipment_id"],
			"skill_id": specification["skill_id"],
			"attack_mode": specification["attack_mode"],
			"minimum_damage": int(stats["base_attack"]),
			"maximum_damage": int(stats["base_attack"]),
			"working_energy_cost": float(stats["working_energy_per_shot"]),
			"activation_power": null,
			"range": float(stats[specification["range_field"]]),
			"minimum_range": float(stats.get("minimum_range", 0.0)),
			"cooldown_ticks": roundi(float(stats["attack_interval_seconds"]) * simulation_hz),
			"projectile_speed": float(stats["runtime_projectile_speed"]),
			"muzzle_offset": (stats["runtime_muzzle_offset"] as Array).duplicate(),
			"muzzle_forward_offset": float(stats["runtime_muzzle_forward_offset"]),
			"area_radius": float(stats.get("runtime_area_radius", 0.0)),
			"target_selection_radius": float(stats.get("runtime_target_selection_radius", 0.0)),
		}
		result[String(weapon["ability_id"])] = weapon
	return DomainResult.ok(result)


## 执行 `d04_monster_lifecycles` 对应的模块操作。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func d04_monster_lifecycles(map_instance_id: String) -> DomainResult:
	return monster_lifecycles_for_map("d04_field_zone", map_instance_id)


## 执行 `monster_lifecycles_for_map` 对应的模块操作。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func monster_lifecycles_for_map(map_id: String, map_instance_id: String) -> DomainResult:
	if map_instance_id.is_empty():
		return DomainResult.failure(&"combat.invalid_map_instance", "monster lifecycle generation requires a map instance")
	if map_id != String(_d04_encounter["map_id"]):
		return DomainResult.ok([])
	if not bool(_d04_encounter["enabled"]):
		return DomainResult.ok([])
	var policy := monster_population_policy_for_map(map_id)
	return monster_replenishment_for_map(
		map_id, map_instance_id, {}, 0, int(policy.get("maximum_population", 0))
	)


## 查询地图级怪物种群策略并隔离目录内部配置。
## [param map_id] 待查询的业务地图标识。
## 返回启用地图的种群策略副本；无配置时返回空字典。
## 设计：调用方不得持有并修改目录内部配置。
func monster_population_policy_for_map(map_id: String) -> Dictionary:
	if map_id != String(_d04_encounter.get("map_id", "")) or not bool(_d04_encounter.get("enabled", false)):
		return {}
	return (_d04_encounter.get("population_policy", {}) as Dictionary).duplicate(true)


## 计算本轮应补数量；阈值采用严格小于，结果始终受地图上限钳制。
## [param map_id] 待计算补量的业务地图标识。
## [param alive_count] 当前存活怪物总数。
## 返回本轮允许生成且不超过地图上限的数量。
func monster_replenishment_count(map_id: String, alive_count: int) -> int:
	var policy := monster_population_policy_for_map(map_id)
	if policy.is_empty():
		return 0
	var maximum := int(policy["maximum_population"])
	var admitted_alive := clampi(alive_count, 0, maximum)
	var ratio := float(admitted_alive) / float(maximum)
	var replenish_ratio := float(policy["normal_replenish_ratio"])
	if ratio < float(policy["critical_threshold_ratio"]):
		replenish_ratio = float(policy["critical_replenish_ratio"])
	elif ratio < float(policy["low_threshold_ratio"]):
		replenish_ratio = float(policy["low_replenish_ratio"])
	return mini(maximum - admitted_alive, roundi(float(maximum) * replenish_ratio))


## 按配置权重与当前物种缺口生成一批新的怪物生命周期定义。
## 每次选择 `(现存+本批)/权重` 最小的物种，使长期比例逼近配置权重。
## [param map_id] 待补充的业务地图标识。
## [param map_instance_id] 接收新怪物的权威地图实例标识。
## [param alive_by_species] 各物种当前存活数量。
## [param first_sequence] 本批实例稳定序号的起点。
## [param requested_count] 本轮期望生成数量。
## 返回按权重生成的怪物定义数组或配置错误。
func monster_replenishment_for_map(
	map_id: String,
	map_instance_id: String,
	alive_by_species: Dictionary,
	first_sequence: int,
	requested_count: int,
) -> DomainResult:
	if map_instance_id.is_empty() or first_sequence < 0 or requested_count < 0:
		return DomainResult.failure(&"combat.invalid_population_request", "monster replenishment request is invalid")
	if map_id != String(_d04_encounter.get("map_id", "")) or not bool(_d04_encounter.get("enabled", false)):
		return DomainResult.ok([])
	var groups: Array = _d04_encounter["spawn_groups"]
	var working_counts := alive_by_species.duplicate()
	var result: Array[Dictionary] = []
	for batch_index: int in range(requested_count):
		var selected_group: Dictionary = groups[0]
		var selected_score := INF
		for raw_group: Variant in groups:
			var candidate: Dictionary = raw_group
			var candidate_species := String(candidate["monster_id"])
			var score := float(working_counts.get(candidate_species, 0)) / float(candidate["weight"])
			if score < selected_score:
				selected_score = score
				selected_group = candidate
		var species_id := String(selected_group["monster_id"])
		var species_count := int(working_counts.get(species_id, 0))
		var sequence := first_sequence + batch_index
		result.append(_monster_lifecycle_definition(
			selected_group, map_instance_id, sequence, species_count
		))
		working_counts[species_id] = species_count + 1
	return DomainResult.ok(result)


## 将一个种群组配置组装为可登记的怪物生命周期定义。
## [param group] 含物种、锚点、半径和权重的生成组。
## [param map_instance_id] 新怪物所属权威地图实例。
## [param sequence] 新怪物的全局生成序号。
## [param species_count] 该物种在生成本只前的数量。
## 返回包含数值、AI、掉落和确定性生成位置的完整定义。
## 设计：目录只生成领域数据，不直接创建运行时怪物对象。
func _monster_lifecycle_definition(
	group: Dictionary,
	map_instance_id: String,
	sequence: int,
	species_count: int,
) -> Dictionary:
	var species_id := String(group["monster_id"])
	var species: Dictionary = _monsters_by_id[species_id]
	var stats: Dictionary = species["stats"]
	var combat: Dictionary = species["combat"]
	var anchor_values: Array = group["anchor"]
	var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1]))
	var angle := float(species_count) * 2.399963229728653
	var normalized_ring := sqrt(float(posmod(species_count, 25) + 1) / 25.0)
	var spawn_position := anchor + Vector2(cos(angle), sin(angle)) \
		* float(group["spawn_radius"]) * normalized_ring
	return {
				"monster_id": "%s.population.%d" % [_d04_encounter["encounter_id"], sequence],
				"species_id": species_id,
				"map_instance_id": map_instance_id,
				"position": spawn_position,
				"spawn_anchor": anchor,
				"spawn_radius": float(group["spawn_radius"]),
				"spawn_index": sequence,
				"max_health": int(stats["max_health"]),
				"base_attack": int(stats["base_attack"]),
				"attack_archetype": String(combat["attack_archetype"]),
				"behavior_profile": String(combat["behavior_profile"]),
				"engagement_policy": String(combat["engagement_policy"]),
				"runtime_move_speed": float(combat["runtime_move_speed"]),
				"attack_range": float(combat["attack_range"]),
				"aggro_radius": float(combat["aggro_radius"]),
				"leash_distance": float(combat["leash_distance"]),
				"wander_radius": float(combat["wander_radius"]),
				"wander_interval_seconds": float(combat.get("wander_interval_seconds", 5.0)),
				"attack_interval_seconds": float(combat["attack_interval_seconds"]),
				"runtime_projectile_speed": combat["runtime_projectile_speed"],
				"projectile_hitbox": (combat["projectile_hitbox"] as Dictionary).duplicate(true),
				"display_name": String(species["display_name"]),
				"combat_actor_id": String(species["combat_actor_id"]),
				"respawn_seconds": float(combat["respawn_seconds"]),
				"population_managed": true,
				"drops": (species.get("drops") as Array).duplicate(true)
					if species.get("drops") is Array else null,
				"unknown_fields": _unknown_monster_fields(stats),
			}


## 执行 `equipment_definition` 对应的模块操作。
## [param equipment_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func equipment_definition(equipment_id: String) -> Dictionary:
	var definition: Variant = _equipment_by_id.get(equipment_id)
	return definition.duplicate(true) if definition is Dictionary else {}


## 执行 `monster_definition` 对应的模块操作。
## [param species_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func monster_definition(species_id: String) -> Dictionary:
	var definition: Variant = _monsters_by_id.get(species_id)
	return definition.duplicate(true) if definition is Dictionary else {}


## 执行 `configure` 对应的模块操作。
## [param catalog] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param documents] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
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


## 执行 `index_definitions` 对应的模块操作。
## [param raw_definitions] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param destination] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param context] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
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


## 校验 `validate_runtime_links` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
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
	for weapon_id: String in ["starter_rocket_launcher", "starter_missile"]:
		if not _equipment_by_id.has(weapon_id):
			return DomainResult.failure(&"combat.invalid_catalog", "starter secondary weapon is unresolved")
	var groups: Variant = _d04_encounter.get("spawn_groups")
	var policy: Variant = _d04_encounter.get("population_policy")
	if String(_d04_encounter.get("map_id", "")) != "d04_field_zone" or not groups is Array:
		return DomainResult.failure(&"combat.invalid_catalog", "D04 encounter identity or spawn groups are invalid")
	if not policy is Dictionary or int(policy.get("maximum_population", 0)) <= 0 \
		or float(policy.get("replenish_interval_seconds", 0.0)) <= 0.0:
		return DomainResult.failure(&"combat.invalid_catalog", "D04 population policy is invalid")
	for raw_group: Variant in groups:
		if not raw_group is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "D04 spawn group must be a dictionary")
		var group: Dictionary = raw_group
		var anchor: Variant = group.get("anchor")
		if not _monsters_by_id.has(String(group.get("monster_id", ""))) \
			or not anchor is Array or anchor.size() != 2 \
			or float(group.get("weight", 0.0)) <= 0.0 or float(group.get("spawn_radius", -1.0)) < 0.0:
			return DomainResult.failure(&"combat.invalid_catalog", "D04 spawn group contains unresolved or invalid data")
	for species: Dictionary in _monsters_by_id.values():
		var stats: Dictionary = species["stats"]
		var combat: Dictionary = species.get("combat", {})
		if not stats.has("defense") or stats["defense"] != null \
			or not stats.has("move_speed") or stats["move_speed"] != null:
			return DomainResult.failure(&"combat.invalid_catalog", "unknown monster defense and speed must remain explicit nulls")
		if StringName(combat.get("engagement_policy", "")) not in [
			&"unresponsive", &"retaliatory", &"aggressive"
		]:
			return DomainResult.failure(&"combat.invalid_catalog", "monster engagement policy is invalid")
		var attack_archetype := StringName(combat.get("attack_archetype", ""))
		if attack_archetype not in [&"ranged_projectile", &"corrosive_projectile", &"contact_melee"]:
			return DomainResult.failure(&"combat.invalid_catalog", "monster attack archetype is invalid")
		var projectile_speed: Variant = combat.get("runtime_projectile_speed")
		if attack_archetype == &"contact_melee":
			if projectile_speed != null:
				return DomainResult.failure(&"combat.invalid_catalog", "contact monster must not define projectile speed")
		elif typeof(projectile_speed) not in [TYPE_INT, TYPE_FLOAT] or float(projectile_speed) <= 0.0:
			return DomainResult.failure(&"combat.invalid_catalog", "ranged monster projectile speed is invalid")
		var projectile_hitbox: Variant = combat.get("projectile_hitbox")
		if not projectile_hitbox is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "monster projectile hitbox is missing")
		var hitbox_offset: Variant = (projectile_hitbox as Dictionary).get("offset")
		if not hitbox_offset is Array or hitbox_offset.size() != 2 \
			or float((projectile_hitbox as Dictionary).get("radius", 0.0)) <= 0.0:
			return DomainResult.failure(&"combat.invalid_catalog", "monster projectile hitbox is invalid")
		if float(combat.get("wander_interval_seconds", -1.0)) < 0.0:
			return DomainResult.failure(&"combat.invalid_catalog", "monster wander interval is invalid")
	return DomainResult.ok()


## 执行 `unknown_monster_fields` 对应的模块操作。
## [param stats] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _unknown_monster_fields(stats: Dictionary) -> Array[String]:
	var fields: Array[String] = []
	for field_name: String in ["defense", "move_speed"]:
		if stats.get(field_name) == null:
			fields.append(field_name)
	return fields


## 执行 `validate_document_header` 对应的模块操作。
## [param document] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param context] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _validate_document_header(document: Dictionary, context: String) -> DomainResult:
	if int(document.get("schema_version", -1)) != SUPPORTED_SCHEMA_VERSION:
		return DomainResult.failure(&"combat.unsupported_catalog_schema", "%s schema version is unsupported" % context)
	if String(document.get("content_version", "")).is_empty():
		return DomainResult.failure(&"combat.invalid_catalog", "%s content version is missing" % context)
	return DomainResult.ok()


## 执行 `read_json_dictionary` 对应的模块操作。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _read_json_dictionary(path: String) -> DomainResult:
	if not FileAccess.file_exists(path):
		return DomainResult.failure(&"combat.catalog_file_missing", "catalog document does not exist: %s" % path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return DomainResult.failure(&"combat.invalid_catalog_json", "catalog document root must be a JSON object: %s" % path)
	return DomainResult.ok(parsed)


## 执行 `is_controlled_json_path` 对应的模块操作。
## [param path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _is_controlled_json_path(path: String) -> bool:
	return path.begins_with(CONTROLLED_DATA_ROOT) \
		and path.ends_with(".json") \
		and not path.contains("..")
