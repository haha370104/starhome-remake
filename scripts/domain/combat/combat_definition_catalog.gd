class_name CombatDefinitionCatalog
extends RefCounted

const DEFAULT_CATALOG_PATH := "res://data/gameplay/stage3/catalog_v1.json"
const CONTROLLED_DATA_ROOT := "res://data/gameplay/"
const SUPPORTED_SCHEMA_VERSION := 1
const STARTER_ABILITY_ID := "energy_cannon.primary"
const STARTER_ROCKET_ABILITY_ID := "rocket_launcher.primary"
const STARTER_MISSILE_ABILITY_ID := "missile.primary"

var content_version := ""
var _starter_loadout: Dictionary = {}
var _equipment_by_id: Dictionary = {}
var _monsters_by_id: Dictionary = {}
var _d04_encounter: Dictionary = {}
var _encounters_by_map_id: Dictionary = {}


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
	for key: String in [
		"starter_loadout", "monsters", "d04_encounters", "glory_monsters", "glory_encounters", "material_drops", "enhancement_monsters"
	]:
		if key in ["material_drops", "enhancement_monsters"] and not references.has(key):
			continue
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
	var self_repair_bonus_strength := maxi(0, int(chassis_stats.get("self_repair_bonus", 0)))
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
		self_repair_bonus_strength += maxi(0, int(stats.get("self_repair_bonus", 0)))
		equipment_hardiness[equipment_id] = int(stats["max_durability"])
	var result := VehicleAssemblyCalculator.calculate(
		calculator_chassis, components, driving_skill_level, movement_config
	)
	if not result.is_ok:
		return result
	var assembly: Dictionary = result.value
	assembly["vehicle_id"] = chassis_id
	assembly["self_repair_base_strength"] = int(chassis_stats["repair_strength"])
	assembly["self_repair_bonus_strength"] = self_repair_bonus_strength
	assembly["self_repair_energy_cost"] = float(chassis_stats["repair_energy_cost"])
	assembly["self_repair_required_skill_level"] = int(chassis_stats["repair_skill_level"])
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
## [param simulation_hz] 权威服务器每秒模拟刻数。
## 返回成功时携带两种副武器定义的领域结果。
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


