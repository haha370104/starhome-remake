class_name MonsterLifecycle
extends MovableEntity

const MonsterAggroPolicyScript := preload(
	"res://scripts/domain/combat/monster_aggro_policy.gd"
)
const MonsterAttackModeScript := preload(
	"res://scripts/domain/combat/monster_attack_mode.gd"
)
const DropTableScript := preload("res://scripts/domain/combat/drop_table.gd")

var monster_id := ""
var map_instance_id := ""
var species_id := ""
var display_name := ""
var combat_actor_id := ""
var behavior_profile := &"idle"
var engagement_policy = MonsterAggroPolicyScript.new()
var attack_mode = MonsterAttackModeScript.new()
var drop_table = DropTableScript.new()
var defense := 0
var max_health := 0
var health := 0
var aggro_radius := 0.0
var leash_distance := 0.0
var wander_radius := 0.0
var home_position := Vector2.ZERO
var target_actor_id := ""
var wander_target := Vector2.ZERO
var next_wander_tick := 0
var wander_interval_ticks := 0
var movement_route := PackedVector2Array()
var movement_route_index := 0
var movement_route_goal := Vector2.INF
var movement_route_kind := &""
var returning_home := false
var attack_ready_tick := 0
var action := &"idle"
var action_sequence := 0
var respawn_delay_ticks := 0
var respawn_at_tick := -1
var population_managed := false
var population_kind: StringName = &"ordinary"
var death_generation := 0
var last_killer_id := ""
var _wander_random := RandomNumberGenerator.new()
var generator_afflictions := GeneratorAfflictions.new()


## 从地图生成配置组装完整怪物领域对象。
## [param definition] 物种数值、索敌、攻击、掉落及本次生成点配置。
## [param simulation_hz] 权威服务器逻辑频率。
## [param current_tick] 本次实际生成时的权威时钟，运行中补怪不能从零起算。
## 返回配置完成的怪物或字段错误。
## 设计：怪物的生命、移动、索敌、攻击和掉落都由同一对象持有，服务端只推进模拟。
func configure(definition: Dictionary, simulation_hz: int, current_tick := 0) -> DomainResult:
	var requested_id := String(definition.get("monster_id", ""))
	var requested_map_instance_id := String(definition.get("map_instance_id", ""))
	var requested_position: Variant = definition.get("position", Vector2.INF)
	var requested_health := int(definition.get("max_health", 0))
	var requested_respawn_seconds := float(definition.get("respawn_seconds", -1.0))
	var requested_wander_interval_seconds := float(
		definition.get("wander_interval_seconds", 5.0)
	)
	var requested_policy := StringName(definition.get("engagement_policy", "unresponsive"))
	if requested_id.is_empty() or requested_map_instance_id.is_empty() \
		or not requested_position is Vector2:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster, map identity and position are required")
	if not requested_position.is_finite() or requested_health <= 0:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster position or health is invalid")
	if simulation_hz <= 0 or current_tick < 0 or requested_respawn_seconds < 0.0 \
		or requested_wander_interval_seconds < 0.0:
		return DomainResult.failure(&"combat.invalid_monster_definition", "monster respawn timing is invalid")
	if not MonsterAggroPolicyScript.is_supported(requested_policy):
		return DomainResult.failure(&"combat.invalid_engagement_policy", "monster engagement policy is invalid")
	monster_id = requested_id
	generator_afflictions.clear()
	entity_id = requested_id
	map_instance_id = requested_map_instance_id
	position = requested_position
	home_position = position
	wander_target = position
	returning_home = false
	clear_movement_route()
	movement_speed = maxf(0.0, float(definition.get("runtime_move_speed", 0.0)))
	species_id = String(definition.get("species_id", ""))
	display_name = String(definition.get("display_name", monster_id))
	combat_actor_id = String(definition.get("combat_actor_id", ""))
	behavior_profile = StringName(definition.get("behavior_profile", "idle"))
	engagement_policy = MonsterAggroPolicyScript.new(requested_policy)
	attack_mode = MonsterAttackModeScript.new(definition, simulation_hz)
	drop_table = DropTableScript.new()
	var drop_result := drop_table.configure(definition.get("drops"))
	if not drop_result.is_ok:
		return drop_result
	defense = maxi(0, int(definition.get("defense", 0)))
	max_health = requested_health
	health = max_health
	aggro_radius = maxf(0.0, float(definition.get("aggro_radius", 0.0)))
	leash_distance = maxf(0.0, float(definition.get("leash_distance", 0.0)))
	wander_radius = maxf(0.0, float(definition.get("wander_radius", 0.0)))
	wander_interval_ticks = roundi(requested_wander_interval_seconds * float(simulation_hz))
	respawn_delay_ticks = roundi(requested_respawn_seconds * float(simulation_hz))
	population_managed = bool(definition.get("population_managed", false))
	population_kind = StringName(definition.get("population_kind", "ordinary"))
	respawn_at_tick = -1
	death_generation = 0
	last_killer_id = ""
	target_actor_id = ""
	_wander_random.seed = (map_instance_id + ":" + monster_id).hash()
	schedule_next_wander(current_tick, true)
	attack_ready_tick = 0
	action = &"idle"
	action_sequence = 0
	facing_direction = 6
	return DomainResult.ok(self)


