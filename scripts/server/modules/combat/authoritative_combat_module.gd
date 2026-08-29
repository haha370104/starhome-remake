class_name AuthoritativeCombatModule
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")
const MonsterLifecycleScript := preload("res://scripts/domain/combat/monster_lifecycle.gd")
const ProjectileSweep := preload("res://scripts/domain/combat/projectile_sweep.gd")
const VehicleCombatStateScript := preload("res://scripts/domain/combat/vehicle_combat_state.gd")
const UseAbilityIntentContract := preload("res://scripts/network/contracts/use_ability_intent.gd")
const ACTOR_PROJECTILE_HITBOX_OFFSET := Vector2(0.0, -16.0)
const ACTOR_PROJECTILE_HITBOX_RADIUS := 18.0
const LOOT_PICKUP_RADIUS := 125.0

var simulation_hz := 20
var current_tick := 0
var event_sequence := 0
var working_energy_regen_factor := 1.0
var actors: Dictionary = {}
var monsters: Dictionary = {}
var combat_events: Array[Dictionary] = []
var death_events: Array[Dictionary] = []
var respawn_events: Array[Dictionary] = []
var pending_projectiles: Array[Dictionary] = []
var pending_monster_attacks: Array[Dictionary] = []
var ground_loot: Dictionary = {}
var _random := RandomNumberGenerator.new()
var _monster_position_resolver := Callable()
var _shot_sequence := 0
var _monster_attack_sequence := 0
var _loot_sequence := 0


## 配置并初始化 `configure` 对应的模块状态。
## [param requested_simulation_hz] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param random_seed] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param regen_factor] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(
	requested_simulation_hz: int,
	random_seed: int,
	regen_factor: float = 1.0,
) -> DomainResult:
	if requested_simulation_hz <= 0 or regen_factor < 0.0:
		return DomainResult.failure(&"combat.invalid_module_config", "tick rate and regeneration factor are invalid")
	simulation_hz = requested_simulation_hz
	current_tick = 0
	event_sequence = 0
	_shot_sequence = 0
	_monster_attack_sequence = 0
	_loot_sequence = 0
	working_energy_regen_factor = regen_factor
	_random.seed = random_seed
	actors.clear()
	monsters.clear()
	combat_events.clear()
	death_events.clear()
	respawn_events.clear()
	pending_projectiles.clear()
	pending_monster_attacks.clear()
	ground_loot.clear()
	return DomainResult.ok(self)


## 执行 `set_monster_position_resolver` 对应的模块操作。
## [param resolver] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func set_monster_position_resolver(resolver: Callable) -> void:
	_monster_position_resolver = resolver


## 执行 `register_vehicle` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param assembly] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param weapons_by_ability] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func register_vehicle(
	actor_id: String,
	map_instance_id: String,
	position: Vector2,
	assembly: Dictionary,
	weapons_by_ability: Dictionary,
) -> DomainResult:
	if actor_id.is_empty() or map_instance_id.is_empty() or actors.has(actor_id) or not position.is_finite():
		return DomainResult.failure(&"combat.invalid_actor", "actor/map identity must be unique and position finite")
	var normalized_weapons: Dictionary = {}
	for raw_slot: Variant in weapons_by_ability.keys():
		var slot_id := String(raw_slot)
		if slot_id.is_empty() or not weapons_by_ability[raw_slot] is Dictionary:
			return DomainResult.failure(&"combat.invalid_weapon_definition", "weapon slot or definition is invalid")
		var weapon_result := _normalize_energy_cannon(weapons_by_ability[raw_slot])
		if not weapon_result.is_ok:
			return weapon_result
		normalized_weapons[slot_id] = weapon_result.value
	var vehicle_state: VehicleCombatState = VehicleCombatStateScript.new()
	var state_result := vehicle_state.configure(assembly)
	if not state_result.is_ok:
		return state_result
	actors[actor_id] = {
		"map_instance_id": map_instance_id,
		"position": position,
		"previous_position": position,
		"position_sample_tick": -1,
		"vehicle_state": vehicle_state,
		"weapons": normalized_weapons,
		"cooldown_ready_ticks": {},
		"last_command_sequence": -1,
	}
	return DomainResult.ok(vehicle_state)


## 执行 `register_monster` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func register_monster(definition: Dictionary) -> DomainResult:
	var lifecycle: MonsterLifecycle = MonsterLifecycleScript.new()
	var result := lifecycle.configure(definition, simulation_hz)
	if not result.is_ok:
		return result
	if monsters.has(lifecycle.monster_id):
		return DomainResult.failure(&"combat.duplicate_monster", "monster identity is already registered")
	monsters[lifecycle.monster_id] = lifecycle
	return DomainResult.ok(lifecycle)


## 执行 `unregister_vehicle` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func unregister_vehicle(actor_id: String) -> bool:
	return actors.erase(actor_id)