## 从玩家当前固定装配对象生成该玩家独有的权威战车装配与武器定义。
## [param player] 已由共享持久化映射器还原的 Player 聚合。
## [param simulation_hz] 权威服务器每秒模拟刻数。
## [param movement_config] 战车重量、推进力到移动速度的服务器规则。
## 返回 assembly 与 weapons 字典；缺少底盘或主装置时返回领域错误，采掘臂不登记主炮攻击。
## 设计：loadout 是唯一装备事实来源；新兵目录仅为待证实的弹道常量提供回退。
func vehicle_combat_loadout(
	player: Player,
	simulation_hz: int,
	movement_config: Dictionary,
) -> DomainResult:
	if player == null or simulation_hz <= 0:
		return DomainResult.failure(&"combat.invalid_player_loadout", "player combat loadout is unavailable")
	var stats := player.calculate_vehicle_stats()
	var clothing := player.vehicle.clothing_bonuses
	var chassis := player.vehicle.loadout.at(0) as VehicleChassis
	var primary_weapon := player.vehicle.loadout.at(1)
	if chassis == null:
		return DomainResult.failure(
			&"equipment.chassis_required_for_field",
			"a vehicle chassis is required before entering a field map",
		)
	if not primary_weapon is VehicleWeapon and not primary_weapon is VehicleMiningArm:
		return DomainResult.failure(
			&"equipment.primary_weapon_required_for_field",
			"a primary weapon is required before entering a field map",
		)
	var calculator_chassis := {
		"weight": chassis.weight,
		"max_health": chassis.base_max_health + player.vehicle.achievement_bonuses.max_health + player.vehicle.loadout.attachment_bonus("max_health") + player.food_status.bonus(16),
		"max_durability": chassis.max_durability,
		"working_energy_capacity": chassis.working_energy_capacity,
		"reserve_energy_capacity": chassis.reserve_energy_capacity,
		"power_output": chassis.output_power,
	}
	var components: Array[Dictionary] = []
	var equipment_hardiness: Dictionary = {chassis.definition_id: chassis.max_durability}
	for equipment: VehicleEquipment in player.vehicle.loadout.items():
		if equipment == chassis:
			continue
		var component := {
			"weight": equipment.weight,
			"max_durability": equipment.max_durability,
			"reserve_energy_capacity": float(equipment.stat("reserve_energy_capacity", 0.0)),
			"working_energy_capacity": float(equipment.stat("working_energy_capacity", 0.0)),
			"power_output": float(equipment.stat("power_output", 0.0)),
			"continuous_power_draw": float(equipment.stat("continuous_power_draw", 0.0)),
		}
		if equipment is VehicleEngine:
			component["propulsion"] = (equipment as VehicleEngine).drive
			component["required_driving_level"] = equipment.required_skill_level
		components.append(component)
		equipment_hardiness[equipment.definition_id] = equipment.max_durability
	var driving_level := player.skills.effective_level("driving", player.character_equipment)
	var assembly_result := VehicleAssemblyCalculator.calculate(
		calculator_chassis, components, driving_level, movement_config
	)
	if not assembly_result.is_ok:
		return assembly_result
	var assembly: Dictionary = assembly_result.value
	assembly["movement_speed"] = player.vehicle.movement_speed(driving_level,
		float(movement_config.get("base_speed_multiplier", 1500)), float(movement_config.get("base_speed_cap", 240)))
	assembly["max_health"] = stats.max_health
	assembly["defense"] = maxi(0, int(stats.defense) - player.food_status.bonus(17))
	assembly["food_defense"] = player.food_status.bonus(17)
	assembly["working_energy_capacity"] = clothing.apply_value("working_energy_capacity", float(assembly.working_energy_capacity))
	assembly["power_output"] = clothing.apply_value("output_power", float(assembly.power_output))
	assembly["available_power_output"] = maxf(0, float(assembly.power_output) - float(assembly.passive_power_load))
	assembly["power_overloaded"] = float(assembly.passive_power_load) > float(assembly.power_output)
	assembly["repair_wait_reduction"] = clothing.trait_value("repair")
	assembly["corrosion_reduction"] = clothing.trait_value("purification")
	assembly["vehicle_id"] = chassis.definition_id
	assembly["self_repair_base_strength"] = chassis.self_repair_power()
	assembly["self_repair_bonus_strength"] = int(stats.self_repair_bonus)
	assembly["self_repair_energy_cost"] = chassis.self_repair_energy_cost
	assembly["self_repair_required_skill_level"] = chassis.required_repair_skill_level
	assembly["equipment_hardiness"] = equipment_hardiness
	assembly["unknown_fields"] = []
	var weapons: Dictionary = {}
	if primary_weapon is VehicleWeapon:
		var weapon_result := _primary_weapon_definition(primary_weapon, simulation_hz)
		if not weapon_result.is_ok:
			return weapon_result
		weapons[STARTER_ABILITY_ID] = weapon_result.value
	var secondary_result := _equipped_secondary_weapon(player.vehicle.loadout.at(13), simulation_hz)
	if not secondary_result.is_ok:
		return secondary_result
	weapons.merge(secondary_result.value)
	for ability_id: String in weapons:
		weapons[ability_id] = player.vehicle.achievement_bonuses.apply_weapon(weapons[ability_id])
		var effect := String({"energy_cannon": "energy_cannon_attack", "missile": "missile_attack",
			"rocket_launcher": "rocket_attack"}.get(weapons[ability_id].get("skill_id", ""), ""))
		var food_kind := int({"energy_cannon_attack": 13, "missile_attack": 14, "rocket_attack": 15}.get(effect, 0))
		var bonus := player.vehicle.loadout.attachment_bonus(effect) + player.vehicle.loadout.socket_bonus(effect)
		for field: String in ["minimum_damage", "maximum_damage"]:
			weapons[ability_id][field] = maxi(1, roundi(clothing.apply_value(effect, float(weapons[ability_id][field]) + bonus)) + player.food_status.bonus(food_kind))
		if effect == "energy_cannon_attack":
			weapons[ability_id]["range"] = clothing.apply_value("energy_cannon_range", float(weapons[ability_id]["range"]))
			weapons[ability_id]["critical_chance"] = player.vehicle.loadout.socket_bonus("critical_chance")
			weapons[ability_id]["critical_multiplier"] = chassis.socket_rules.critical_multiplier if chassis.socket_rules != null else 1.5
		weapons[ability_id]["working_energy_cost"] *= 1.0 - clothing.trait_value("economy")
		weapons[ability_id]["pursuit_bonus"] = clothing.trait_value("pursuit")
	return DomainResult.ok({"assembly": assembly, "weapons": weapons})


