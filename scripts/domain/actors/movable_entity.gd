class_name MovableEntity
extends RefCounted

var entity_id: String
var position: Vector2
var movement_speed: float
var facing_direction: int


## 初始化所有可移动生物共享的最小空间状态。
## [param initial_entity_id] 实体稳定标识。
## [param initial_position] 当前世界坐标。
## [param initial_movement_speed] 每秒移动像素数。
## [param initial_facing_direction] 八方向朝向编号。
## 设计：基类只描述“能移动”，不持有背包、战斗或交互等子类职责。
func _init(
	initial_entity_id: String = "",
	initial_position: Vector2 = Vector2.ZERO,
	initial_movement_speed: float = 0.0,
	initial_facing_direction: int = 0,
) -> void:
	entity_id = initial_entity_id
	position = initial_position
	movement_speed = maxf(0.0, initial_movement_speed)
	facing_direction = posmod(initial_facing_direction, 8)


## 按给定时间向目标移动，但不会越过目标点。
## [param target] 本次移动的目标世界坐标。
## [param delta] 本次模拟步长，单位为秒。
## 返回移动后的世界坐标。
func move_towards_target(target: Vector2, delta: float) -> Vector2:
	position = position.move_toward(target, movement_speed * maxf(delta, 0.0))
	return position


## 直接同步由权威边界确认的空间状态。
## [param authoritative_position] 权威世界坐标。
## [param authoritative_facing_direction] 权威八方向朝向编号。
func synchronize_transform(
	authoritative_position: Vector2,
	authoritative_facing_direction: int,
) -> void:
	position = authoritative_position
	facing_direction = posmod(authoritative_facing_direction, 8)