## 执行 `update_actor_position` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func update_actor_position(actor_id: String, position: Vector2) -> DomainResult:
	if not actors.has(actor_id):
		return DomainResult.failure(&"combat.unknown_actor", "actor is not registered")
	if not position.is_finite():
		return DomainResult.failure(&"combat.invalid_position", "actor position must be finite")
	var actor: Dictionary = actors[actor_id]
	if int(actor["position_sample_tick"]) != current_tick:
		actor["previous_position"] = actor["position"]
		actor["position_sample_tick"] = current_tick
	actor["position"] = position
	return DomainResult.ok(position)


## 执行 `handle_energy_cannon_attack` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param raw_intent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：客户端只提供瞄准坐标；服务端一次求出射线首个交点并延迟到弹体抵达时结算。
func handle_energy_cannon_attack(actor_id: String, raw_intent: Variant) -> DomainResult:
	if not actors.has(actor_id):
		return DomainResult.failure(&"combat.unknown_actor", "authenticated actor is not registered")
	var intent_result = UseAbilityIntentContract.from_dictionary(raw_intent)
	if not intent_result.is_ok:
		return intent_result
	var intent: UseAbilityIntent = intent_result.value
	var map_instance_id := intent.map_instance_id
	var ability_id := intent.ability_id
	var requested_aim := intent.aim_world_position
	var command_sequence := intent.input_sequence
	var actor: Dictionary = actors[actor_id]
	if command_sequence < 0 or command_sequence <= int(actor["last_command_sequence"]):
		return DomainResult.failure(&"combat.stale_command", "attack command sequence is stale")
	actor["last_command_sequence"] = command_sequence
	if map_instance_id != String(actor["map_instance_id"]):
		return DomainResult.failure(&"combat.map_instance_mismatch", "ability intent targets another map instance")
	if not actor["weapons"].has(ability_id):
		return DomainResult.failure(&"combat.weapon_not_equipped", "energy-cannon ability is not equipped")
	var weapon: Dictionary = actor["weapons"][ability_id]
	var ready_tick := int(actor["cooldown_ready_ticks"].get(ability_id, 0))
	if current_tick < ready_tick:
		return DomainResult.failure(&"combat.weapon_cooldown", "energy cannon is cooling down")
	var actor_position: Vector2 = actor["position"]
	var aim := requested_aim - actor_position
	if not requested_aim.is_finite() or aim.length_squared() < 4.0:
		return DomainResult.failure(&"combat.invalid_aim", "energy-cannon aim must be finite and distinct from the actor")
	var vehicle_state: VehicleCombatState = actor["vehicle_state"]
	if weapon["activation_power"] != null \
		and not vehicle_state.supports_activation_power(float(weapon["activation_power"])):
		return DomainResult.failure(&"combat.insufficient_power_output", "vehicle output budget cannot activate weapon")
	var energy_result := vehicle_state.consume_working_energy(float(weapon["working_energy_cost"]))
	if not energy_result.is_ok:
		return energy_result
	actor["cooldown_ready_ticks"][ability_id] = current_tick + int(weapon["cooldown_ticks"])
	var direction := aim.normalized()
	var resolved_distance := minf(aim.length(), float(weapon["range"]))
	var endpoint := actor_position + direction * resolved_distance
	var origin := _projectile_origin(actor_position, direction, resolved_distance, weapon)
	var collision := _first_projectile_collision(map_instance_id, origin, endpoint)
	var impact_position := Vector2(collision.get("position", endpoint))
	var travel_distance := origin.distance_to(impact_position)
	var travel_ticks := maxi(
		1,
		ceili(travel_distance / float(weapon["projectile_speed"]) * float(simulation_hz)),
	)
	_shot_sequence += 1
	var shot_id := "%s.shot.%d" % [actor_id, _shot_sequence]
	var target_id := String(collision.get("target_entity_id", ""))
	pending_projectiles.append({
		"shot_id": shot_id,
		"impact_tick": current_tick + travel_ticks,
		"attacker_id": actor_id,
		"target_entity_id": target_id,
		"weapon": weapon.duplicate(true),
		"impact_position": impact_position,
	})
	var event := _record_combat_event({
		"event_type": &"energy_cannon_projectile_spawned",
		"server_tick": current_tick,
		"impact_tick": current_tick + travel_ticks,
		"shot_id": shot_id,
		"attacker_id": actor_id,
		"target_entity_id": target_id,
		"weapon_id": weapon["weapon_id"],
		"origin": [origin.x, origin.y],
		"direction": [direction.x, direction.y],
		"maximum_distance": resolved_distance,
		"impact_position": [impact_position.x, impact_position.y],
		"damage": 0,
		"working_energy": vehicle_state.working_energy,
		"cooldown_ready_tick": actor["cooldown_ready_ticks"][ability_id],
	})
	return DomainResult.ok(event)