## 将实际安装的副武器转换为权威攻击定义；空槽不登记任何攻击能力。
## [param equipment] 战车副武器槽中的实际装备。
## [param simulation_hz] 权威模拟频率。
## 返回按能力标识索引的武器定义；非攻击装置返回空集合。
func _equipped_secondary_weapon(equipment: VehicleEquipment, simulation_hz: int) -> DomainResult:
	if not equipment is VehicleWeapon:
		return DomainResult.ok({})
	var weapon := equipment as VehicleWeapon
	var mode := weapon.combat_mode()
	if mode not in ["missile", "rocket_launcher"]:
		return DomainResult.ok({})
	var templates := starter_secondary_weapons(simulation_hz)
	if not templates.is_ok:
		return templates
	var ability_id := mode + ".primary"
	var definition: Dictionary = templates.value[ability_id].duplicate(true)
	definition["weapon_id"] = weapon.definition_id
	definition["minimum_damage"] = weapon.base_attack
	definition["maximum_damage"] = weapon.base_attack
	definition["working_energy_cost"] = weapon.working_energy_per_shot
	if weapon.attack_range > 0.0:
		definition["range"] = weapon.attack_range
	definition["minimum_range"] = float(weapon.stat("minimum_range", definition["minimum_range"]))
	if weapon.attack_interval_seconds > 0.0:
		definition["cooldown_ticks"] = maxi(1, roundi(weapon.attack_interval_seconds * simulation_hz))
	return DomainResult.ok({ability_id: definition})


## 将实际装备的能量炮转换为权威战斗状态机协议。
## [param weapon] 玩家 Location 1 的具体武器实例。
## [param simulation_hz] 权威服务器每秒模拟刻数。
## 返回统一武器定义；运行时弹道常量缺失时复用已确认的新兵炮默认值。
func _primary_weapon_definition(weapon: VehicleWeapon, simulation_hz: int) -> DomainResult:
	var fallback: Dictionary = (_equipment_by_id["recruit_energy_cannon"] as Dictionary)["stats"]
	var interval := weapon.attack_interval_seconds
	if interval <= 0.0:
		interval = float(fallback["attack_interval_seconds"])
	var cooldown_ticks := roundi(interval * float(simulation_hz))
	if weapon.base_attack <= 0 or weapon.attack_range <= 0.0 or cooldown_ticks <= 0:
		return DomainResult.failure(&"combat.invalid_weapon_definition", "equipped primary weapon stats are invalid")
	return DomainResult.ok({
		"ability_id": STARTER_ABILITY_ID,
		"weapon_id": weapon.definition_id,
		"skill_id": "energy_cannon",
		"attack_mode": "line_projectile",
		"minimum_damage": weapon.base_attack,
		"maximum_damage": weapon.base_attack,
		"working_energy_cost": weapon.working_energy_per_shot,
		"activation_power": null,
		"range": weapon.attack_range,
		"upgrade_range_limit": float(weapon.stat("range_limit", weapon.attack_range)),
		"cooldown_ticks": cooldown_ticks,
		"projectile_speed": float(weapon.stat("runtime_projectile_speed", fallback["runtime_projectile_speed"])),
		"muzzle_offset": (weapon.stat("runtime_muzzle_offset", fallback["runtime_muzzle_offset"]) as Array).duplicate(),
		"muzzle_forward_offset": float(weapon.stat("runtime_muzzle_forward_offset", fallback["runtime_muzzle_forward_offset"])),
		"damage_model": &"confirmed_base_attack_direct",
		"unknown_fields": ["activation_power", "server_damage_formula", "original_server_projectile_speed"],
	})


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
	var encounter := _encounter_for_map(map_id)
	if encounter.is_empty():
		return DomainResult.ok([])
	if not bool(encounter["enabled"]):
		return DomainResult.ok([])
	var policy := monster_population_policy_for_map(map_id)
	return monster_replenishment_for_map(
		map_id, map_instance_id, {}, 0, int(policy.get("maximum_population", 0))
	)


