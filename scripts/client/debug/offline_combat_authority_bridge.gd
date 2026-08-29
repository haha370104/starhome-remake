class_name OfflineCombatAuthorityBridge
extends Node

const CombatCatalogScript := preload("res://scripts/domain/combat/combat_definition_catalog.gd")
const CombatModuleScript := preload("res://scripts/server/modules/combat/authoritative_combat_module.gd")
const UseAbilityIntentScript := preload("res://scripts/network/contracts/use_ability_intent.gd")

signal combat_snapshot_ready(snapshot: Dictionary)
signal combat_event_ready(event: Dictionary)

const SIMULATION_HZ := 20
const SNAPSHOT_INTERVAL_TICKS := 2
const LOCAL_ACTOR_ID := "player.local"
const ABILITY_ID := "energy_cannon.primary"

var module: AuthoritativeCombatModule
var navigation
var map_instance_id := ""
var player_position := Vector2.ZERO
var _accumulator := 0.0
var _next_command_sequence := 1


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
	if not assembly_result.is_ok or not weapon_result.is_ok:
		return ERR_INVALID_DATA
	module = CombatModuleScript.new()
	if not module.configure(SIMULATION_HZ, hash(map_instance_id), 1.0).is_ok:
		return ERR_INVALID_DATA
	module.set_monster_position_resolver(_resolve_monster_position)
	if not module.register_vehicle(
		LOCAL_ACTOR_ID,
		map_instance_id,
		player_position,
		assembly_result.value,
		{ABILITY_ID: weapon_result.value},
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
	player_position = position
	if module != null:
		module.update_actor_position(LOCAL_ACTOR_ID, position)


## 执行 `request_attack` 对应的模块操作。
## [param aim_world_position] 瞄准世界坐标，只用于表达发射方向。
## 返回该函数计算、查询或操作得到的结果。
func request_attack(aim_world_position: Vector2) -> Dictionary:
	if module == null or not aim_world_position.is_finite():
		return {"ok": false, "code": &"combat.invalid_aim"}
	var intent := UseAbilityIntentScript.new(
		map_instance_id, ABILITY_ID, aim_world_position, _next_command_sequence
	)
	_next_command_sequence += 1
	var result = module.handle_energy_cannon_attack(LOCAL_ACTOR_ID, intent.to_dictionary())
	if result.is_ok:
		combat_event_ready.emit(result.value.duplicate(true))
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
		if module.current_tick % SNAPSHOT_INTERVAL_TICKS == 0:
			_emit_snapshot()


## 发布 `emit_snapshot` 对应的模块状态。
func _emit_snapshot() -> void:
	if module != null:
		combat_snapshot_ready.emit(module.snapshot_for_actor(LOCAL_ACTOR_ID))


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
