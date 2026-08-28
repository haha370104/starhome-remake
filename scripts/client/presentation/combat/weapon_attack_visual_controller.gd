class_name WeaponAttackVisualController
extends Node

const RAW_ANIMATION := &"raw"
const MINIMUM_SHOT_DISTANCE := 2.0
const MUZZLE_FORWARD_OFFSET := 28.0

var _world_parent: Node2D
var _weapon_id: StringName = &""
var _weapon: Dictionary = {}
var _projectile_frames: SpriteFrames
var _impact_frames: SpriteFrames
var _cooldown_remaining := 0.0
var _projectiles: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _visual_collision_resolver := Callable()


## 执行 `configure` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param world_parent] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param weapon_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：控制器只消费业务化武器关系；旧客户端文件名与映射推断仅保留在 source audit。
func configure(
	manifest: Dictionary,
	world_parent: Node2D,
	weapon_id: StringName,
) -> Error:
	clear_effects()
	_world_parent = world_parent
	_weapon_id = weapon_id
	_weapon.clear()
	_projectile_frames = null
	_impact_frames = null
	_visual_collision_resolver = Callable()
	_cooldown_remaining = 0.0
	if _world_parent == null or _weapon_id == &"":
		return ERR_INVALID_PARAMETER
	var weapons_value: Variant = manifest.get("weapons", {})
	if not weapons_value is Dictionary:
		return ERR_INVALID_DATA
	var weapon_value: Variant = (weapons_value as Dictionary).get(String(_weapon_id), {})
	if not weapon_value is Dictionary or (weapon_value as Dictionary).is_empty():
		return ERR_DOES_NOT_EXIST
	var candidate: Dictionary = (weapon_value as Dictionary).duplicate(true)
	if not _is_valid_weapon(candidate):
		return ERR_INVALID_DATA
	var projectile: Dictionary = candidate["projectile"]
	var impact: Dictionary = candidate["impact"]
	_projectile_frames = _load_frames(String(projectile["resource"]))
	_impact_frames = _load_frames(String(impact["resource"]))
	if _projectile_frames == null or _impact_frames == null:
		return ERR_CANT_OPEN
	_weapon = candidate
	return OK


## 执行 `set_visual_collision_resolver` 对应的模块操作。
## [param resolver] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_visual_collision_resolver(resolver: Callable) -> void:
	_visual_collision_resolver = resolver


## 执行 `request_fire` 对应的模块操作。
## [param origin] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requested_target] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：超出武器表现射程的点击会被钳制到射程边缘；伤害与命中仍必须由服务端裁决。
func request_fire(origin: Vector2, requested_target: Vector2) -> Dictionary:
	if _weapon.is_empty() or _world_parent == null:
		return {"ok": false, "code": &"unconfigured"}
	if _cooldown_remaining > 0.0:
		return {
			"ok": false,
			"code": &"cooldown",
			"remaining_seconds": _cooldown_remaining,
		}
	var aim := requested_target - origin
	if not aim.is_finite() or aim.length() < MINIMUM_SHOT_DISTANCE:
		return {"ok": false, "code": &"target_too_close"}
	var direction := aim.normalized()
	var maximum_range := float(_weapon["maximum_visual_range"])
	var resolved_distance := minf(aim.length(), maximum_range)
	var resolved_target := origin + direction * resolved_distance
	var muzzle_values: Array = _weapon["muzzle_offset"]
	var muzzle_offset := Vector2(float(muzzle_values[0]), float(muzzle_values[1]))
	var forward_offset := minf(MUZZLE_FORWARD_OFFSET, resolved_distance * 0.5)
	var muzzle_position := origin + muzzle_offset + direction * forward_offset
	_spawn_projectile(muzzle_position, resolved_target)
	_cooldown_remaining = float(_weapon["cooldown_seconds"])
	return {
		"ok": true,
		"resolved_target": resolved_target,
		"direction": direction,
		"range_clamped": aim.length() > maximum_range,
	}


## 执行 `advance` 对应的模块操作。
## [param delta_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：该显式入口使测试无需依赖真实帧时钟；节点 `_process` 只负责转发。
func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta_seconds)
	if _cooldown_remaining < 0.00001:
		_cooldown_remaining = 0.0
	_advance_projectiles(delta_seconds)
	_advance_impacts(delta_seconds)


## 清除当前地图的全部瞬态弹体与命中特效，并重置冷却。
func clear_effects() -> void:
	for state in _projectiles:
		_free_state_node(state)
	for state in _impacts:
		_free_state_node(state)
	_projectiles.clear()
	_impacts.clear()
	_cooldown_remaining = 0.0


## 执行 `active_projectile_count` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func active_projectile_count() -> int:
	return _projectiles.size()


## 执行 `active_impact_count` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func active_impact_count() -> int:
	return _impacts.size()


## 执行 `cooldown_remaining` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该冷却只抑制重复动画；服务端冷却仍是唯一玩法权威。
func cooldown_remaining() -> float:
	return _cooldown_remaining


## 按渲染帧推进当前节点的表现状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	advance(delta)