## 查询地图级怪物种群策略并隔离目录内部配置。
## [param map_id] 待查询的业务地图标识。
## 返回启用地图的种群策略副本；无配置时返回空字典。
## 设计：调用方不得持有并修改目录内部配置。
## [param population_kind] ordinary 或 elite；两种种群独立配置。
func monster_population_policy_for_map(map_id: String, population_kind: StringName = &"ordinary") -> Dictionary:
	var encounter := _encounter_for_map(map_id)
	if encounter.is_empty() or not bool(encounter.get("enabled", false)):
		return {}
	var key := "population_policy" if population_kind == &"ordinary" else String(population_kind) + "_population_policy"
	return (encounter.get(key, {}) as Dictionary).duplicate(true)


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
## [param population_kind] ordinary 或 elite，选择独立物种池。
## 返回按权重生成的怪物定义数组或配置错误。
func monster_replenishment_for_map(
	map_id: String,
	map_instance_id: String,
	alive_by_species: Dictionary,
	first_sequence: int,
	requested_count: int,
	population_kind: StringName = &"ordinary",
) -> DomainResult:
	if population_kind not in [&"ordinary", &"elite", &"mutant", &"boss"]:
		return DomainResult.failure(&"combat.invalid_population_request", "unknown population kind")
	if map_instance_id.is_empty() or first_sequence < 0 or requested_count < 0:
		return DomainResult.failure(&"combat.invalid_population_request", "monster replenishment request is invalid")
	var encounter := _encounter_for_map(map_id)
	if encounter.is_empty() or not bool(encounter.get("enabled", false)):
		return DomainResult.ok([])
	var key := "spawn_groups" if population_kind == &"ordinary" else String(population_kind) + "_spawn_groups"
	var groups: Array = encounter.get(key, [])
	if groups.is_empty():
		return DomainResult.ok([])
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
			encounter, selected_group, map_instance_id, sequence, species_count
		))
		result.back()["population_kind"] = population_kind
		working_counts[species_id] = species_count + 1
	return DomainResult.ok(result)


## 将一个种群组配置组装为可登记的怪物生命周期定义。
## [param group] 含物种和目标权重的生成组。
## [param map_instance_id] 新怪物所属权威地图实例。
## [param sequence] 新怪物的全局生成序号。
## [param _species_count] 该物种在生成本只前的数量，预留给后续密度规则。
## 返回包含数值、AI、掉落和确定性生成位置的完整定义。
## 设计：目录只生成领域数据，不直接创建运行时怪物对象。
## [param encounter] 调用方传入的 `encounter` 参数。
func _monster_lifecycle_definition(
	encounter: Dictionary,
	group: Dictionary,
	map_instance_id: String,
	sequence: int,
	_species_count: int,
) -> Dictionary:
	var species_id := String(group["monster_id"])
	var species: Dictionary = _monsters_by_id[species_id]
	var stats: Dictionary = species["stats"]
	var combat: Dictionary = species["combat"]
	return {
				"monster_id": "%s.population.%d" % [encounter["encounter_id"], sequence],
				"species_id": species_id,
				"map_instance_id": map_instance_id,
				"position": Vector2.INF,
				"spawn_distribution": String(
					(encounter.get("population_policy", {}) as Dictionary).get(
						"spawn_distribution", "full_walkable_map"
					)
				),
				"spawn_index": sequence,
				"max_health": int(stats["max_health"]),
				"base_attack": int(stats["base_attack"]),
				"defense": int(combat.get("runtime_defense", 0)),
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
				"drops": _copy_optional_drops(species),
				"unknown_fields": _unknown_monster_fields(stats),
			}


## 复制已确认的掉落表，同时保留 null 表示尚无可信掉落数据的语义。
## [param species] 怪物物种定义。
## 返回独立掉落数组；未配置或非数组时返回 null。
func _copy_optional_drops(species: Dictionary) -> Variant:
	var drops: Variant = species.get("drops")
	if drops is Array:
		return drops.duplicate(true)
	return null


