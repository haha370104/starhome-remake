class_name AuthoritativeMapInstance
extends RefCounted

const MapDefinitionLoaderScript := preload("res://scripts/maps/map_definition_loader.gd")
const DiamondNavigationScript := preload("res://scripts/navigation/diamond_navigation.gd")
const MonsterRoutePlannerScript := preload("res://scripts/navigation/monster_route_planner.gd")
const RandomWalkableSpawnSamplerScript := preload(
	"res://scripts/navigation/random_walkable_spawn_sampler.gd"
)
const EntityScript := preload("res://scripts/server/authoritative_entity.gd")
const MoveIntentContract := preload("res://scripts/network/contracts/move_intent.gd")
const ErrorCodes := preload("res://scripts/network/contracts/network_error_codes.gd")
const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const MiningModuleScript := preload(
	"res://scripts/server/modules/mining/authoritative_mining_module.gd"
)
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")
const DomainResult := preload("res://scripts/core/domain_result.gd")

var definition
var navigation
var entities: Dictionary = {}
var movement_speed_cap := 240.0
var dynamic_blocking_enabled := true
var dynamic_blocking_radius := 18.0
var instance_id := ""
var combat_module: AuthoritativeCombatModule
var mining_module
var _combat_catalog
var _combat_assembly: Dictionary = {}
var _combat_weapons: Dictionary = {}
var _accepted_movement_distance: Dictionary = {}
var _last_progression_combat_event_id := 0
var _monster_population_policy: Dictionary = {}
var _next_monster_replenishment_tick := -1
var _monster_spawn_sequence := 0


## 加载并校验 `load_map` 对应的模块状态。
## [param map_config_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func load_map(map_config_path: String) -> Dictionary:
	var loader = MapDefinitionLoaderScript.new()
	definition = loader.load_file(map_config_path)
	if definition == null:
		return _failure(&"invalid_map_definition", "; ".join(loader.errors))
	instance_id = "%s.instance.1" % definition.map_id
	navigation = DiamondNavigationScript.new()
	if not navigation.load_from(
		definition.navigation_data_path,
		definition.navigation_grid_size,
		definition.navigation_cell_size,
	):
		definition = null
		return _failure(&"invalid_navigation", "map navigation failed to load")
	return _success(definition)


## 执行 `configure_combat` 对应的模块操作。
## [param catalog] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param simulation_hz] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func configure_combat(catalog, simulation_hz: int) -> Dictionary:
	if definition == null or navigation == null:
		return _failure(&"combat.map_not_loaded", "load map navigation before combat")
	_accepted_movement_distance.clear()
	_last_progression_combat_event_id = 0
	var lifecycle_result = catalog.monster_lifecycles_for_map(String(definition.map_id), instance_id)
	if not lifecycle_result.is_ok:
		return _failure(lifecycle_result.error_code, lifecycle_result.error_message)
	var assembly_result = catalog.starter_vehicle_assembly(10, {
		"base_speed_multiplier": 1500.0,
		"base_speed_cap": movement_speed_cap,
	})
	var weapon_result = catalog.starter_energy_cannon(simulation_hz)
	var secondary_result = catalog.starter_secondary_weapons(simulation_hz)
	if not assembly_result.is_ok or not weapon_result.is_ok or not secondary_result.is_ok:
		return _failure(&"combat.definition_invalid", "starter vehicle combat definitions are invalid")
	_combat_catalog = catalog
	_monster_population_policy = catalog.monster_population_policy_for_map(String(definition.map_id))
	_combat_assembly = assembly_result.value
	_combat_weapons = {"energy_cannon.primary": weapon_result.value}
	_combat_weapons.merge(secondary_result.value)
	combat_module = CombatModuleScript.new()
	var configured = combat_module.configure(simulation_hz, hash(instance_id), 1.0)
	if not configured.is_ok:
		return _failure(configured.error_code, configured.error_message)
	combat_module.set_monster_position_resolver(_resolve_monster_position)
	combat_module.set_monster_route_resolver(_resolve_monster_route)
	for raw_definition: Variant in lifecycle_result.value:
		var monster_definition: Dictionary = raw_definition.duplicate(true)
		var requested_position := _random_monster_spawn_position(int(monster_definition["spawn_index"]))
		if not requested_position.is_finite():
			return _failure(&"combat.no_monster_spawn", "monster group has no walkable spawn")
		monster_definition["position"] = requested_position
		var registration = combat_module.register_monster(monster_definition)
		if not registration.is_ok:
			return _failure(registration.error_code, registration.error_message)
	_monster_spawn_sequence = lifecycle_result.value.size()
	_next_monster_replenishment_tick = roundi(
		float(_monster_population_policy.get("replenish_interval_seconds", 60.0)) * simulation_hz
	)
	for entity_id: String in entities:
		var registration := _register_vehicle_combat(entity_id)
		if not registration.ok:
			return registration
	return _success(combat_module.monsters.size())