## 计算与客户端预测一致的炮口世界坐标。
## [param actor_position] 发射者权威脚点。
## [param direction] 已归一化发射方向。
## [param resolved_distance] 本次被射程钳制后的总距离。
## [param weapon] 服务端规范化后的武器定义。
## 返回弹体连续碰撞线段的起点。
func _projectile_origin(
	actor_position: Vector2,
	direction: Vector2,
	resolved_distance: float,
	weapon: Dictionary,
) -> Vector2:
	var offset_values: Array = weapon["muzzle_offset"]
	var muzzle_offset := Vector2(float(offset_values[0]), float(offset_values[1]))
	var forward_offset := minf(float(weapon["muzzle_forward_offset"]), resolved_distance * 0.5)
	return actor_position + muzzle_offset + direction * forward_offset


## 在发射瞬间的权威怪物位置中查找最先与弹道相交的存活怪物。
## [param map_instance_id] 发射者当前权威地图实例。
## [param origin] 权威弹体起点。
## [param endpoint] 由瞄准方向和当前射程确定的弹道终点。
## 返回首个交点及目标；整段无目标时返回 `hit=false`。
## 设计：复杂度为每次开火 O(当前地图怪物数)，不随弹体飞行帧数增长。
func _first_projectile_collision(
	map_instance_id: String,
	origin: Vector2,
	endpoint: Vector2,
) -> Dictionary:
	var best := {"hit": false, "t": INF}
	var monster_ids := monsters.keys()
	monster_ids.sort()
	for monster_id: String in monster_ids:
		var monster: MonsterLifecycle = monsters[monster_id]
		if monster.map_instance_id != map_instance_id or not monster.is_alive():
			continue
		var candidate := ProjectileSweep.segment_circle_intersection(
			origin,
			endpoint,
			monster.position + monster.attack_mode.projectile_hitbox_offset,
			monster.attack_mode.projectile_hitbox_radius,
		)
		if not bool(candidate.get("hit", false)) or float(candidate["t"]) >= float(best["t"]):
			continue
		best = candidate
		best["target_entity_id"] = monster_id
	return best


## 在当前权威 tick 结算所有已经飞抵预计算交点的炮弹。
## 设计：弹体不逐帧推进；命中对象在发射时确定，扣血只在 `impact_tick` 发生。
func _settle_due_projectiles() -> void:
	var index := 0
	while index < pending_projectiles.size():
		var projectile: Dictionary = pending_projectiles[index]
		if int(projectile["impact_tick"]) > current_tick:
			index += 1
			continue
		pending_projectiles.remove_at(index)
		_settle_projectile(projectile)


## 结算一颗到达交点的炮弹，并产生可去重的命中、失效及死亡事件。
## [param projectile] 发射时冻结的权威弹体预约。
func _settle_projectile(projectile: Dictionary) -> void:
	var target_id := String(projectile["target_entity_id"])
	var impact_position: Vector2 = projectile["impact_position"]
	if target_id.is_empty() or not monsters.has(target_id):
		_record_projectile_expired(projectile, impact_position)
		return
	var monster: MonsterLifecycle = monsters[target_id]
	if not monster.is_alive():
		_record_projectile_expired(projectile, impact_position)
		return
	var weapon: Dictionary = projectile["weapon"]
	var attacker_id := String(projectile["attacker_id"])
	var damage := _random.randi_range(int(weapon["minimum_damage"]), int(weapon["maximum_damage"]))
	var damage_result := monster.apply_damage(damage, attacker_id, current_tick)
	if not damage_result.is_ok:
		_record_projectile_expired(projectile, impact_position)
		return
	var event := _record_combat_event({
		"event_type": &"energy_cannon_hit",
		"server_tick": current_tick,
		"impact_tick": current_tick,
		"shot_id": projectile["shot_id"],
		"attacker_id": attacker_id,
		"target_entity_id": target_id,
		"weapon_id": weapon["weapon_id"],
		"impact_position": [impact_position.x, impact_position.y],
		"damage": damage_result.value["applied_damage"],
		"target_health": damage_result.value["health"],
	})
	if bool(damage_result.value["died"]):
		var spawned_loot := _spawn_monster_loot(monster, attacker_id)
		var death_event := {
			"event_type": &"monster_died",
			"server_tick": current_tick,
			"monster_id": target_id,
			"killer_id": attacker_id,
			"death_generation": damage_result.value["death_generation"],
			"respawn_at_tick": damage_result.value["respawn_at_tick"],
			"position": [monster.position.x, monster.position.y],
			"loot_drops": spawned_loot,
		}
		death_events.append(death_event)
		event["death"] = death_event.duplicate(true)