## 读取 D04 遭遇配置中的怪物种群维持策略。
## 返回可安全读取的种群策略字典。
## [param map_id] 调用方传入的 `map_id` 参数。
func _encounter_for_map(map_id: String) -> Dictionary:
	var value: Variant = _encounters_by_map_id.get(map_id)
	return value as Dictionary if value is Dictionary else {}


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


## 返回已接入权威运行时的全部怪物物种 ID，主要供内容完整性审计使用。
## 执行 `monster_ids` 对应的模块操作。
func monster_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for species_id: Variant in _monsters_by_id.keys():
		result.append(String(species_id))
	result.sort()
	return result


## 返回具备可靠客户端地图关系的地图 ID；未恢复关系的物种仍可由显式配置生成。
## 执行 `monster_encounter_map_ids` 对应的模块操作。
func monster_encounter_map_ids() -> PackedStringArray:
	var result := PackedStringArray()
	for map_id: Variant in _encounters_by_map_id.keys():
		result.append(String(map_id))
	result.sort()
	return result


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
	for key: String in ["glory_monsters", "glory_encounters"]:
		var glory_header := _validate_document_header(documents[key], key)
		if not glory_header.is_ok:
			return glory_header
	_starter_loadout = documents["starter_loadout"].duplicate(true)
	_d04_encounter = documents["d04_encounters"].duplicate(true)
	var equipment_result := _index_definitions(_starter_loadout.get("definitions"), _equipment_by_id, "equipment")
	if not equipment_result.is_ok:
		return equipment_result
	var glory_monster_document: Dictionary = documents["glory_monsters"]
	var glory_monster_result := _index_definitions(
		glory_monster_document.get("definitions"), _monsters_by_id, "Glory monster"
	)
	if not glory_monster_result.is_ok:
		return glory_monster_result
	var monster_document: Dictionary = documents["monsters"]
	var monster_result := _index_definitions(
		monster_document.get("definitions"), _monsters_by_id, "monster", true
	)
	if not monster_result.is_ok:
		return monster_result
	if documents.has("material_drops"):
		var drops_result := _apply_material_drops(documents.material_drops)
		if not drops_result.is_ok:
			return drops_result
	var encounter_result := _index_encounters(documents["glory_encounters"].get("encounters"))
	if not encounter_result.is_ok:
		return encounter_result
	_encounters_by_map_id[String(_d04_encounter["map_id"])] = _d04_encounter.duplicate(true)
	if documents.has("enhancement_monsters"):
		var extra := EnhancementMonsterRules.from_dictionary(documents.enhancement_monsters)
		if not extra.is_ok:
			return extra
		var applied: DomainResult = extra.value.apply(_monsters_by_id, _encounters_by_map_id)
		if not applied.is_ok:
			return applied
	return _validate_runtime_links()


## 装载明确批准的掉落规则；完整表替换旧规则，补充表仍兼容追加模式。
## [param document] 单独版本化的材料投放配置。
## 返回全部条目通过领域掉落校验后的结果。
func _apply_material_drops(document: Dictionary) -> DomainResult:
	if int(document.get("schema_version", 0)) != 1 or not document.get("definitions") is Array:
		return DomainResult.failure(&"combat.invalid_material_drops", "材料投放配置格式错误")
	var mode := String(document.get("mode", "append"))
	if mode not in ["append", "replace"]:
		return DomainResult.failure(&"combat.invalid_material_drops", "未知掉落配置模式")
	var seen: Dictionary = {}
	for raw: Variant in document.definitions:
		if not raw is Dictionary or not raw.get("monster_id") is String or not raw.get("drops") is Array:
			return DomainResult.failure(&"combat.invalid_material_drops", "材料投放条目格式错误")
		var id := String(raw.monster_id)
		if not _monsters_by_id.has(id) or seen.has(id):
			return DomainResult.failure(&"combat.invalid_material_drops", "材料投放引用未知或重复怪物")
		seen[id] = true
		var table := DropTable.new()
		var validation := table.configure(raw.drops)
		if not validation.is_ok:
			return validation
		var species: Dictionary = _monsters_by_id[id]
		var combined: Array = species.drops.duplicate(true) if mode == "append" and species.get("drops") is Array else []
		combined.append_array(table.entries())
		species.drops = combined
	return DomainResult.ok()


