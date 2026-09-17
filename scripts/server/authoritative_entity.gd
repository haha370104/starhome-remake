class_name AuthoritativeEntity
extends RefCounted

const EntitySnapshotContract := preload("res://scripts/network/contracts/entity_snapshot.gd")

var entity_id := ""
var map_instance_id := ""
var position := Vector2.ZERO
var target_position := Vector2.ZERO
var movement_speed := 203.0
var facing_index := 0
var action := &"idle"
var last_input_sequence := -1
var state_revision := 0
var path := PackedVector2Array()
var path_index := 0


## 设置或恢复 `set_path` 对应的模块状态。
## [param new_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param target] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param input_sequence] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func set_path(new_path: PackedVector2Array, target: Vector2, input_sequence: int) -> void:
	path = new_path
	path_index = 1 if path.size() > 1 else path.size()
	target_position = target
	last_input_sequence = input_sequence
	state_revision += 1
	action = &"walking" if path_index < path.size() else &"idle"
	_update_facing_to_next_point()


## 立即停止当前权威路线；用于推进力归零等服务端状态变化。
func stop_moving() -> void:
	var was_moving := action == &"walking" or path_index < path.size() \
		or not target_position.is_equal_approx(position)
	path = PackedVector2Array([position])
	path_index = path.size()
	target_position = position
	action = &"idle"
	if was_moving:
		state_revision += 1


## 推进并更新 `simulate` 对应的模块状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func simulate(delta: float) -> void:
	if delta <= 0.0 or path_index >= path.size():
		action = &"idle"
		return
	var remaining_distance := movement_speed * delta
	while remaining_distance > 0.0 and path_index < path.size():
		var next_point := path[path_index]
		var distance := position.distance_to(next_point)
		if distance <= 0.001:
			position = next_point
			path_index += 1
			_update_facing_to_next_point()
			continue
		if remaining_distance >= distance:
			position = next_point
			remaining_distance -= distance
			path_index += 1
			_update_facing_to_next_point()
		else:
			position = position.move_toward(next_point, remaining_distance)
			remaining_distance = 0.0
	action = &"walking" if path_index < path.size() else &"idle"
	state_revision += 1


## 执行 `snapshot` 对应的模块操作。
## [param server_tick] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func snapshot(server_tick: int) -> Dictionary:
	var contract = EntitySnapshotContract.new(
		entity_id,
		server_tick,
		position,
		facing_index,
		action,
		movement_speed if action == &"walking" else 0.0,
		state_revision,
		maxi(0, last_input_sequence),
		movement_speed,
	)
	return contract.to_dictionary()


## 推进并更新 `update_facing_to_next_point` 对应的模块状态。
## 设计：该函数位于权威服务器边界，客户端不得覆盖其计算结果。
func _update_facing_to_next_point() -> void:
	if path_index >= path.size():
		return
	var direction := position.direction_to(path[path_index])
	if direction.is_zero_approx():
		return
	# 0 faces east; indices advance clockwise in 45-degree steps.
	var octant := roundi(direction.angle() / (PI / 4.0))
	facing_index = posmod(octant, 8)