## 记录飞满射程或预定目标已消失的无伤害结束事件。
## [param projectile] 发射时冻结的权威弹体预约。
## [param impact_position] 客户端应结束权威弹体的世界坐标。
func _record_projectile_expired(projectile: Dictionary, impact_position: Vector2) -> void:
	_record_combat_event({
		"event_type": &"energy_cannon_projectile_expired",
		"server_tick": current_tick,
		"impact_tick": current_tick,
		"shot_id": projectile["shot_id"],
		"attacker_id": projectile["attacker_id"],
		"target_entity_id": "",
		"impact_position": [impact_position.x, impact_position.y],
		"damage": 0,
	})


## 执行 `advance_ticks` 对应的模块操作。
## [param tick_count] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func advance_ticks(tick_count: int) -> DomainResult:
	if tick_count < 0:
		return DomainResult.failure(&"combat.invalid_tick_count", "tick count cannot be negative")
	var emitted_respawns: Array[Dictionary] = []
	var fixed_delta := 1.0 / float(simulation_hz)
	for unused_tick: int in range(tick_count):
		current_tick += 1
		for actor_id: String in actors:
			var vehicle_state: VehicleCombatState = actors[actor_id]["vehicle_state"]
			vehicle_state.regenerate_working_energy(fixed_delta, working_energy_regen_factor)
		_settle_due_projectiles()
		_settle_due_monster_attacks()
		_commit_actor_position_samples()
		for monster_id: String in monsters:
			var monster: MonsterLifecycle = monsters[monster_id]
			var lifecycle_result := monster.advance_to_tick(current_tick)
			if bool(lifecycle_result.value["respawned"]):
				monster.next_wander_tick = current_tick + monster.wander_interval_ticks
				var respawn_event := {
					"event_type": &"monster_respawned",
					"server_tick": current_tick,
					"monster_id": monster_id,
					"death_generation": monster.death_generation,
				}
				respawn_events.append(respawn_event)
				emitted_respawns.append(respawn_event)
			if monster.is_alive():
				_simulate_monster_tick(monster_id, fixed_delta)
	return DomainResult.ok(emitted_respawns)


## 执行 `snapshot_for_actor` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot_for_actor(actor_id: String) -> Dictionary:
	if not actors.has(actor_id):
		return {}
	var actor: Dictionary = actors[actor_id]
	var map_instance_id := String(actor["map_instance_id"])
	var monster_snapshots: Array[Dictionary] = []
	var monster_ids := monsters.keys()
	monster_ids.sort()
	for monster_id: String in monster_ids:
		var monster: MonsterLifecycle = monsters[monster_id]
		if monster.map_instance_id != map_instance_id:
			continue
		monster_snapshots.append({
			"entity_id": monster_id,
			"species_id": monster.species_id,
			"display_name": monster.display_name,
			"combat_actor_id": monster.combat_actor_id,
			"position": [monster.position.x, monster.position.y],
			"health": monster.health,
			"max_health": monster.max_health,
			"alive": monster.is_alive(),
			"action": String(monster.action),
			"action_sequence": monster.action_sequence,
			"facing_index": monster.facing_direction,
		})
	return {
		"server_tick": current_tick,
		"local_entity_id": actor_id,
		"local_vehicle": (actor["vehicle_state"] as VehicleCombatState).to_dictionary(),
		"monsters": monster_snapshots,
		"ground_loot": _ground_loot_for_map(map_instance_id),
		"recent_events": combat_events.slice(maxi(0, combat_events.size() - 32)).duplicate(true),
	}


## 预检玩家拾取地面掉落物的身份、地图和距离。
## [param actor_id] 由认证会话绑定的玩家实体标识。
## [param loot_id] 客户端仅用于指明目标的掉落实例标识。
## 返回可交给背包事务的掉落值对象，或身份、地图、距离错误。
## 设计：本函数不移除掉落物，确保背包或持久化提交失败时不会吞掉物品。
func prepare_loot_pickup(actor_id: String, loot_id: String) -> DomainResult:
	if not actors.has(actor_id):
		return DomainResult.failure(&"combat.unknown_actor", "authenticated actor is not registered")
	var loot_value: Variant = ground_loot.get(loot_id)
	if not loot_value is Dictionary:
		return DomainResult.failure(&"loot.not_found", "ground loot does not exist")
	var actor: Dictionary = actors[actor_id]
	var loot: Dictionary = loot_value
	if String(loot["map_instance_id"]) != String(actor["map_instance_id"]):
		return DomainResult.failure(&"loot.map_mismatch", "ground loot belongs to another map instance")
	var loot_position := Vector2(float(loot["position"][0]), float(loot["position"][1]))
	if (actor["position"] as Vector2).distance_to(loot_position) > LOOT_PICKUP_RADIUS:
		return DomainResult.failure(&"loot.out_of_range", "ground loot is outside pickup range")
	return DomainResult.ok(loot.duplicate(true))