## 应用权威伤害并按索敌策略记录攻击者。
## [param amount] 本次原始伤害；当前阶段尚未恢复旧服防御公式。
## [param attacker_id] 伤害来源玩家标识。
## [param current_tick] 当前权威逻辑 tick。
## 返回实际伤害、生命、死亡和重生信息。
## [param bypass_defense] 已确认的持续高热直接扣生命，普通炮击仍经过实时防御。
func apply_damage(amount: int, attacker_id: String, current_tick: int, bypass_defense := false) -> DomainResult:
	if health <= 0:
		return DomainResult.failure(&"combat.target_already_dead", "monster is already dead")
	if amount < 0 or attacker_id.is_empty() or current_tick < 0:
		return DomainResult.failure(&"combat.invalid_damage", "damage attribution is invalid")
	var applied := mini(amount if bypass_defense else CombatDefense.mitigate(amount, generator_afflictions.defense_after(defense)), health)
	health -= applied
	var died := health == 0
	if died:
		generator_afflictions.clear()
		death_generation += 1
		last_killer_id = attacker_id
		respawn_at_tick = current_tick + respawn_delay_ticks
		target_actor_id = ""
		clear_movement_route()
	elif engagement_policy.retaliates_when_hit():
		target_actor_id = attacker_id
	return DomainResult.ok({
		"applied_damage": applied,
		"health": health,
		"died": died,
		"death_generation": death_generation,
		"respawn_at_tick": respawn_at_tick,
	})


## 推进生命周期并在到期时恢复出生状态。
## [param current_tick] 当前权威逻辑 tick。
## 返回是否重生及当前生命信息。
func advance_to_tick(current_tick: int) -> DomainResult:
	if current_tick < 0:
		return DomainResult.failure(&"combat.invalid_tick", "tick cannot be negative")
	var respawned := false
	if not population_managed and health == 0 and respawn_at_tick >= 0 and current_tick >= respawn_at_tick:
		health = max_health
		respawn_at_tick = -1
		last_killer_id = ""
		reset_to_home(current_tick)
		respawned = true
	return DomainResult.ok({
		"respawned": respawned,
		"death_generation": death_generation,
		"health": health,
	})


## 将怪物恢复到出生点及空闲 AI 状态。
## [param current_tick] 当前权威逻辑 tick。
func reset_to_home(current_tick: int) -> void:
	generator_afflictions.clear()
	position = home_position
	target_actor_id = ""
	pause_wander(current_tick)


## 开始完整返巢；途中重新进入游荡半径不能恢复旧目标或再次追击。
## [param current_tick] 允许立即规划首段返巢路线的权威时钟。
func begin_return_home(current_tick: int) -> void:
	returning_home = true
	clear_target()
	clear_movement_route()
	wander_target = home_position
	next_wander_tick = current_tick


## 完成返巢或游荡，清除旧路线并开始下一次游荡前的等待。
## [param current_tick] 停留间隔的起始权威时钟。
func pause_wander(current_tick: int) -> void:
	returning_home = false
	action = &"idle"
	wander_target = position
	clear_movement_route()
	schedule_next_wander(current_tick)