## 执行 `index_definitions` 对应的模块操作。
## [param raw_definitions] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param destination] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param context] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## [param allow_override] 调用方传入的 `allow_override` 参数。
func _index_definitions(
	raw_definitions: Variant,
	destination: Dictionary,
	context: String,
	allow_override := false,
) -> DomainResult:
	if not raw_definitions is Array:
		return DomainResult.failure(&"combat.invalid_catalog", "%s definitions must be an array" % context)
	for raw_definition: Variant in raw_definitions:
		if not raw_definition is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "%s definition must be a dictionary" % context)
		var definition: Dictionary = raw_definition
		var definition_id := String(definition.get("id", ""))
		if definition_id.is_empty() or (destination.has(definition_id) and not allow_override):
			return DomainResult.failure(&"combat.invalid_catalog", "%s definition ID is empty or duplicated" % context)
		if not definition.get("stats") is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "%s stats must be a dictionary" % context)
		destination[definition_id] = definition.duplicate(true)
	return DomainResult.ok()


## 建立地图到怪物种群定义的索引；D04 的手工首切配置会在随后覆盖同名地图。
## [param raw_encounters] 调用方传入的 `raw_encounters` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _index_encounters(raw_encounters: Variant) -> DomainResult:
	if not raw_encounters is Array:
		return DomainResult.failure(&"combat.invalid_catalog", "Glory encounters must be an array")
	for raw_encounter: Variant in raw_encounters:
		if not raw_encounter is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "Glory encounter must be a dictionary")
		var encounter: Dictionary = raw_encounter
		var map_id := String(encounter.get("map_id", ""))
		if map_id.is_empty() or _encounters_by_map_id.has(map_id):
			return DomainResult.failure(&"combat.invalid_catalog", "Glory encounter map ID is empty or duplicated")
		_encounters_by_map_id[map_id] = encounter.duplicate(true)
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
	if String(_d04_encounter.get("map_id", "")) != "d04_field_zone":
		return DomainResult.failure(&"combat.invalid_catalog", "D04 encounter identity is invalid")
	for encounter: Dictionary in _encounters_by_map_id.values():
		var groups: Variant = encounter.get("spawn_groups")
		var policy: Variant = encounter.get("population_policy")
		if not groups is Array or groups.is_empty():
			return DomainResult.failure(&"combat.invalid_catalog", "encounter spawn groups are invalid")
		if not policy is Dictionary or int(policy.get("maximum_population", 0)) <= 0 \
			or float(policy.get("replenish_interval_seconds", 0.0)) <= 0.0 \
			or String(policy.get("spawn_distribution", "")) != "full_walkable_map" \
			or float(policy.get("minimum_spawn_separation", 0.0)) < 0.0:
			return DomainResult.failure(&"combat.invalid_catalog", "encounter population policy is invalid")
		var elite_groups: Variant = encounter.get("elite_spawn_groups", [])
		var elite_policy: Variant = encounter.get("elite_population_policy", {})
		if not elite_groups is Array or not elite_policy is Dictionary:
			return DomainResult.failure(&"combat.invalid_catalog", "elite population format is invalid")
		if not elite_groups.is_empty() or not elite_policy.is_empty():
			var quota := TimedPopulationQuota.new()
			if elite_groups.is_empty() or elite_policy.is_empty() or not quota.configure(elite_policy, 20).is_ok:
				return DomainResult.failure(&"combat.invalid_catalog", "elite population policy is invalid")
			if int(encounter.get("progression", {}).get("danger_tier", 0)) != 10:
				return DomainResult.failure(&"combat.invalid_catalog", "elite population requires tier ten")
		for raw_group: Variant in groups + elite_groups:
			if not raw_group is Dictionary:
				return DomainResult.failure(&"combat.invalid_catalog", "encounter spawn group must be a dictionary")
			var group: Dictionary = raw_group
			if not _monsters_by_id.has(String(group.get("monster_id", ""))) \
				or float(group.get("weight", 0.0)) <= 0.0:
				return DomainResult.failure(&"combat.invalid_catalog", "encounter group contains unresolved or invalid data")
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