## 在背包事务成功后提交一次地面掉落移除。
## [param actor_id] 已通过会话认证并完成背包入账的玩家实体标识。
## [param loot_id] 待移除的掉落实例标识。
## 返回拾取事件或并发状态变化错误。
func commit_loot_pickup(actor_id: String, loot_id: String) -> DomainResult:
	var prepared := prepare_loot_pickup(actor_id, loot_id)
	if not prepared.is_ok:
		return prepared
	var loot: Dictionary = prepared.value
	ground_loot.erase(loot_id)
	return DomainResult.ok(_record_combat_event({
		"event_type": &"loot_picked_up",
		"server_tick": current_tick,
		"actor_id": actor_id,
		"loot_id": loot_id,
		"item_definition_id": loot["item_definition_id"],
		"quantity": loot["quantity"],
	}))


## 将怪物领域掉落结果生成为当前地图的权威地面实体。
## [param monster] 本次死亡且持有掉落表的怪物聚合。
## [param killer_id] 触发死亡结算的玩家实体标识。
## 返回嵌入死亡事件的掉落 DTO 数组。
func _spawn_monster_loot(monster: MonsterLifecycle, killer_id: String) -> Array[Dictionary]:
	var spawned: Array[Dictionary] = []
	for rolled: Dictionary in monster.drop_table.roll(_random):
		_loot_sequence += 1
		var loot_id := "%s.loot.%d.%d" % [monster.monster_id, monster.death_generation, _loot_sequence]
		var loot := {
			"loot_id": loot_id,
			"map_instance_id": monster.map_instance_id,
			"source_monster_id": monster.monster_id,
			"killer_id": killer_id,
			"item_definition_id": String(rolled["item_definition_id"]),
			"quantity": int(rolled["quantity"]),
			"position": [monster.position.x, monster.position.y],
			"spawn_tick": current_tick,
		}
		ground_loot[loot_id] = loot
		spawned.append(loot.duplicate(true))
	return spawned