## 按个体独立随机序列安排首次启动或后续停顿，不消耗战斗伤害和掉落随机数。
## [param current_tick] 本次等待开始的权威时钟。
## [param initial] 首次启动均匀分布在一个配置周期内，后续周期在基准值上下浮动25%。
## 设计：稳定身份决定序列，出生批次和遍历顺序不会让整批怪物保持同一节拍。
func schedule_next_wander(current_tick: int, initial := false) -> void:
	var minimum_delay := 1 if initial else maxi(1, roundi(wander_interval_ticks * 0.75))
	var maximum_delay := maxi(1, wander_interval_ticks) if initial \
		else maxi(minimum_delay, roundi(wander_interval_ticks * 1.25))
	next_wander_tick = current_tick + _wander_random.randi_range(minimum_delay, maximum_delay)


## 地图时钟跨过休眠时间时，保留本怪物原先剩余的游荡等待。
## [param elapsed_ticks] 地图无人期间跳过的逻辑 tick 数；非正数不产生变化。
func defer_wander_for_suspension(elapsed_ticks: int) -> void:
	next_wander_tick += maxi(0, elapsed_ticks)


## 判断怪物是否允许主动搜索目标。
## 返回主动攻击策略时为 true。
func can_acquire_target() -> bool:
	return engagement_policy.acquires_targets_unprovoked()


## 清除当前仇恨目标。
func clear_target() -> void:
	target_actor_id = ""


## 接受地图权威导航生成的路线，并跳过与当前脚点重合的起始节点。
## [param route] 从当前脚点到最终可达目标的有序世界坐标。
## [param goal] 地图导航确认后的实际终点。
## [param route_kind] wander、chase 或 home，用于识别 AI 状态切换。
## 返回路线是否包含至少一个尚未到达的有效节点。
## 设计：怪物领域对象持有移动进度；静态地图如何生成路线仍属于地图实例职责。
func begin_movement_route(
	route: PackedVector2Array,
	goal: Vector2,
	route_kind: StringName,
) -> bool:
	clear_movement_route()
	if route.is_empty() or not goal.is_finite() or route_kind == &"":
		return false
	movement_route = route.duplicate()
	movement_route_goal = goal
	movement_route_kind = route_kind
	while (
		movement_route_index < movement_route.size()
		and position.distance_to(movement_route[movement_route_index]) <= 0.5
	):
		movement_route_index += 1
	return movement_route_index < movement_route.size()


## 清除当前路线和终点，不改变怪物脚点或游荡计时。
func clear_movement_route() -> void:
	movement_route = PackedVector2Array()
	movement_route_index = 0
	movement_route_goal = Vector2.INF
	movement_route_kind = &""


## 判断当前路线是否仍有未消费的路径节点。
## 返回存在下一路径节点时为 true。
func has_active_movement_route() -> bool:
	return movement_route_index < movement_route.size()


## 读取当前应前往的路径节点。
## 返回下一节点；路线已结束时返回非有限坐标。
func next_movement_waypoint() -> Vector2:
	return movement_route[movement_route_index] \
		if has_active_movement_route() else Vector2.INF


## 消费已经到达的连续路径节点。
## [param arrival_radius] 判定路径节点抵达的世界像素半径。
func advance_movement_route(arrival_radius: float = 0.5) -> void:
	while (
		movement_route_index < movement_route.size()
		and position.distance_to(movement_route[movement_route_index]) <= arrival_radius
	):
		movement_route_index += 1


## 更新八方向朝向。
## [param direction] 指向目标的世界向量。
func face(direction: Vector2) -> void:
	if not direction.is_zero_approx():
		facing_direction = posmod(-roundi(direction.angle() / (PI / 4.0)), 8)


## 判断怪物当前是否存活。
## 返回生命大于零时为 true。
func is_alive() -> bool:
	return health > 0


## 序列化怪物领域状态用于测试和调试。
## 返回不含表现资源句柄的状态字典。
func to_dictionary() -> Dictionary:
	return {
		"monster_id": monster_id,
		"map_instance_id": map_instance_id,
		"species_id": species_id,
		"display_name": display_name,
		"position": position,
		"home_position": home_position,
		"movement_speed": movement_speed,
		"max_health": max_health,
		"health": health,
		"defense": defense,
		"engagement_policy": engagement_policy.policy_id,
		"attack_archetype": attack_mode.archetype,
		"base_attack": attack_mode.base_attack,
		"drops": drop_table.entries(),
		"wander_interval_ticks": wander_interval_ticks,
		"respawn_delay_ticks": respawn_delay_ticks,
		"respawn_at_tick": respawn_at_tick,
		"population_managed": population_managed,
		"death_generation": death_generation,
		"last_killer_id": last_killer_id,
	}
