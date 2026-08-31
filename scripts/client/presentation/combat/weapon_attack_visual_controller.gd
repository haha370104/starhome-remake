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
var _muzzle_frames: SpriteFrames
var _cooldown_remaining := 0.0
var _projectiles: Array[Dictionary] = []
var _impacts: Array[Dictionary] = []
var _muzzles: Array[Dictionary] = []
var _visual_collision_resolver := Callable()
var _visual_shot_sequence := 0


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
	_muzzle_frames = null
	_visual_collision_resolver = Callable()
	_cooldown_remaining = 0.0
	_visual_shot_sequence = 0
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
	var muzzle_value: Variant = candidate.get("muzzle", {})
	if muzzle_value is Dictionary and not (muzzle_value as Dictionary).is_empty():
		_muzzle_frames = _load_frames(String((muzzle_value as Dictionary)["resource"]))
		if _muzzle_frames == null:
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
## [param tracking_target_resolver] 可选的导弹目标实时坐标解析器。
## 返回该函数计算、查询或操作得到的结果。
## 设计：超出武器表现射程的点击会被钳制到射程边缘；伤害与命中仍必须由服务端裁决。
func request_fire(
	origin: Vector2,
	requested_target: Vector2,
	tracking_target_resolver: Callable = Callable(),
) -> Dictionary:
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
	var minimum_range := float(_weapon.get("minimum_visual_range", 0.0))
	if aim.length() < minimum_range:
		return {"ok": false, "code": &"target_too_close"}
	var maximum_range := float(_weapon["maximum_visual_range"])
	var resolved_distance := minf(aim.length(), maximum_range)
	var resolved_target := origin + direction * resolved_distance
	var muzzle_values: Array = _weapon["muzzle_offset"]
	var muzzle_offset := Vector2(float(muzzle_values[0]), float(muzzle_values[1]))
	var forward_offset := minf(MUZZLE_FORWARD_OFFSET, resolved_distance * 0.5)
	var muzzle_position := origin + muzzle_offset + direction * forward_offset
	_visual_shot_sequence += 1
	var visual_shot_id := "%s.visual.%d.%d.%d" % [
		String(_weapon_id),
		OS.get_process_id(),
		Time.get_ticks_usec(),
		_visual_shot_sequence,
	]
	_spawn_muzzle(muzzle_position)
	_spawn_projectile(
		muzzle_position,
		resolved_target,
		tracking_target_resolver,
		visual_shot_id,
	)
	_cooldown_remaining = float(_weapon["cooldown_seconds"])
	CombatTraceLogger.record(&"client", &"visual_projectile_spawned", {
		"visual_shot_id": visual_shot_id,
		"weapon_id": String(_weapon_id),
		"actor_view_position": origin,
		"requested_target": requested_target,
		"resolved_target": resolved_target,
		"muzzle_position": muzzle_position,
		"direction": direction,
		"maximum_visual_range": maximum_range,
		"range_clamped": aim.length() > maximum_range,
		"projectile_speed": float((_weapon["projectile"] as Dictionary)["travel_pixels_per_second"]),
	})
	return {
		"ok": true,
		"visual_shot_id": visual_shot_id,
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
	_advance_timed_effects(_muzzles, delta_seconds)


## 清除当前地图的全部瞬态弹体与命中特效，并重置冷却。
func clear_effects() -> void:
	for state in _projectiles:
		_free_state_node(state)
	for state in _impacts:
		_free_state_node(state)
	for state in _muzzles:
		_free_state_node(state)
	_projectiles.clear()
	_impacts.clear()
	_muzzles.clear()
	_cooldown_remaining = 0.0


## 执行 `active_projectile_count` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func active_projectile_count() -> int:
	return _projectiles.size()


## 执行 `active_impact_count` 对应的模块操作。
## 返回该函数计算、查询或操作得到的结果。
func active_impact_count() -> int:
	return _impacts.size()


## 查询当前仍在播放的炮口特效数量。
## 返回活动炮口特效的数量。
func active_muzzle_count() -> int:
	return _muzzles.size()


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
		or float(weapon.get("minimum_visual_range", 0.0)) < 0.0
		or float(weapon.get("minimum_visual_range", 0.0)) >= float(weapon.get("maximum_visual_range", 0.0))
		or float(weapon.get("cooldown_seconds", 0.0)) <= 0.0
		or not muzzle_value is Array
		or (muzzle_value as Array).size() != 2
	):
		return false
	return (
		_is_valid_effect(weapon.get("projectile", {}), true)
		and _is_valid_effect(weapon.get("impact", {}), false)
		and _is_valid_optional_effect(weapon.get("muzzle", {}))
	)


