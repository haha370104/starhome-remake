class_name MonsterLifecycle
extends RefCounted

const DomainResult := preload("res://scripts/core/domain_result.gd")

var monster_id := ""
var map_instance_id := ""
var position := Vector2.ZERO
var max_health := 0
var health := 0
var respawn_delay_ticks := 0
var respawn_at_tick := -1
var death_generation := 0
var last_killer_id := ""


## 执行 `configure` 对应的模块操作。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param simulation_hz] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(definition: Dictionary, simulation_hz: int) -> DomainResult:
	var requested_id := String(definition.get("monster_id", ""))
	var requested_map_instance_id := String(definition.get("map_instance_id", ""))
	var requested_position: Variant = definition.get("position", Vector2.INF)
	var requested_health := int(definition.get("max_health", 0))
	var requested_respawn_seconds := float(definition.get("respawn_seconds", -1.0))
	if requested_id.is_empty() or requested_map_instance_id.is_empty() or not requested_position is Vector2:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster, map identity and position are required")
	if not requested_position.is_finite() or requested_health <= 0:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster position or health is invalid")
	if simulation_hz <= 0 or requested_respawn_seconds < 0.0:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster respawn timing is invalid")
	monster_id = requested_id
	map_instance_id = requested_map_instance_id
	position = requested_position
	max_health = requested_health
	health = max_health
	respawn_delay_ticks = roundi(requested_respawn_seconds * float(simulation_hz))
	respawn_at_tick = -1
	death_generation = 0
	last_killer_id = ""
	return DomainResult.ok(self)


## 执行 `apply_damage` 对应的模块操作。
## [param amount] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param attacker_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param current_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数保持领域规则确定，并避免依赖具体表现层或传输层。
func apply_damage(amount: int, attacker_id: String, current_tick: int) -> DomainResult:
	if health <= 0:
		return DomainResult.failure(&"combat.target_already_dead", "monster is already dead")
	if amount < 0 or attacker_id.is_empty() or current_tick < 0:
		return DomainResult.failure(&"combat.invalid_damage", "damage attribution is invalid")
	var applied := mini(amount, health)
	health -= applied
	var died := health == 0
	if died:
		death_generation += 1
		last_killer_id = attacker_id
		respawn_at_tick = current_tick + respawn_delay_ticks
	return DomainResult.ok({
		"applied_damage": applied,
		"health": health,
		"died": died,
		"death_generation": death_generation,
		"respawn_at_tick": respawn_at_tick,
	})


## 执行 `advance_to_tick` 对应的模块操作。
## [param current_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func advance_to_tick(current_tick: int) -> DomainResult:
	if current_tick < 0:
		return DomainResult.failure(&"combat.invalid_tick", "tick cannot be negative")
	var respawned := false
	if health == 0 and respawn_at_tick >= 0 and current_tick >= respawn_at_tick:
		health = max_health
		respawn_at_tick = -1
		last_killer_id = ""
		respawned = true
	return DomainResult.ok({
		"respawned": respawned,
		"death_generation": death_generation,
		"health": health,
	})


## 判断 `is_alive` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func is_alive() -> bool:
	return health > 0


## 序列化或保存 `to_dictionary` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
func to_dictionary() -> Dictionary:
	return {
		"monster_id": monster_id,
		"map_instance_id": map_instance_id,
		"position": position,
		"max_health": max_health,
		"health": health,
		"respawn_delay_ticks": respawn_delay_ticks,
		"respawn_at_tick": respawn_at_tick,
		"death_generation": death_generation,
		"last_killer_id": last_killer_id,
	}