## 为当前地图配置独立的权威矿源种群；非野外图得到空模块。
## [param catalog] 调用方传入的 `catalog` 参数。
## [param simulation_hz] 调用方传入的 `simulation_hz` 参数。
## 返回该函数计算、查询或操作得到的结果。
func configure_mining(catalog, simulation_hz: int) -> Dictionary:
	if definition == null or navigation == null:
		return _failure(&"mining.map_not_loaded", "load map navigation before mining")
	mining_module = MiningModuleScript.new()
	var configured = mining_module.configure(
		catalog, String(definition.map_id), instance_id, simulation_hz, navigation
	)
	return _success(configured.value) if configured.is_ok \
		else _failure(configured.error_code, configured.error_message)


## 创建 `spawn_entity` 对应的模块状态。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param movement_speed] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func spawn_entity(entity_id: String, requested_position: Vector2, movement_speed: float) -> Dictionary:
	if definition == null or navigation == null:
		return _failure(&"map_not_loaded", "load a map before spawning entities")
	if entity_id.is_empty() or entities.has(entity_id):
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "entity_id must be non-empty and unique")
	if not requested_position.is_finite():
		return _failure(&"invalid_position", "spawn position must be finite")
	if movement_speed <= 0.0 or movement_speed > movement_speed_cap:
		return _failure(&"invalid_speed", "movement speed exceeds the server cap")
	var spawn_position := admitted_spawn_position(requested_position, StringName(entity_id))
	if not spawn_position.is_finite():
		return _failure(&"no_walkable_spawn", "map has no walkable spawn near requested position")
	var entity: AuthoritativeEntity = EntityScript.new()
	entity.entity_id = entity_id
	entity.map_instance_id = instance_id
	entity.position = spawn_position
	entity.target_position = spawn_position
	entity.movement_speed = movement_speed
	entities[entity_id] = entity
	if combat_module != null:
		var combat_result := _register_vehicle_combat(entity_id)
		if not combat_result.ok:
			entities.erase(entity_id)
			return combat_result
	return _success(entity)


## 执行 `admitted_spawn_position` 对应的模块操作。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func admitted_spawn_position(
	requested_position: Vector2,
	entity_id: StringName = &"",
) -> Vector2:
	var spawn_position := requested_position
	if not navigation.is_walkable(spawn_position):
		spawn_position = navigation.closest_walkable_position(spawn_position)
	if not spawn_position.is_finite():
		return Vector2.INF
	if dynamic_blocking_enabled:
		spawn_position = _closest_dynamically_available_position(spawn_position, entity_id)
	return spawn_position


## 移除并清理 `remove_entity` 对应的模块状态。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func remove_entity(entity_id: String) -> bool:
	if combat_module != null:
		combat_module.unregister_vehicle(entity_id)
	_accepted_movement_distance.erase(entity_id)
	if mining_module != null:
		mining_module.unregister_actor(entity_id)
	return entities.erase(entity_id)


