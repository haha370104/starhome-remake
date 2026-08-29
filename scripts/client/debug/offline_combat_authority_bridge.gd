class_name OfflineCombatAuthorityBridge
extends Node

const CombatCatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const UseAbilityIntentScript := preload("res://scripts/network/contracts/use_ability_intent.gd")

signal combat_snapshot_ready(snapshot: Dictionary)
signal combat_event_ready(event: Dictionary)
signal skill_progression_event_ready(event: Dictionary)

const SIMULATION_HZ := 20
const SNAPSHOT_INTERVAL_TICKS := 2
const LOCAL_ACTOR_ID := "player.local"
const ABILITY_ID := "energy_cannon.primary"
const SELF_REPAIR_ABILITY_ID := "self_repair"

var module: AuthoritativeCombatModule
var navigation
var map_instance_id := ""
var player_position := Vector2.ZERO
var _accumulator := 0.0
var _next_command_sequence := 1
var _vehicle_weight := 0.0
var _last_progression_combat_event_id := 0


## 执行 `configure_map` 对应的模块操作。
## [param map_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_map_instance_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_player_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_navigation] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于客户端交互或表现边界，最终状态以服务器权威结果为准。
func configure_map(
	map_id: String,
	requested_map_instance_id: String,
	requested_player_position: Vector2,
	requested_navigation,
) -> Error:
	module = null
	navigation = requested_navigation
	map_instance_id = requested_map_instance_id
	player_position = requested_player_position
	_accumulator = 0.0
	_next_command_sequence = 1
	_vehicle_weight = 0.0
	_last_progression_combat_event_id = 0
	var catalog_result = CombatCatalogScript.load_default()
	if not catalog_result.is_ok:
		return ERR_INVALID_DATA
	var catalog = catalog_result.value
	var monsters_result = catalog.monster_lifecycles_for_map(map_id, map_instance_id)
	if not monsters_result.is_ok:
		return ERR_INVALID_DATA
	if monsters_result.value.is_empty():
		combat_snapshot_ready.emit({"server_tick": 0, "local_vehicle": {}, "monsters": []})
		return OK
	var assembly_result = catalog.starter_vehicle_assembly(10, {
		"base_speed_multiplier": 1500.0,
		"base_speed_cap": 240.0,
	})
	var weapon_result = catalog.starter_energy_cannon(SIMULATION_HZ)
	var secondary_result = catalog.starter_secondary_weapons(SIMULATION_HZ)
	if not assembly_result.is_ok or not weapon_result.is_ok or not secondary_result.is_ok:
		return ERR_INVALID_DATA
	_vehicle_weight = float(assembly_result.value.get("total_weight", 0.0))
	module = CombatModuleScript.new()
	if not module.configure(SIMULATION_HZ, hash(map_instance_id), 1.0).is_ok:
		return ERR_INVALID_DATA
	module.set_monster_position_resolver(_resolve_monster_position)
	var weapons := {ABILITY_ID: weapon_result.value}
	weapons.merge(secondary_result.value)
	if not module.register_vehicle(
		LOCAL_ACTOR_ID,
		map_instance_id,
		player_position,
		assembly_result.value,
		weapons,
	).is_ok:
		return ERR_INVALID_DATA
	for raw_definition: Variant in monsters_result.value:
		var definition: Dictionary = raw_definition.duplicate(true)
		definition["position"] = _walkable_position(definition["position"])
		if not module.register_monster(definition).is_ok:
			return ERR_INVALID_DATA
	_emit_snapshot()
	return OK


## 执行 `update_player_position` 对应的模块操作。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func update_player_position(position: Vector2) -> void:
	var accepted_distance := player_position.distance_to(position)
	player_position = position
	if module != null:
		module.update_actor_position(LOCAL_ACTOR_ID, position)
		if accepted_distance > 0.0 and _vehicle_weight > 0.0:
			skill_progression_event_ready.emit({
				"entity_id": LOCAL_ACTOR_ID,
				"source": "accepted_driving_movement",
				"skill_id": "driving",
				"distance": accepted_distance,
				"vehicle_weight": _vehicle_weight,
			})


## 执行 `request_attack` 对应的模块操作。
## [param aim_world_position] 瞄准世界坐标，只用于表达发射方向。
## 返回该函数计算、查询或操作得到的结果。
func request_attack(aim_world_position: Vector2, ability_id: String = ABILITY_ID) -> Dictionary:
	if module == null or not aim_world_position.is_finite():
		return {"ok": false, "code": &"combat.invalid_aim"}
	var intent := UseAbilityIntentScript.new(
		map_instance_id, ability_id, aim_world_position, _next_command_sequence
	)
	_next_command_sequence += 1
	var result = module.handle_weapon_attack(LOCAL_ACTOR_ID, intent.to_dictionary())
	if result.is_ok:
		combat_event_ready.emit(result.value.duplicate(true))
		_emit_snapshot()
		return {"ok": true, "value": result.value}
	return {"ok": false, "code": result.error_code, "message": result.error_message}


