class_name NpcWorldView
extends "res://scripts/characters/world_character.gd"

enum PatrolState { WAITING, MOVING }

const DEFAULT_MOVEMENT_SPEED := 203.0
const DEFAULT_ANIMATION_SPEED_SCALE := 1.0
const NpcModelScript := preload("res://scripts/domain/npcs/npc_base.gd")

var npc_id := ""
var npc_definition: Dictionary
var npc_model: NpcBase
var navigation: RefCounted
var patrol_state := PatrolState.WAITING
var patrol_index := 0
var path_points := PackedVector2Array()
var path_index := 0
var wait_remaining := 0.0
var interaction_active := false
var random := RandomNumberGenerator.new()


## 配置并初始化 `configure_npc` 对应的模块状态。
## [param character_set] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param definition] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param navigation_service] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func configure_npc(
	character_set: Dictionary,
	definition: Dictionary,
	navigation_service: RefCounted,
) -> void:
	npc_definition = definition
	npc_model = create_npc_model()
	var model_result := npc_model.configure(definition)
	if not model_result.is_ok:
		push_error("NPC domain model failed: %s" % model_result.error_message)
	npc_id = npc_model.entity_id
	navigation = navigation_service
	name = npc_id
	var requested_spawn := _vector_from(definition["spawn"])
	var spawn := requested_spawn
	if not navigation.is_walkable(spawn):
		spawn = navigation.closest_walkable_position(spawn)
	if not spawn.is_finite():
		push_error("NPC %s has no walkable spawn point" % npc_id)
		spawn = requested_spawn
	position = spawn
	npc_model.position = spawn
	var name_offset := _vector_from(definition.get("name_offset", [-64, -88]))
	configure(
		character_set,
		String(definition.get("name", npc_id)),
		Color.WHITE,
		name_offset,
	)
	var patrol: Dictionary = definition.get("patrol", {})
	set_animation_speed_scale(
		float(patrol.get("animation_speed_scale", DEFAULT_ANIMATION_SPEED_SCALE))
	)
	for raw_point in patrol.get("points", []):
		var point: Dictionary = raw_point.duplicate(true)
		var requested := _vector_from(point["position"])
		var resolved := requested
		if not navigation.is_walkable(requested):
			resolved = navigation.closest_reachable_position(spawn, requested)
		point["resolved_position"] = resolved
		var resolved_points := npc_model.patrol_points
		resolved_points.append(point)
		npc_model.patrol_points = resolved_points
	if npc_model.patrol_points.is_empty():
		npc_model.set_patrol_points([{"resolved_position": spawn, "dwell": [2.0, 4.0]}])
	else:
		npc_model.set_patrol_points(npc_model.patrol_points)
	random.randomize()
	random.seed = random.seed ^ hash(npc_id)
	wait_remaining = _random_seconds(patrol.get("initial_delay", [0.4, 2.4]), 1.0)
	set_action("stand", current_direction)


## 按渲染帧推进当前节点的表现状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func _process(delta: float) -> void:
	if interaction_active or npc_model == null or npc_model.patrol_points.size() < 2:
		return
	if patrol_state == PatrolState.WAITING:
		wait_remaining -= delta
		if wait_remaining <= 0.0:
			_start_next_leg()
	else:
		_advance_movement(delta)


## 设置或恢复 `set_interaction_active` 对应的模块状态。
## [param active] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func set_interaction_active(active: bool) -> void:
	interaction_active = active
	if active:
		set_action("stand", current_direction)
	elif patrol_state == PatrolState.MOVING:
		_begin_path_segment()


## 查询并返回 `get_interaction_data` 对应的模块状态。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func get_interaction_data() -> Dictionary:
	return npc_model.interaction_data()


## 执行 `default_actions` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func default_actions() -> Array:
	return npc_model.default_actions()


## 校验并处理 `handle_action` 对应的模块状态。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func handle_action(action_id: String) -> String:
	return npc_model.handle_action(action_id)


## 创建当前世界表现节点对应的 NPC 领域模型。
## 返回基础 NPC 模型；商店和任务表现子类覆盖此工厂方法。
## 设计：场景继承负责选择业务子类，移动渲染仍统一复用本节点。
func create_npc_model() -> NpcBase:
	return NpcModelScript.new()


## 执行 `start_next_leg` 对应的模块操作。
## 设计：该函数遵循所在模块的职责边界。
func _start_next_leg() -> void:
	var target := npc_model.advance_patrol_point()
	path_points = navigation.find_path(position, target)
	if path_points.is_empty():
		patrol_state = PatrolState.WAITING
		wait_remaining = 1.0
		return
	path_index = 1 if path_points.size() > 1 else 0
	patrol_state = PatrolState.MOVING
	_begin_path_segment()


## 推进并更新 `advance_movement` 对应的模块状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该函数遵循所在模块的职责边界。
func _advance_movement(delta: float) -> void:
	if path_index >= path_points.size():
		_arrive_at_patrol_point()
		return
	var waypoint := path_points[path_index]
	var motion := waypoint - position
	var step := npc_model.movement_speed * delta
	if motion.length() <= step:
		position = waypoint
		path_index += 1
		if path_index >= path_points.size():
			_arrive_at_patrol_point()
		else:
			_begin_path_segment()
	else:
		position += motion.normalized() * step
	npc_model.position = position


## 执行 `begin_path_segment` 对应的模块操作。
## 设计：该函数遵循所在模块的职责边界。
func _begin_path_segment() -> void:
	if path_index >= path_points.size():
		return
	var motion := path_points[path_index] - position
	if motion.length_squared() <= 0.01:
		return
	current_direction = posmod(-roundi(motion.angle() / (PI / 4.0)), 8)
	set_action("move", current_direction)


## 执行 `arrive_at_patrol_point` 对应的模块操作。
## 设计：该函数遵循所在模块的职责边界。
func _arrive_at_patrol_point() -> void:
	patrol_state = PatrolState.WAITING
	path_points = PackedVector2Array()
	path_index = 0
	set_action("stand", current_direction)
	npc_model.position = position
	wait_remaining = _random_seconds(npc_model.current_dwell_range(), 2.0)


## 执行 `patrol_position` 对应的模块操作。
## [param index] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func _patrol_position(index: int) -> Vector2:
	return npc_model.patrol_points[index]["resolved_position"]


## 执行 `random_seconds` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param fallback] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func _random_seconds(value: Variant, fallback: float) -> float:
	if value is Array and value.size() >= 2:
		return random.randf_range(float(value[0]), float(value[1]))
	return float(value) if value is float or value is int else fallback


## 执行 `vector_from` 对应的模块操作。
## [param value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该函数遵循所在模块的职责边界。
func _vector_from(value: Variant) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