## 执行 `handle_use_ability` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param raw_intent] 客户端通用能力意图，不得携带战斗数值。
## [param authoritative_context] 服务器从玩家聚合派生的技能等级等可信上下文。
func handle_use_ability(
	entity_id: String,
	raw_intent: Variant,
	authoritative_context: Dictionary = {},
):
	var ability_id := String(raw_intent.get("ability_id", "")) if raw_intent is Dictionary else ""
	if ability_id == MiningModuleScript.COLLECT_ABILITY_ID:
		if mining_module == null:
			return _failure(&"mining.not_available", "this map has no configured mining module")
		var intent_result = UseAbilityIntentContract.from_dictionary(raw_intent)
		if not intent_result.is_ok:
			return _failure(intent_result.error_code, intent_result.error_message)
		var intent = intent_result.value
		if intent.map_instance_id != instance_id:
			return _failure(&"mining.map_instance_mismatch", "mining intent targets another map")
		var entity: AuthoritativeEntity = entities.get(entity_id)
		if entity == null:
			return _failure(&"mining.actor_missing", "mining actor is absent from the map")
		var vehicle_state := vehicle_combat_state_for(entity_id)
		if is_vehicle_combat_active() and vehicle_state != null and vehicle_state.health <= 0:
			return _failure(&"combat.vehicle_destroyed", "destroyed vehicle cannot collect minerals")
		var mining_result = mining_module.begin_collection(
			entity_id,
			entity.position,
			intent.aim_world_position,
			int(authoritative_context.get("mining_skill_level", -1)),
			intent.input_sequence,
		)
		return _success(mining_result.value) if mining_result.is_ok \
			else _failure(mining_result.error_code, mining_result.error_message)
	if combat_module == null or not is_vehicle_combat_active():
		return _failure(&"combat.not_available", "this map has no configured combat encounter")
	if mining_module != null:
		mining_module.interrupt(entity_id, &"attack")
	var result = combat_module.handle_self_repair(
		entity_id,
		raw_intent,
		int(authoritative_context.get("repair_skill_level", -1)),
	) if ability_id == AuthoritativeCombatModule.SELF_REPAIR_ABILITY_ID \
	else combat_module.handle_weapon_attack(entity_id, raw_intent)
	return _success(result.value) if result.is_ok else _failure(result.error_code, result.error_message)


## 预检指定玩家是否可拾取当前地图的一件地面掉落物。
## [param entity_id] 由服务器会话绑定的玩家实体标识。
## [param loot_id] 客户端请求拾取的地面掉落实例标识。
## 返回供背包事务消费的掉落 DTO 或拒绝原因。
func prepare_loot_pickup(entity_id: String, loot_id: String) -> DomainResult:
	if combat_module == null:
		return DomainResult.failure(&"combat.module_unavailable", "map combat module is unavailable")
	return combat_module.prepare_loot_pickup(entity_id, loot_id)


## 在玩家背包持久化成功后移除当前地图的一件地面掉落物。
## [param entity_id] 已完成背包入账的玩家实体标识。
## [param loot_id] 待提交移除的地面掉落实例标识。
## 返回权威拾取事件或并发状态变化错误。
func commit_loot_pickup(entity_id: String, loot_id: String) -> DomainResult:
	if combat_module == null:
		return DomainResult.failure(&"combat.module_unavailable", "map combat module is unavailable")
	return combat_module.commit_loot_pickup(entity_id, loot_id)


## 校验并处理 `handle_move_intent` 对应的模块状态。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param raw_intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func handle_move_intent(entity_id: String, raw_intent: Variant) -> Dictionary:
	var entity: AuthoritativeEntity = entities.get(entity_id)
	if entity == null:
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "entity is not present in this map instance")
	var vehicle_state := vehicle_combat_state_for(entity_id)
	if is_vehicle_combat_active() and vehicle_state != null and vehicle_state.health <= 0:
		return _failure(&"combat.vehicle_destroyed", "destroyed vehicle cannot move")
	var intent_result = MoveIntentContract.from_dictionary(raw_intent)
	if not intent_result.is_ok:
		return _failure(intent_result.error_code, intent_result.error_message)
	var intent = intent_result.value
	if intent.map_instance_id != instance_id:
		return _failure(ErrorCodes.INVALID_IDENTIFIER, "move intent targets a different map instance")
	var sequence: int = intent.input_sequence
	if sequence <= entity.last_input_sequence:
		return _failure(ErrorCodes.STALE_SEQUENCE, "sequence was already acknowledged")
	var requested_position: Vector2 = intent.requested_world_point
	var authoritative_target := requested_position
	if not navigation.is_walkable(authoritative_target):
		authoritative_target = navigation.closest_reachable_position(
			entity.position, requested_position
		)
	if not authoritative_target.is_finite():
		return _failure(&"unreachable_target", "no reachable fallback exists")
	var static_target := authoritative_target
	if dynamic_blocking_enabled and not _position_has_dynamic_clearance(
		authoritative_target, entity_id, true
	):
		authoritative_target = _closest_dynamically_available_position(
			authoritative_target, entity_id
		)
	if not authoritative_target.is_finite():
		return _failure(&"dynamic_target_blocked", "no target clears other entity foot points")
	var authoritative_path := _find_authoritative_path(entity_id, entity.position, authoritative_target)
	if authoritative_path.is_empty():
		return _failure(&"unreachable_target", "no authoritative path exists")
	entity.set_path(authoritative_path, authoritative_target, sequence)
	if combat_module != null and not authoritative_target.is_equal_approx(entity.position):
		combat_module.interrupt_self_repair(entity_id, &"movement")
	if mining_module != null and not authoritative_target.is_equal_approx(entity.position):
		mining_module.interrupt(entity_id, &"movement")
	return _success({
		"sequence": sequence,
		"requested_target": requested_position,
		"authoritative_target": authoritative_target,
		"adjusted": not requested_position.is_equal_approx(authoritative_target),
		"dynamic_adjusted": not static_target.is_equal_approx(authoritative_target),
	})