## 查询指定地图当前可见的全部地面掉落物。
## [param map_instance_id] 快照接收玩家所在的地图实例标识。
## 返回按稳定 loot_id 排序的 DTO 数组。
func _ground_loot_for_map(map_instance_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var loot_ids := ground_loot.keys()
	loot_ids.sort()
	for loot_id: String in loot_ids:
		var loot: Dictionary = ground_loot[loot_id]
		if String(loot["map_instance_id"]) == map_instance_id:
			result.append(loot.duplicate(true))
	return result


## 执行 `simulate_monster_tick` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fixed_delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _simulate_monster_tick(monster_id: String, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var target_id := _engaged_actor_id(monster)
	if target_id.is_empty():
		_simulate_unengaged_monster(monster_id, fixed_delta)
		return
	var actor: Dictionary = actors[target_id]
	var target_position: Vector2 = actor["position"]
	var home_position := monster.home_position
	if monster.position.distance_to(home_position) > monster.leash_distance:
		_move_monster_towards_home(monster_id, fixed_delta)
		return
	monster.target_actor_id = target_id
	var distance := monster.position.distance_to(target_position)
	if distance > monster.attack_mode.attack_range:
		_move_monster(monster_id, target_position, fixed_delta)
		return
	monster.action = &"attack"
	monster.face(target_position - monster.position)
	if current_tick < monster.attack_ready_tick:
		return
	monster.attack_ready_tick = current_tick + monster.attack_mode.interval_ticks
	monster.action_sequence += 1
	_begin_monster_attack(monster_id, target_id, target_position)


## 创建一次怪物攻击；远程弹体固定方向飞行，贴身攻击在当前 tick 结算。
## [param monster_id] 权威攻击者实体 ID。
## [param target_id] 权威目标玩家 ID。
## [param target_position] 发起攻击时冻结的目标脚点。
func _begin_monster_attack(monster_id: String, target_id: String, target_position: Vector2) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var attack_archetype: StringName = monster.attack_mode.archetype
	var origin := monster.position + Vector2(0.0, -24.0)
	var endpoint := target_position + Vector2(0.0, -16.0)
	var impact_tick := current_tick
	if attack_archetype != &"contact_melee":
		if not monster.attack_mode.is_projectile():
			return
		var projectile_speed: float = monster.attack_mode.projectile_speed
		if projectile_speed <= 0.0:
			return
		impact_tick += maxi(
			1,
			ceili(origin.distance_to(endpoint) / projectile_speed * float(simulation_hz)),
		)
	_monster_attack_sequence += 1
	var attack_id := "%s.attack.%d" % [monster_id, _monster_attack_sequence]
	var attack := {
		"attack_id": attack_id,
		"impact_tick": impact_tick,
		"attacker_id": monster_id,
		"target_entity_id": target_id,
		"map_instance_id": monster.map_instance_id,
		"damage": monster.attack_mode.base_attack,
		"attack_archetype": attack_archetype,
		"combat_actor_id": monster.combat_actor_id,
		"projectile_speed": monster.attack_mode.projectile_speed,
		"origin": origin,
		"target_position": endpoint,
		"current_position": origin,
	}
	_record_combat_event({
		"event_type": &"monster_attack_started",
		"server_tick": current_tick,
		"impact_tick": impact_tick,
		"attack_id": attack_id,
		"attacker_id": monster_id,
		"target_entity_id": target_id,
		"attack_archetype": attack_archetype,
		"combat_actor_id": monster.combat_actor_id,
		"projectile_speed": monster.attack_mode.projectile_speed,
		"origin": [origin.x, origin.y],
		"target_position": [endpoint.x, endpoint.y],
	})
	if impact_tick == current_tick:
		_resolve_monster_attack(attack)
	else:
		pending_monster_attacks.append(attack)


## 按固定 tick 推进怪物远程弹体，并对玩家本 tick 的移动线段做连续碰撞。
func _settle_due_monster_attacks() -> void:
	for index in range(pending_monster_attacks.size() - 1, -1, -1):
		var attack: Dictionary = pending_monster_attacks[index]
		var current_position: Vector2 = attack["current_position"]
		var target_position: Vector2 = attack["target_position"]
		var tick_distance := float(attack["projectile_speed"]) / float(simulation_hz)
		var next_position := current_position.move_toward(target_position, tick_distance)
		var collision := _first_actor_projectile_collision(
			String(attack["map_instance_id"]), current_position, next_position
		)
		if bool(collision.get("hit", false)):
			pending_monster_attacks.remove_at(index)
			attack["target_entity_id"] = String(collision["target_entity_id"])
			attack["impact_position"] = collision["position"]
			_resolve_monster_attack(attack)
			continue
		attack["current_position"] = next_position
		if next_position.is_equal_approx(target_position) or int(attack["impact_tick"]) <= current_tick:
			pending_monster_attacks.remove_at(index)
			_record_monster_attack_expired(attack, next_position)


## 查找当前逻辑 tick 内最先接住怪物弹体的存活玩家。
## [param map_instance_id] 弹体所属的权威地图实例。
## [param segment_start] 弹体在本逻辑 tick 的起点。
## [param segment_end] 弹体在本逻辑 tick 的终点。
## 返回最早交点、实际目标玩家和归一化线段参数；无交点时返回 `hit=false`。
## 玩家与弹体都可能在 tick 内移动，因此在相对坐标中扫掠两条线段，避免穿透或躲开后仍命中。
func _first_actor_projectile_collision(
	map_instance_id: String,
	segment_start: Vector2,
	segment_end: Vector2,
) -> Dictionary:
	var best := {"hit": false, "t": INF}
	var actor_ids := actors.keys()
	actor_ids.sort()
	for actor_id: String in actor_ids:
		var actor: Dictionary = actors[actor_id]
		var vehicle_state: VehicleCombatState = actor["vehicle_state"]
		if String(actor["map_instance_id"]) != map_instance_id or vehicle_state.health <= 0:
			continue
		var previous_center: Vector2 = actor["previous_position"] + ACTOR_PROJECTILE_HITBOX_OFFSET
		var current_center: Vector2 = actor["position"] + ACTOR_PROJECTILE_HITBOX_OFFSET
		var relative_start := segment_start - previous_center
		var relative_end := segment_end - current_center
		var candidate: Dictionary
		if relative_start.length_squared() <= ACTOR_PROJECTILE_HITBOX_RADIUS * ACTOR_PROJECTILE_HITBOX_RADIUS:
			candidate = {"hit": true, "t": 0.0}
		else:
			candidate = ProjectileSweep.segment_circle_intersection(
				relative_start,
				relative_end,
				Vector2.ZERO,
				ACTOR_PROJECTILE_HITBOX_RADIUS,
			)
		if not bool(candidate.get("hit", false)) or float(candidate["t"]) >= float(best["t"]):
			continue
		best = candidate
		best["position"] = segment_start.lerp(segment_end, float(candidate["t"]))
		best["target_entity_id"] = actor_id
	return best


## 在权威到达 tick 对仍有效的玩家目标应用怪物伤害。
## [param attack] 发起攻击时冻结的权威预约。
func _resolve_monster_attack(attack: Dictionary) -> void:
	var target_id := String(attack["target_entity_id"])
	if not actors.has(target_id):
		return
	var actor: Dictionary = actors[target_id]
	if String(actor["map_instance_id"]) != String(attack["map_instance_id"]):
		return
	var vehicle_state: VehicleCombatState = actor["vehicle_state"]
	if vehicle_state.health <= 0:
		return
	var damage_result := vehicle_state.apply_damage(int(attack["damage"]))
	if not damage_result.is_ok:
		return
	var impact_position := Vector2(
		attack.get("impact_position", actor["position"] + ACTOR_PROJECTILE_HITBOX_OFFSET)
	)
	_record_combat_event({
		"event_type": &"monster_attack_resolved",
		"server_tick": current_tick,
		"impact_tick": current_tick,
		"attack_id": attack["attack_id"],
		"attacker_id": attack["attacker_id"],
		"target_entity_id": target_id,
		"attack_archetype": attack["attack_archetype"],
		"combat_actor_id": attack["combat_actor_id"],
		"impact_position": [impact_position.x, impact_position.y],
		"damage": int(damage_result.value["applied_damage"]),
		"target_health": int(damage_result.value["health"]),
		"target_destroyed": bool(damage_result.value["destroyed"]),
	})


## 记录怪物弹体抵达原始瞄准点但没有碰到任何玩家。
## [param attack] 正在结束的权威怪物攻击状态。
## [param impact_position] 弹体无伤害消失的世界坐标。
func _record_monster_attack_expired(attack: Dictionary, impact_position: Vector2) -> void:
	_record_combat_event({
		"event_type": &"monster_attack_expired",
		"server_tick": current_tick,
		"impact_tick": current_tick,
		"attack_id": attack["attack_id"],
		"attacker_id": attack["attacker_id"],
		"target_entity_id": "",
		"attack_archetype": attack["attack_archetype"],
		"combat_actor_id": attack["combat_actor_id"],
		"impact_position": [impact_position.x, impact_position.y],
		"damage": 0,
	})


## 在一次权威 tick 结束前确认玩家位置样本，下一 tick 未移动时不重复扫掠旧路径。
func _commit_actor_position_samples() -> void:
	for actor_id: String in actors:
		actors[actor_id]["previous_position"] = actors[actor_id]["position"]


## 执行 `engaged_actor_id` 对应的模块操作。
## [param monster] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：`npcinfo.attr_10` 的 0/1/2 在数据层转换为枚举，运行时不依赖怪物名称。
func _engaged_actor_id(monster: MonsterLifecycle) -> String:
	var current_target := monster.target_actor_id
	if not current_target.is_empty() and _is_valid_actor_target(monster, current_target):
		return current_target
	monster.clear_target()
	if monster.can_acquire_target():
		return _nearest_alive_actor(monster)
	return ""


## 执行 `is_valid_actor_target` 对应的模块操作。
## [param monster] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _is_valid_actor_target(monster: MonsterLifecycle, actor_id: String) -> bool:
	if not actors.has(actor_id):
		return false
	var actor: Dictionary = actors[actor_id]
	var state: VehicleCombatState = actor["vehicle_state"]
	return state.health > 0 and String(actor["map_instance_id"]) == monster.map_instance_id


## 执行 `record_combat_event` 对应的模块操作。
## [param event] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：快照携带短事件窗口以容忍 UDP/快照丢包，客户端按事件号去重。
func _record_combat_event(event: Dictionary) -> Dictionary:
	event_sequence += 1
	var recorded := event.duplicate(true)
	recorded["event_id"] = event_sequence
	combat_events.append(recorded)
	if combat_events.size() > 64:
		combat_events.pop_front()
	return recorded


## 执行 `nearest_alive_actor` 对应的模块操作。
## [param monster] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _nearest_alive_actor(monster: MonsterLifecycle) -> String:
	var best_id := ""
	var best_distance := INF
	for actor_id: String in actors:
		var actor: Dictionary = actors[actor_id]
		var state: VehicleCombatState = actor["vehicle_state"]
		if state.health <= 0 or String(actor["map_instance_id"]) != monster.map_instance_id:
			continue
		var distance := monster.position.distance_to(actor["position"])
		if distance <= monster.aggro_radius and distance < best_distance:
			best_id = actor_id
			best_distance = distance
	return best_id


## 执行 `move_monster_towards_home` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fixed_delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _move_monster_towards_home(monster_id: String, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	monster.clear_target()
	var home_position := monster.home_position
	if monster.position.distance_to(home_position) <= 1.0:
		monster.action = &"idle"
		return
	_move_monster(monster_id, home_position, fixed_delta)


## 执行 `simulate_unengaged_monster` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fixed_delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _simulate_unengaged_monster(monster_id: String, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	monster.clear_target()
	var home_position := monster.home_position
	var wander_radius := monster.wander_radius
	if wander_radius <= 0.0:
		_move_monster_towards_home(monster_id, fixed_delta)
		return
	if monster.position.distance_to(home_position) > wander_radius + 8.0:
		_move_monster_towards_home(monster_id, fixed_delta)
		return
	var wander_target := monster.wander_target
	var reached_target := monster.position.distance_to(wander_target) <= 2.0
	if not reached_target:
		_move_monster(monster_id, wander_target, fixed_delta)
		return
	if monster.action == &"move":
		monster.action = &"idle"
		monster.wander_target = monster.position
		monster.next_wander_tick = current_tick + monster.wander_interval_ticks
		return
	if current_tick < monster.next_wander_tick:
		monster.action = &"idle"
		return
	if current_tick >= monster.next_wander_tick:
		var phase_degrees := posmod(hash(monster_id) + current_tick * 47, 360)
		var radius_factor := 0.35 + float(posmod(hash(monster_id) + current_tick, 60)) / 100.0
		wander_target = home_position + Vector2.RIGHT.rotated(deg_to_rad(phase_degrees)) * wander_radius * radius_factor
		monster.wander_target = wander_target
	_move_monster(monster_id, wander_target, fixed_delta)


## 执行 `move_monster` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param target_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fixed_delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _move_monster(monster_id: String, target_position: Vector2, fixed_delta: float) -> void:
	var monster: MonsterLifecycle = monsters[monster_id]
	var delta := target_position - monster.position
	if delta.is_zero_approx():
		monster.action = &"idle"
		return
	var requested := monster.position + delta.normalized() * minf(
		delta.length(), monster.movement_speed * fixed_delta
	)
	var admitted := requested
	if _monster_position_resolver.is_valid():
		var resolved: Variant = _monster_position_resolver.call(monster_id, monster.position, requested)
		if resolved is Vector2:
			admitted = resolved
	if admitted.is_finite():
		monster.position = admitted
		monster.action = &"move"
		monster.face(delta)


## 执行 `vehicle_state_for` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func vehicle_state_for(actor_id: String) -> VehicleCombatState:
	if not actors.has(actor_id):
		return null
	return actors[actor_id]["vehicle_state"]


## 执行 `monster_for` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func monster_for(monster_id: String) -> MonsterLifecycle:
	return monsters.get(monster_id)


## 查询当前权威模块登记的全部怪物标识。
## 返回按字典当前顺序复制的标识数组。
func monster_ids() -> Array:
	return monsters.keys().duplicate()


## 执行 `normalize_energy_cannon` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _normalize_energy_cannon(definition: Dictionary) -> DomainResult:
	var weapon_id := String(definition.get("weapon_id", ""))
	var minimum_damage := int(definition.get("minimum_damage", -1))
	var maximum_damage := int(definition.get("maximum_damage", -1))
	var working_energy_cost := float(definition.get("working_energy_cost", -1.0))
	var raw_activation_power: Variant = definition.get("activation_power", null)
	var activation_power: Variant = null
	if raw_activation_power != null:
		if typeof(raw_activation_power) != TYPE_INT and typeof(raw_activation_power) != TYPE_FLOAT:
			return DomainResult.failure(&"combat.invalid_weapon_definition", "activation power must be numeric or explicitly unknown")
		activation_power = float(raw_activation_power)
	var attack_range := float(definition.get("range", 0.0))
	var upgrade_range_limit := float(definition.get("upgrade_range_limit", attack_range))
	var cooldown_ticks := int(definition.get("cooldown_ticks", 0))
	var projectile_speed := float(definition.get("projectile_speed", 0.0))
	var muzzle_offset_value: Variant = definition.get("muzzle_offset", [])
	var muzzle_forward_offset := float(definition.get("muzzle_forward_offset", -1.0))
	if weapon_id.is_empty() or minimum_damage < 0 or maximum_damage < minimum_damage:
		return DomainResult.failure(&"combat.invalid_weapon_definition", "energy-cannon damage definition is invalid")
	if working_energy_cost < 0.0 or (activation_power != null and float(activation_power) < 0.0) \
		or attack_range <= 0.0 or upgrade_range_limit < attack_range or cooldown_ticks <= 0 \
		or projectile_speed <= 0.0 or muzzle_forward_offset < 0.0 \
		or not muzzle_offset_value is Array or muzzle_offset_value.size() != 2:
		return DomainResult.failure(&"combat.invalid_weapon_definition", "energy-cannon resource or timing definition is invalid")
	return DomainResult.ok({
		"weapon_id": weapon_id,
		"minimum_damage": minimum_damage,
		"maximum_damage": maximum_damage,
		"working_energy_cost": working_energy_cost,
		"activation_power": activation_power,
		"range": attack_range,
		"upgrade_range_limit": upgrade_range_limit,
		"cooldown_ticks": cooldown_ticks,
		"projectile_speed": projectile_speed,
		"muzzle_offset": [float(muzzle_offset_value[0]), float(muzzle_offset_value[1])],
		"muzzle_forward_offset": muzzle_forward_offset,
	})