## 执行 `is_valid_weapon` 对应的模块操作。
## [param weapon] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _is_valid_weapon(weapon: Dictionary) -> bool:
	var muzzle_value: Variant = weapon.get("muzzle_offset", [])
	if (
		float(weapon.get("maximum_visual_range", 0.0)) <= 0.0
		or float(weapon.get("cooldown_seconds", 0.0)) <= 0.0
		or not muzzle_value is Array
		or (muzzle_value as Array).size() != 2
	):
		return false
	return (
		_is_valid_effect(weapon.get("projectile", {}), true)
		and _is_valid_effect(weapon.get("impact", {}), false)
	)


## 执行 `is_valid_effect` 对应的模块操作。
## [param effect_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param requires_speed] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _is_valid_effect(effect_value: Variant, requires_speed: bool) -> bool:
	if not effect_value is Dictionary:
		return false
	var effect: Dictionary = effect_value
	if (
		String(effect.get("resource", "")).is_empty()
		or int(effect.get("frames", 0)) <= 0
		or float(effect.get("fps", 0.0)) <= 0.0
	):
		return false
	return not requires_speed or float(effect.get("travel_pixels_per_second", 0.0)) > 0.0


## 执行 `load_frames` 对应的模块操作。
## [param resource_path] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _load_frames(resource_path: String) -> SpriteFrames:
	var frames := ResourceLoader.load(resource_path, "SpriteFrames") as SpriteFrames
	return frames if frames != null and frames.has_animation(RAW_ANIMATION) else null


## 执行 `spawn_projectile` 对应的模块操作。
## [param origin] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param target] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _spawn_projectile(origin: Vector2, target: Vector2) -> void:
	var wrapper := _create_effect_node("WeaponProjectile", origin, _projectile_frames)
	var projectile: Dictionary = _weapon["projectile"]
	var duration := origin.distance_to(target) / float(projectile["travel_pixels_per_second"])
	_projectiles.append({
		"node": wrapper,
		"origin": origin,
		"target": target,
		"elapsed": 0.0,
		"duration": maxf(duration, 0.001),
	})


## 执行 `spawn_impact` 对应的模块操作。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _spawn_impact(position: Vector2) -> void:
	var wrapper := _create_effect_node("WeaponImpact", position, _impact_frames)
	_impacts.append({"node": wrapper, "elapsed": 0.0})


## 执行 `create_effect_node` 对应的模块操作。
## [param name_value] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param frames] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _create_effect_node(name_value: String, position: Vector2, frames: SpriteFrames) -> Node2D:
	var wrapper := Node2D.new()
	wrapper.name = name_value
	wrapper.position = position
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.animation = RAW_ANIMATION
	sprite.frame = 0
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	return wrapper


## 执行 `advance_projectiles` 对应的模块操作。
## [param delta_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 设计：使用上一位置到下一位置的连续线段查询，避免高速弹体单帧穿过小型怪物。
func _advance_projectiles(delta_seconds: float) -> void:
	for index in range(_projectiles.size() - 1, -1, -1):
		var state: Dictionary = _projectiles[index]
		var previous_progress := minf(float(state["elapsed"]) / float(state["duration"]), 1.0)
		var previous_position := Vector2(state["origin"]).lerp(Vector2(state["target"]), previous_progress)
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		var progress := minf(float(state["elapsed"]) / float(state["duration"]), 1.0)
		var next_position := Vector2(state["origin"]).lerp(Vector2(state["target"]), progress)
		var collision := _resolve_visual_collision(previous_position, next_position)
		if bool(collision.get("hit", false)):
			_free_state_node(state)
			_spawn_impact(Vector2(collision.get("position", next_position)))
			_projectiles.remove_at(index)
			continue
		var wrapper := state["node"] as Node2D
		if wrapper != null and is_instance_valid(wrapper):
			wrapper.position = next_position
		if progress < 1.0:
			continue
		_free_state_node(state)
		_spawn_impact(Vector2(state["target"]))
		_projectiles.remove_at(index)


## 执行 `resolve_visual_collision` 对应的模块操作。
## [param segment_start] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param segment_end] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _resolve_visual_collision(segment_start: Vector2, segment_end: Vector2) -> Dictionary:
	if not _visual_collision_resolver.is_valid():
		return {"hit": false}
	var result: Variant = _visual_collision_resolver.call(segment_start, segment_end)
	return result if result is Dictionary else {"hit": false}


## 执行 `advance_impacts` 对应的模块操作。
## [param delta_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _advance_impacts(delta_seconds: float) -> void:
	var impact: Dictionary = _weapon.get("impact", {})
	var frame_count := int(impact.get("frames", 0))
	var fps := float(impact.get("fps", 0.0))
	for index in range(_impacts.size() - 1, -1, -1):
		var state: Dictionary = _impacts[index]
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		var frame := int(floor(float(state["elapsed"]) * fps))
		if frame >= frame_count:
			_free_state_node(state)
			_impacts.remove_at(index)
			continue
		var wrapper := state["node"] as Node2D
		if wrapper != null and is_instance_valid(wrapper):
			var sprite := wrapper.get_node_or_null("Sprite") as AnimatedSprite2D
			if sprite != null:
				sprite.frame = frame


## 执行 `free_state_node` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _free_state_node(state: Dictionary) -> void:
	var node := state.get("node") as Node
	if node != null and is_instance_valid(node):
		node.free()