## 推进并更新 `simulate` 对应的模块状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func simulate(delta: float) -> void:
	var entity_ids := entities.keys()
	entity_ids.sort()
	for entity_id: String in entity_ids:
		var entity: AuthoritativeEntity = entities[entity_id]
		var previous_position: Vector2 = entity.position
		var vehicle_state := vehicle_combat_state_for(entity_id)
		if vehicle_state != null and vehicle_state.health <= 0:
			entity.target_position = entity.position
			entity.path = PackedVector2Array([entity.position])
			entity.path_index = entity.path.size()
			entity.action = &"idle"
			continue
		if not dynamic_blocking_enabled or entities.size() <= 1:
			entity.simulate(delta)
		else:
			var motion_state := _capture_motion_state(entity)
			entity.simulate(delta)
			if (
				not entity.position.is_equal_approx(previous_position)
				and _movement_intersects_dynamic_blocker(
					entity_id, previous_position, entity.position
				)
			):
				_restore_motion_state(entity, motion_state)
		if not entity.position.is_equal_approx(previous_position):
			_accepted_movement_distance[entity_id] = float(
				_accepted_movement_distance.get(entity_id, 0.0)
			) + previous_position.distance_to(entity.position)
	if combat_module != null:
		for entity_id: String in entities:
			combat_module.update_actor_position(entity_id, entities[entity_id].position)
		combat_module.advance_ticks(1)
		_replenish_monster_population_if_due()
	if mining_module != null:
		mining_module.advance_ticks(1)


## 取出到期的采矿周期，交给服务器完成背包与持久化事务。
## 返回该函数计算、查询或操作得到的结果。
func drain_mining_cycles() -> Array[Dictionary]:
	return mining_module.drain_ready_cycles() if mining_module != null else []


## 背包入账成功后提交一次矿量扣减。
## [param token] 调用方传入的 `token` 参数。
func commit_mining_cycle(token: String):
	return mining_module.commit_cycle(token) if mining_module != null \
		else DomainResult.failure(&"mining.not_available", "mining module is unavailable")


## 背包或存档失败时释放预约且不消耗矿量。
## [param token] 调用方传入的 `token` 参数。
## 返回该函数计算、查询或操作得到的结果。
func reject_mining_cycle(token: String) -> bool:
	return mining_module.reject_cycle(token) if mining_module != null else false


## 每分钟按地图策略补充怪物；死亡实例在补量时统一回收，不再逐只原地复活。
func _replenish_monster_population_if_due() -> void:
	if combat_module == null or _next_monster_replenishment_tick < 0 \
		or combat_module.current_tick < _next_monster_replenishment_tick:
		return
	var interval_ticks := maxi(1, roundi(
		float(_monster_population_policy.get("replenish_interval_seconds", 60.0))
		* combat_module.simulation_hz
	))
	_next_monster_replenishment_tick += interval_ticks
	var alive_by_species: Dictionary = {}
	var alive_count := 0
	for monster: MonsterLifecycle in combat_module.monsters.values():
		if monster.map_instance_id == instance_id and monster.is_alive():
			alive_count += 1
			alive_by_species[monster.species_id] = int(
				alive_by_species.get(monster.species_id, 0)
			) + 1
	var replenish_count: int = _combat_catalog.monster_replenishment_count(
		String(definition.map_id), alive_count
	)
	combat_module.remove_dead_monsters(instance_id)
	if replenish_count <= 0:
		return
	var generated = _combat_catalog.monster_replenishment_for_map(
		String(definition.map_id), instance_id, alive_by_species,
		_monster_spawn_sequence, replenish_count,
	)
	if not generated.is_ok:
		push_error("Monster replenishment failed: %s" % generated.error_message)
		return
	for raw_definition: Variant in generated.value:
		var monster_definition: Dictionary = raw_definition.duplicate(true)
		var position := _random_monster_spawn_position(int(monster_definition["spawn_index"]))
		if not position.is_finite():
			continue
		monster_definition["position"] = position
		combat_module.register_monster(monster_definition)
	_monster_spawn_sequence += generated.value.size()