## 向本地权威战斗模块提交一次开始自维修意图。
## [param repair_skill_level] 当前离线玩家聚合中的维修基础等级。
## 返回启动事件或与正式服务器一致的领域拒绝。
## 设计：离线调试仍走通用能力契约；回血量、周期与能耗不由主场景直接修改。
func request_self_repair(repair_skill_level: int) -> Dictionary:
	if module == null or repair_skill_level < 0:
		return {"ok": false, "code": &"combat.not_available"}
	var intent := UseAbilityIntentScript.new(
		map_instance_id,
		SELF_REPAIR_ABILITY_ID,
		player_position,
		_next_command_sequence,
	)
	_next_command_sequence += 1
	var result = module.handle_self_repair(
		LOCAL_ACTOR_ID, intent.to_dictionary(), repair_skill_level
	)
	if result.is_ok:
		combat_event_ready.emit((result.value as Dictionary).duplicate(true))
		_emit_snapshot()
		return {"ok": true, "value": result.value}
	return {"ok": false, "code": result.error_code, "message": result.error_message}


## 预检离线调试玩家是否可以拾取指定地面掉落。
## [param loot_id] 权威战斗模块生成的掉落实例标识。
## 返回可交给正式背包入账规则的掉落 DTO 或领域拒绝。
func prepare_loot_pickup(loot_id: String):
	if module == null:
		return DomainResult.failure(&"loot.offline_unavailable", "offline combat authority is unavailable")
	return module.prepare_loot_pickup(LOCAL_ACTOR_ID, loot_id)


## 在离线背包入账成功后提交地面掉落移除并发布新快照。
## [param loot_id] 已完成入包的掉落实例标识。
## 返回拾取事件或并发、距离拒绝。
## 设计：保持与正式服务器相同的“先入包、后删地面实体”提交顺序。
func commit_loot_pickup(loot_id: String):
	if module == null:
		return DomainResult.failure(&"loot.offline_unavailable", "offline combat authority is unavailable")
	var result = module.commit_loot_pickup(LOCAL_ACTOR_ID, loot_id)
	if result.is_ok:
		combat_event_ready.emit((result.value as Dictionary).duplicate(true))
		_emit_snapshot()
	return result


## 按渲染帧推进当前节点的表现状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	if module == null or delta <= 0.0:
		return
	_accumulator += delta
	var fixed_delta := 1.0 / float(SIMULATION_HZ)
	while _accumulator + 0.000001 >= fixed_delta:
		_accumulator -= fixed_delta
		module.update_actor_position(LOCAL_ACTOR_ID, player_position)
		module.advance_ticks(1)
		_emit_combat_progression_events()
		if module.current_tick % SNAPSHOT_INTERVAL_TICKS == 0:
			_emit_snapshot()


## 发布 `emit_snapshot` 对应的模块状态。
func _emit_snapshot() -> void:
	if module != null:
		combat_snapshot_ready.emit(module.snapshot_for_actor(LOCAL_ACTOR_ID))


## 把新产生的最终有效伤害转换为离线权威技能成长事件。
## 设计：离线桥接只模拟正式服务器的内部事件，不会根据客户端发射动画直接授予经验。
func _emit_combat_progression_events() -> void:
	if module == null:
		return
	for combat_event: Dictionary in module.combat_events:
		var event_id := int(combat_event.get("event_id", 0))
		if event_id <= _last_progression_combat_event_id:
			continue
		_last_progression_combat_event_id = maxi(_last_progression_combat_event_id, event_id)
		var event_type := StringName(combat_event.get("event_type", &""))
		if event_type in [&"energy_cannon_hit", &"rocket_launcher_hit", &"missile_hit"] \
				and int(combat_event.get("damage", 0)) > 0:
			skill_progression_event_ready.emit({
				"entity_id": LOCAL_ACTOR_ID,
				"source": "effective_damage",
				"skill_id": String(combat_event.get("skill_id", "energy_cannon")),
				"damage": int(combat_event.get("damage", 0)),
				"combat_event_id": event_id,
			})
		elif event_type == &"self_repair_resolved" and int(combat_event.get("healed", 0)) > 0:
			skill_progression_event_ready.emit({
				"entity_id": LOCAL_ACTOR_ID,
				"source": "authoritative_action",
				"skill_id": "repair",
				"amount": 1.0,
				"combat_event_id": event_id,
			})


## 执行 `resolve_monster_position` 对应的模块操作。
## [param monster_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param current_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
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


## 执行 `walkable_position` 对应的模块操作。
## [param requested_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _walkable_position(requested_position: Vector2) -> Vector2:
	if navigation == null or navigation.is_walkable(requested_position):
		return requested_position
	return navigation.closest_walkable_position(requested_position)
