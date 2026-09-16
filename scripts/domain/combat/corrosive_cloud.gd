class_name CorrosiveCloud
extends RefCounted

# 复刻默认：原客户端只有表现，原服伤害周期和寿命未知。
const DURATION_SECONDS := 4.0
const INTERVAL_SECONDS := 1.0
const DAMAGE_RATIO := 0.25
const GROUND_RADIUS := 38.0

var effect_id: String
var attacker_id: String
var combat_actor_id: String
var map_instance_id: String
var attached_actor_id: String
var position: Vector2
var damage_per_tick: int
var expires_tick: int
var next_damage_tick: int
var _interval_ticks: int
var _duration_ticks: int


## 把已验证的弹体结算转换为独立的腐蚀领域对象。
## [param attack] 权威攻击记录，仅服务端可构造。
## [param point] 地面毒雾中心，或附着效果的初始位置。
## [param target_id] 命中战车 ID；空字符串代表地面残留。
## [param tick] 当前权威时钟。
## [param hz] 权威逻辑频率。
func _init(attack: Dictionary, point: Vector2, target_id: String, tick: int, hz: int) -> void:
	effect_id = String(attack.attack_id)
	attacker_id = String(attack.attacker_id)
	combat_actor_id = String(attack.combat_actor_id)
	map_instance_id = String(attack.map_instance_id)
	attached_actor_id = target_id
	position = point
	damage_per_tick = ceili(maxi(0, int(attack.damage)) * DAMAGE_RATIO)
	_interval_ticks = maxi(1, roundi(INTERVAL_SECONDS * hz))
	_duration_ticks = maxi(_interval_ticks, roundi(DURATION_SECONDS * hz))
	expires_tick = tick + _duration_ticks
	next_damage_tick = tick + _interval_ticks


## 判断同一攻击者的新腐蚀是否应该刷新现有残留，避免无限叠层。
## [param other] 刚落地或附着的新腐蚀对象。
## 返回同源且附着同一战车，或同源地面范围重叠时为 true。
func can_refresh(other: CorrosiveCloud) -> bool:
	return attacker_id == other.attacker_id and map_instance_id == other.map_instance_id \
		and attached_actor_id == other.attached_actor_id \
		and (not attached_actor_id.is_empty() or position.distance_to(other.position) <= GROUND_RADIUS)


## 延长同源腐蚀寿命，但不推迟下一次扣血，也不累计额外伤害层。
## [param tick] 最新一次命中的权威时钟。
func refresh(tick: int) -> void:
	expires_tick = tick + _duration_ticks


## 消费到期的伤害脉冲；同一 tick 重复调用不会重复扣血。
## [param tick] 按固定步长推进的权威时钟。
## 返回本 tick 是否应该结算一次伤害。
func consume_pulse(tick: int) -> bool:
	if tick < next_damage_tick or tick > expires_tick:
		return false
	next_damage_tick = tick + _interval_ticks
	return true


## 判断战车是否受到本团毒雾影响。
## [param actor_id] 待检测战车。
## [param actor_map] 战车当前地图实例。
## [param actor_center] 战车实际碰撞中心。
## 返回同地图附着目标或站在地面毒雾内时为 true。
func affects(actor_id: String, actor_map: String, actor_center: Vector2) -> bool:
	if actor_map != map_instance_id:
		return false
	if not attached_actor_id.is_empty():
		return actor_id == attached_actor_id
	return position.distance_to(actor_center) <= GROUND_RADIUS


## 判断最后一次脉冲是否已经消费，可以移除残留。
## [param tick] 当前权威时钟。
## 返回寿命结束且没有未结算末次脉冲时为 true。
func is_expired(tick: int) -> bool:
	return tick > expires_tick or (tick == expires_tick and next_damage_tick > expires_tick)


## 导出不包含伤害规则的只读表现快照。
## [param world_position] 服务端解析的最新地面或战车位置。
## 返回网络边界 DTO；客户端只负责绘制。
func snapshot(world_position: Vector2) -> Dictionary:
	return {"effect_id": effect_id, "attached_actor_id": attached_actor_id,
		"position": [world_position.x, world_position.y], "expires_tick": expires_tick}