## 为下一只怪物选择与存活实体保持配置间距的权威出生点。
## [param spawn_sequence] 用于确定性随机采样的全局生成序号。
## 返回可用出生坐标；地图没有候选点时返回无穷坐标。
func _random_monster_spawn_position(spawn_sequence: int) -> Vector2:
	var occupied: Array[Vector2] = []
	if combat_module != null:
		for monster: MonsterLifecycle in combat_module.monsters.values():
			if monster.map_instance_id == instance_id and monster.is_alive():
				occupied.append(monster.position)
	var minimum_separation := float(
		_monster_population_policy.get("minimum_spawn_separation", 0.0)
	)
	return RandomWalkableSpawnSamplerScript.sample(
		navigation,
		hash("%s.monster.%d" % [instance_id, spawn_sequence]),
		occupied,
		minimum_separation,
	)


## 提取自上次调用后产生的技能成长事件，并清空已消费的移动累计。
## 返回按玩家拆分的正常驾驶位移与最终有效能量炮伤害事件。
## 设计：只观察权威模拟结果；受阻回滚、传送和客户端声明的距离都不会进入事件。
func drain_skill_progression_events() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var entity_ids := _accepted_movement_distance.keys()
	entity_ids.sort()
	for entity_id: String in entity_ids:
		var distance := float(_accepted_movement_distance[entity_id])
		if distance > 0.0 and _combat_assembly.has("total_weight"):
			events.append({
				"entity_id": entity_id,
				"source": "accepted_driving_movement",
				"skill_id": "driving",
				"distance": distance,
				"vehicle_weight": float(_combat_assembly.get("total_weight", 0.0)),
			})
	_accepted_movement_distance.clear()
	if combat_module == null:
		return events
	for combat_event: Dictionary in combat_module.combat_events:
		var event_id := int(combat_event.get("event_id", 0))
		if event_id <= _last_progression_combat_event_id:
			continue
		_last_progression_combat_event_id = maxi(_last_progression_combat_event_id, event_id)
		var event_type := StringName(combat_event.get("event_type", &""))
		if event_type in [&"energy_cannon_hit", &"rocket_launcher_hit", &"missile_hit"] \
				and int(combat_event.get("damage", 0)) > 0:
			events.append({
				"entity_id": String(combat_event.get("attacker_id", "")),
				"source": "effective_damage",
				"skill_id": String(combat_event.get("skill_id", "energy_cannon")),
				"damage": int(combat_event.get("damage", 0)),
				"combat_event_id": event_id,
			})
		elif event_type == &"self_repair_resolved" and int(combat_event.get("healed", 0)) > 0:
			events.append({
				"entity_id": String(combat_event.get("actor_id", "")),
				"source": "authoritative_action",
				"skill_id": "repair",
				"amount": 1.0,
				"combat_event_id": event_id,
			})
	return events


## 执行 `closest_dynamically_available_position` 对应的模块操作。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param excluded_entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _closest_dynamically_available_position(
	requested_position: Vector2,
	excluded_entity_id: StringName,
) -> Vector2:
	if _position_has_dynamic_clearance(requested_position, excluded_entity_id, true):
		return requested_position
	var best_position := Vector2.INF
	var best_distance_squared := INF
	for point_id: int in navigation.graph.get_point_ids():
		var candidate: Vector2 = navigation.graph.get_point_position(point_id)
		if not _position_has_dynamic_clearance(candidate, excluded_entity_id, true):
			continue
		var distance_squared := candidate.distance_squared_to(requested_position)
		if distance_squared < best_distance_squared:
			best_position = candidate
			best_distance_squared = distance_squared
	return best_position