## 校验允许为空的可选武器特效配置。
## [param effect_value] 待校验的特效配置值。
## 返回配置为空或满足标准特效契约时为真。
func _is_valid_optional_effect(effect_value: Variant) -> bool:
	return (
		effect_value is Dictionary
		and ((effect_value as Dictionary).is_empty() or _is_valid_effect(effect_value, false))
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
## [param tracking_target_resolver] 导弹飞行期间用于刷新目标坐标的解析器。
## [param visual_shot_id] 客户端本地视觉弹体的诊断关联标识。
func _spawn_projectile(
	origin: Vector2,
	target: Vector2,
	tracking_target_resolver: Callable,
	visual_shot_id: String,
) -> void:
	var wrapper := _create_effect_node("WeaponProjectile", origin, _projectile_frames)
	var projectile: Dictionary = _weapon["projectile"]
	var duration := origin.distance_to(target) / float(projectile["travel_pixels_per_second"])
	wrapper.rotation = (target - origin).angle()
	_projectiles.append({
		"visual_shot_id": visual_shot_id,
		"node": wrapper,
		"origin": origin,
		"position": origin,
		"target": target,
		"elapsed": 0.0,
		"duration": maxf(duration, 0.001),
		"maximum_lifetime": maxf(duration * 4.0, 2.0),
		"motion_mode": StringName(projectile.get("motion_mode", "linear")),
		"tracking_target_resolver": tracking_target_resolver,
	})


## 在指定世界坐标创建一次可选炮口动画。
## [param position] 炮口特效的世界坐标。
func _spawn_muzzle(position: Vector2) -> void:
	if _muzzle_frames == null:
		return
	var muzzle: Dictionary = _weapon["muzzle"]
	var wrapper := _create_effect_node("WeaponMuzzle", position, _muzzle_frames)
	_muzzles.append({
		"node": wrapper,
		"elapsed": 0.0,
		"duration": float(muzzle["frames"]) / float(muzzle["fps"]),
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
	sprite.play(RAW_ANIMATION)
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
		if StringName(state.get("motion_mode", &"linear")) == &"homing":
			_advance_homing_projectile(index, state, delta_seconds)
			continue
		var previous_progress := minf(float(state["elapsed"]) / float(state["duration"]), 1.0)
		var previous_position := Vector2(state["origin"]).lerp(Vector2(state["target"]), previous_progress)
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		var progress := minf(float(state["elapsed"]) / float(state["duration"]), 1.0)
		var next_position := Vector2(state["origin"]).lerp(Vector2(state["target"]), progress)
		var collision := _resolve_visual_collision(previous_position, next_position)
		if bool(collision.get("hit", false)):
			CombatTraceLogger.record(&"client", &"visual_projectile_collision", {
				"visual_shot_id": String(state.get("visual_shot_id", "")),
				"weapon_id": String(_weapon_id),
				"segment_start": previous_position,
				"segment_end": next_position,
				"visual_collision": collision,
				"elapsed_seconds": float(state["elapsed"]),
			})
			_free_state_node(state)
			_spawn_impact(Vector2(collision.get("position", next_position)))
			_projectiles.remove_at(index)
			continue
		var wrapper := state["node"] as Node2D
		if wrapper != null and is_instance_valid(wrapper):
			wrapper.position = next_position
			wrapper.rotation = (next_position - previous_position).angle()
		if progress < 1.0:
			continue
		CombatTraceLogger.record(&"client", &"visual_projectile_range_end", {
			"visual_shot_id": String(state.get("visual_shot_id", "")),
			"weapon_id": String(_weapon_id),
			"impact_position": Vector2(state["target"]),
			"elapsed_seconds": float(state["elapsed"]),
		})
		_free_state_node(state)
		_spawn_impact(Vector2(state["target"]))
		_projectiles.remove_at(index)


## 推进一枚追踪弹体，并在抵达或超时后生成命中特效。
## [param index] 弹体在活动数组中的索引。
## [param state] 该弹体的可变表现状态。
## [param delta_seconds] 本帧经过的秒数。
func _advance_homing_projectile(index: int, state: Dictionary, delta_seconds: float) -> void:
	state["elapsed"] = float(state["elapsed"]) + delta_seconds
	var resolver: Callable = state["tracking_target_resolver"]
	if resolver.is_valid():
		var resolved: Variant = resolver.call()
		if resolved is Vector2 and (resolved as Vector2).is_finite():
			state["target"] = resolved
	var previous_position: Vector2 = state["position"]
	var target: Vector2 = state["target"]
	var delta := target - previous_position
	var speed := float((_weapon["projectile"] as Dictionary)["travel_pixels_per_second"])
	var next_position := previous_position + delta.limit_length(speed * delta_seconds)
	state["position"] = next_position
	var wrapper := state["node"] as Node2D
	if wrapper != null and is_instance_valid(wrapper):
		wrapper.position = next_position
		if not delta.is_zero_approx():
			wrapper.rotation = delta.angle()
	if next_position.distance_to(target) > 1.0 \
			and float(state["elapsed"]) < float(state["maximum_lifetime"]):
		return
	CombatTraceLogger.record(&"client", &"visual_homing_projectile_end", {
		"visual_shot_id": String(state.get("visual_shot_id", "")),
		"weapon_id": String(_weapon_id),
		"impact_position": target,
		"elapsed_seconds": float(state["elapsed"]),
		"maximum_lifetime_seconds": float(state["maximum_lifetime"]),
	})
	_free_state_node(state)
	_spawn_impact(target)
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


## 推进一组按持续时间自动销毁的瞬态特效。
## [param states] 待推进的特效状态数组。
## [param delta_seconds] 本帧经过的秒数。
func _advance_timed_effects(states: Array[Dictionary], delta_seconds: float) -> void:
	for index in range(states.size() - 1, -1, -1):
		var state: Dictionary = states[index]
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		if float(state["elapsed"]) < float(state["duration"]):
			continue
		_free_state_node(state)
		states.remove_at(index)


## 执行 `free_state_node` 对应的模块操作。
## [param state] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _free_state_node(state: Dictionary) -> void:
	var node := state.get("node") as Node
	if node != null and is_instance_valid(node):
		node.free()