## 执行 `position_has_dynamic_clearance` 对应的模块操作。
## [param candidate] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param excluded_entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param include_reserved_targets] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _position_has_dynamic_clearance(
	candidate: Vector2,
	excluded_entity_id: StringName,
	include_reserved_targets: bool,
) -> bool:
	var minimum_distance_squared := dynamic_blocking_radius * dynamic_blocking_radius
	for other_entity_id: String in entities:
		if StringName(other_entity_id) == excluded_entity_id:
			continue
		var other: AuthoritativeEntity = entities[other_entity_id]
		if candidate.distance_squared_to(other.position) < minimum_distance_squared:
			return false
		if (
			include_reserved_targets
			and not other.target_position.is_equal_approx(other.position)
			and candidate.distance_squared_to(other.target_position) < minimum_distance_squared
		):
			return false
	return true


## 查询并返回 `find_authoritative_path` 对应的模块状态。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _find_authoritative_path(
	entity_id: String,
	from_position: Vector2,
	to_position: Vector2,
) -> PackedVector2Array:
	if not dynamic_blocking_enabled or entities.size() <= 1:
		return navigation.find_path(from_position, to_position)
	var disabled_point_ids: Array[int] = []
	var minimum_distance_squared := dynamic_blocking_radius * dynamic_blocking_radius
	var from_point_id: int = navigation.cell_id(navigation.world_to_cell(from_position))
	for point_id: int in navigation.graph.get_point_ids():
		if point_id == from_point_id or navigation.graph.is_point_disabled(point_id):
			continue
		var point_position: Vector2 = navigation.graph.get_point_position(point_id)
		for other_entity_id: String in entities:
			if other_entity_id == entity_id:
				continue
			var other: AuthoritativeEntity = entities[other_entity_id]
			if point_position.distance_squared_to(other.position) < minimum_distance_squared:
				navigation.graph.set_point_disabled(point_id, true)
				disabled_point_ids.append(point_id)
				break
	var path: PackedVector2Array = navigation.find_path(from_position, to_position, false)
	for point_id: int in disabled_point_ids:
		navigation.graph.set_point_disabled(point_id, false)
	return path


## 执行 `capture_motion_state` 对应的模块操作。
## [param entity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _capture_motion_state(entity: AuthoritativeEntity) -> Dictionary:
	return {
		"position": entity.position,
		"path_index": entity.path_index,
		"facing_index": entity.facing_index,
		"action": entity.action,
		"state_revision": entity.state_revision,
	}


## 执行 `restore_motion_state` 对应的模块操作。
## [param entity] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param motion_state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _restore_motion_state(entity: AuthoritativeEntity, motion_state: Dictionary) -> void:
	entity.position = motion_state.position
	entity.path_index = motion_state.path_index
	entity.facing_index = motion_state.facing_index
	entity.action = &"idle"
	entity.state_revision = int(motion_state.state_revision) + 1


## 执行 `movement_intersects_dynamic_blocker` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param from_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param to_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _movement_intersects_dynamic_blocker(
	entity_id: String,
	from_position: Vector2,
	to_position: Vector2,
) -> bool:
	var minimum_distance_squared := dynamic_blocking_radius * dynamic_blocking_radius
	for other_entity_id: String in entities:
		if other_entity_id == entity_id:
			continue
		var other: AuthoritativeEntity = entities[other_entity_id]
		var closest_point := _closest_point_on_segment(
			other.position, from_position, to_position
		)
		if closest_point.distance_squared_to(other.position) < minimum_distance_squared:
			return true
	return false


## 执行 `closest_point_on_segment` 对应的模块操作。
## [param point] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param segment_start] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param segment_end] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _closest_point_on_segment(
	point: Vector2,
	segment_start: Vector2,
	segment_end: Vector2,
) -> Vector2:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return segment_start
	var weight := clampf((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return segment_start + segment * weight


## 执行 `snapshot` 对应的模块操作。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_time_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot(server_tick: int, server_time_seconds: float) -> Dictionary:
	var entity_snapshots: Array[Dictionary] = []
	var entity_ids := entities.keys()
	entity_ids.sort()
	for entity_id in entity_ids:
		entity_snapshots.append(entities[entity_id].snapshot(server_tick))
	return {
		"server_tick": server_tick,
		"server_time_seconds": server_time_seconds,
		"entities": entity_snapshots,
	}


## 执行 `snapshot_for_actor` 对应的模块操作。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param server_time_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func snapshot_for_actor(server_tick: int, server_time_seconds: float, actor_id: String) -> Dictionary:
	var result := snapshot(server_tick, server_time_seconds)
	if combat_module != null:
		var combat_snapshot: Dictionary = combat_module.snapshot_for_actor(actor_id)
		combat_snapshot["vehicle_combat_active"] = is_vehicle_combat_active()
		combat_snapshot["mine_sources"] = mining_module.snapshot() if mining_module != null else []
		result["combat"] = combat_snapshot
	return result


## 当前地图是否把玩家表现为可战斗战车；资源状态可以存在于非战斗地图，但不能限制人物移动。
## 返回该函数计算、查询或操作得到的结果。
func is_vehicle_combat_active() -> bool:
	if definition == null:
		return false
	return StringName(definition.player_presentation.get("kind", &"character")) == &"combat_actor"


## 查询当前地图内指定实体的权威战车资源状态。
## [param entity_id] 已在本地图登记的玩家战车实体标识。
## 返回该函数计算、查询或操作得到的结果。
func vehicle_combat_state_for(entity_id: String) -> VehicleCombatState:
	if combat_module == null:
		return null
	var actor_value: Variant = combat_module.actors.get(entity_id)
	if not actor_value is Dictionary:
		return null
	return (actor_value as Dictionary).get("vehicle_state") as VehicleCombatState


## 从存档恢复指定战车的可消耗资源当前值。
## [param entity_id] 已在本地图登记的玩家战车实体标识。
## [param persisted_state] 已通过仓储校验的玩家完整聚合。
## 返回该函数计算、查询或操作得到的结果。
## 设计：装备定义仍决定容量与功率，存档只能恢复生命、储备能量和当前能量，不能改写配置上限。
func restore_vehicle_combat_state(entity_id: String, persisted_state: PlayerStateRecord) -> Dictionary:
	var vehicle_state := vehicle_combat_state_for(entity_id)
	if vehicle_state == null or persisted_state == null:
		return _failure(&"persistence.vehicle_state_unavailable", "map does not own this vehicle combat state")
	if (
		persisted_state.vehicle_health < 0
		or persisted_state.vehicle_health > vehicle_state.max_health
		or persisted_state.reserve_energy < 0.0
		or persisted_state.reserve_energy > vehicle_state.reserve_energy_capacity
		or persisted_state.working_energy < 0.0
		or persisted_state.working_energy > vehicle_state.working_energy_capacity
	):
		return _failure(&"persistence.vehicle_state_out_of_range", "persisted vehicle resources exceed current definitions")
	vehicle_state.health = persisted_state.vehicle_health
	vehicle_state.reserve_energy = persisted_state.reserve_energy
	vehicle_state.working_energy = persisted_state.working_energy
	return _success(vehicle_state)


## 执行 `register_vehicle_combat` 对应的模块操作。
## [param entity_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _register_vehicle_combat(entity_id: String) -> Dictionary:
	var entity: AuthoritativeEntity = entities.get(entity_id)
	if entity == null or combat_module == null:
		return _failure(&"combat.invalid_actor", "combat vehicle registration requires a map entity")
	var result = combat_module.register_vehicle(
		entity_id, instance_id, entity.position, _combat_assembly, _combat_weapons
	)
	return _success(result.value) if result.is_ok else _failure(result.error_code, result.error_message)


## 执行 `resolve_monster_position` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param current_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _resolve_monster_position(
	monster_id: String,
	current_position: Vector2,
	requested_position: Vector2,
) -> Vector2:
	if monster_id.is_empty() or navigation == null:
		return current_position
	if navigation.is_walkable(requested_position):
		return requested_position
	var fallback: Vector2 = navigation.closest_reachable_position(current_position, requested_position)
	return fallback if fallback.is_finite() else current_position


## 为怪物 AI 期望终点生成静态障碍安全的完整权威路线。
## [param monster_id] 请求路线的怪物标识，仅用于拒绝空身份。
## [param current_position] 怪物当前权威脚点。
## [param requested_position] 游荡、追击或返巢期望终点。
## 返回含实际可达终点和 AStar 路径的字典；没有路线时返回空字典。
## 设计：导航图只属于地图实例，战斗模块与怪物领域对象不得读取地图资源。
func _resolve_monster_route(
	monster_id: String,
	current_position: Vector2,
	requested_position: Vector2,
) -> Dictionary:
	return MonsterRoutePlannerScript.resolve(
		navigation,
		monster_id,
		current_position,
		requested_position,
	)


## 执行 `success` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _success(value: Variant) -> Dictionary:
	return {"ok": true, "code": &"ok", "value": value}


## 执行 `failure` 对应的模块操作。
## [param code] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param message] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _failure(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}
