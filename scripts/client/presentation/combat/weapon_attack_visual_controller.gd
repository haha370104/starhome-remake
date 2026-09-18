class_name WeaponAttackVisualController
extends Node

const RAW_ANIMATION := &"raw"
const MINIMUM_SHOT_DISTANCE := 2.0
const MUZZLE_FORWARD_OFFSET := 28.0

var _manifest: Dictionary = {}
var _visual_definition_id: StringName = &""
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
var _last_authoritative_event_id := 0
var _confirmed_shots: Dictionary = {}


## 向增强输入公开当前武器射程，避免读取内部武器字典。
## 返回当前最大可视射程，未配置为零。
func assisted_attack_range() -> float:
	return float(_weapon.get("maximum_visual_range", 0.0))


## 自动攻击沿用手动开火的距离和冷却门槛，最终许可仍由服务器决定。
## [param origin] 当前玩家位置。
## [param target] 所选怪物位置。
## 返回本地是否可以尝试开火。
func can_assist_fire(origin: Vector2, target: Vector2) -> bool:
	var distance := origin.distance_to(target)
	return not _weapon.is_empty() and _cooldown_remaining <= 0.0 and target.is_finite() \
		and distance >= maxf(MINIMUM_SHOT_DISTANCE, float(_weapon.get("minimum_visual_range", 0.0))) \
		and distance <= assisted_attack_range()


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
	_manifest = CombatAnimationLibrary.with_weapon_bindings(manifest)
	_visual_definition_id = &""
	_weapon.clear()
	_visual_collision_resolver = Callable()
	_cooldown_remaining = 0.0
	_visual_shot_sequence = 0
	if _world_parent == null:
		return ERR_INVALID_PARAMETER
	return select_weapon(weapon_id)


## 根据实际装备切换后续发射的外观；在途弹体、确认去重和独立冷却保持原状态。
## [param weapon_id] 本地表现目录中的装备标识；空标识表示卸下武器。
## 返回是否找到该装备的完整弹体和爆炸素材。
func select_weapon(weapon_id: StringName) -> Error:
	if weapon_id == _visual_definition_id and not _weapon.is_empty():
		return OK
	_weapon.clear()
	_weapon_id = weapon_id
	_visual_definition_id = weapon_id
	_projectile_frames = null
	_impact_frames = null
	_muzzle_frames = null
	if weapon_id == &"":
		return OK
	var candidate: Dictionary = _manifest.get("weapons", {}).get(String(weapon_id), {}).duplicate(true)
	if not _is_valid_weapon(candidate):
		return ERR_INVALID_DATA
	_projectile_frames = _load_effect_frames(candidate["projectile"])
	_impact_frames = _load_effect_frames(candidate["impact"])
	if _projectile_frames == null or _impact_frames == null:
		return ERR_CANT_OPEN
	var muzzle: Dictionary = candidate.get("muzzle", {})
	if not muzzle.is_empty():
		_muzzle_frames = _load_effect_frames(muzzle)
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
## [param preview_only] 仅校验并解析瞄准，不创建弹体；输入侧等待服务器确认后再播放。
## 返回该函数计算、查询或操作得到的结果。
## 设计：超出武器表现射程的点击会被钳制到射程边缘；伤害与命中仍必须由服务端裁决。
func request_fire(
	origin: Vector2,
	requested_target: Vector2,
	tracking_target_resolver: Callable = Callable(),
	preview_only: bool = false,
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
	if preview_only:
		_cooldown_remaining = float(_weapon["cooldown_seconds"])
		return {"ok": true, "resolved_target": resolved_target, "direction": direction,
			"range_clamped": aim.length() > maximum_range}
	var muzzle_values: Array = _weapon["muzzle_offset"]
	var muzzle_offset := Vector2(float(muzzle_values[0]), float(muzzle_values[1]))
	var forward_offset := minf(float(_weapon.get("muzzle_forward_offset", MUZZLE_FORWARD_OFFSET)), resolved_distance * 0.5)
	var muzzle_position := origin + muzzle_offset + direction * forward_offset
	var visual_shot_id := _spawn_visual_shot(muzzle_position, resolved_target, tracking_target_resolver)
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


## 将本地预测弹体绑定到真正发送的能力意图序号，供权威结果对账。
## [param visual_shot_id] request_fire 返回的本地唯一标识。
## [param input_sequence] 已发送意图的序号；无效序号不绑定。
func bind_input_sequence(visual_shot_id: String, input_sequence: int) -> void:
	if input_sequence < 0:
		return
	for state: Dictionary in _projectiles:
		if String(state["visual_shot_id"]) == visual_shot_id:
			state["input_sequence"] = input_sequence
			return


## 仅为服务器已扣能并接受的开火创建一次弹体，快照重发不重复播放。
## [param event] 含发射者坐标、瞄准终点及 shot_id 的已确认开火事件。
## [param tracking_target_resolver] 导弹目标位置查询器。
## [param actor_view_position] 当前可见车身在特效父节点坐标系下的脚点；缺省保留权威发射位置。
## 返回本次是否产生新的已确认表现。
## 设计：只把权威炮口相对车身的偏移投影到当前车身，终点及权威命中仍保持原值。
func present_confirmed_shot(
	event: Dictionary,
	tracking_target_resolver: Callable = Callable(),
	actor_view_position := Vector2.INF,
) -> bool:
	var shot_id := String(event.get("shot_id", ""))
	var actor_point: Variant = event.get("actor_position", [])
	var endpoint: Variant = event.get("endpoint", [])
	if shot_id.is_empty() or _confirmed_shots.has(shot_id) \
			or not actor_point is Array or actor_point.size() != 2 \
			or not endpoint is Array or endpoint.size() != 2:
		return false
	var actor_position := Vector2(actor_point[0], actor_point[1])
	var target := Vector2(endpoint[0], endpoint[1])
	if not actor_position.is_finite() or not target.is_finite() or _world_parent == null:
		return false
	var confirmed_weapon := StringName(event.get("weapon_id", _weapon_id))
	if select_weapon(confirmed_weapon) != OK:
		return false
	if event.get("weapon_flight") is Dictionary:
		_apply_flight_parameters(event["weapon_flight"])
	var aim := target - actor_position
	var offset: Array = _weapon["muzzle_offset"]
	var forward := minf(float(_weapon.get("muzzle_forward_offset", MUZZLE_FORWARD_OFFSET)), aim.length() * 0.5)
	var authoritative_muzzle := actor_position + Vector2(offset[0], offset[1]) + aim.normalized() * forward
	if event.has("origin"):
		var origin: Variant = event["origin"]
		if not origin is Array or origin.size() != 2:
			return false
		authoritative_muzzle = Vector2(origin[0], origin[1])
	if not authoritative_muzzle.is_finite():
		return false
	var visible_actor := actor_view_position if actor_view_position.is_finite() else actor_position
	var visible_muzzle := visible_actor + authoritative_muzzle - actor_position
	# 已接受的开火不能再次按移动后的距离校验或钳制，否则会吞弹或偏移权威终点。
	var visual_shot_id := _spawn_visual_shot(visible_muzzle, target, tracking_target_resolver)
	_cooldown_remaining = float(_weapon["cooldown_seconds"])
	_confirmed_shots[shot_id] = true
	if _confirmed_shots.size() > 128:
		_confirmed_shots.erase(_confirmed_shots.keys()[0])
	bind_input_sequence(visual_shot_id, int(event.get("input_sequence", -1)))
	for state: Dictionary in _projectiles:
		if String(state.visual_shot_id) == visual_shot_id: state["piercing"] = bool(event.get("piercing", false))
	CombatTraceLogger.record(&"client", &"visual_projectile_spawned", {
		"visual_shot_id": visual_shot_id, "shot_id": shot_id, "weapon_id": String(_weapon_id),
		"actor_view_position": visible_actor, "actor_authoritative_position": actor_position,
		"muzzle_position": visible_muzzle, "authoritative_muzzle_position": authoritative_muzzle,
		"resolved_target": target, "projectile_speed": float(_weapon.projectile.travel_pixels_per_second),
	})
	return true


## 在同一世界坐标系创建炮口与弹体，不重做已经完成的攻击规则校验。
## [param muzzle_position] 本次表现实际使用的炮口位置。
## [param target] 确认后的弹道终点。
## [param tracking_target_resolver] 导弹使用的动态目标解析器。
## 返回本地唯一弹体编号，供诊断与意图对账。
func _spawn_visual_shot(muzzle_position: Vector2, target: Vector2, tracking_target_resolver: Callable) -> String:
	_visual_shot_sequence += 1
	var visual_shot_id := "%s.visual.%d.%d.%d" % [
		String(_weapon_id), OS.get_process_id(), Time.get_ticks_usec(), _visual_shot_sequence,
	]
	_spawn_muzzle(muzzle_position)
	_spawn_projectile(muzzle_position, target, tracking_target_resolver, visual_shot_id)
	return visual_shot_id


## 接收本玩家的权威弹道参数和最终结果，同步后续发射并终结尚在飞行的对应弹体。
## [param snapshot] 已通过会话边界的战斗快照；不允许服务端指定表现资源路径。
## [param ability_id] 此控制器对应的能力槽位。
## 设计：当前在途弹体保留发射时参数；只有匹配本玩家和意图序号的最终事件能结束它，不改生命值。
func apply_authoritative_snapshot(snapshot: Dictionary, ability_id: String) -> void:
	var flights: Variant = snapshot.get("local_weapon_flight", {})
	if flights is Dictionary and flights.get(ability_id) is Dictionary:
		var flight: Dictionary = flights[ability_id]
		if select_weapon(StringName(flight.get("weapon_id", ""))) == OK:
			_apply_flight_parameters(flight)
	var local_id := String(snapshot.get("local_entity_id", ""))
	if local_id.is_empty():
		return
	for raw_event: Variant in snapshot.get("recent_events", []):
		if not raw_event is Dictionary:
			continue
		var event: Dictionary = raw_event
		var event_id := int(event.get("event_id", 0))
		if event_id <= _last_authoritative_event_id:
			continue
		_last_authoritative_event_id = event_id
		if String(event.get("attacker_id", "")) != local_id:
			continue
		var event_type := String(event.get("event_type", ""))
		if event_type.ends_with("_hit") or event_type.ends_with("_projectile_expired"):
			_finish_authoritative_projectile(event)


## 校验并原子应用权威弹道参数；保持本地受控的动画资源选择不变。
## [param flight] 包含武器标识、射程、速度、冷却与炮口偏移的协议数据。
func _apply_flight_parameters(flight: Dictionary) -> void:
	if _weapon.is_empty():
		return
	var reach := float(flight.get("range", 0.0))
	var minimum := float(flight.get("minimum_range", 0.0))
	var speed := float(flight.get("projectile_speed", 0.0))
	var cooldown := float(flight.get("cooldown_seconds", 0.0))
	var forward := float(flight.get("muzzle_forward_offset", -1.0))
	var offset: Variant = flight.get("muzzle_offset", [])
	var weapon_id := StringName(flight.get("weapon_id", ""))
	if weapon_id == &"" or not is_finite(reach) or not is_finite(minimum) \
			or not is_finite(speed) or not is_finite(cooldown) or not is_finite(forward) \
			or reach <= 0.0 or minimum < 0.0 or minimum >= reach or speed <= 0.0 \
			or cooldown <= 0.0 or forward < 0.0 or not offset is Array or offset.size() != 2:
		return
	if not Vector2(float(offset[0]), float(offset[1])).is_finite():
		return
	_weapon_id = weapon_id
	_weapon["maximum_visual_range"] = reach
	_weapon["minimum_visual_range"] = minimum
	_weapon["cooldown_seconds"] = cooldown
	_weapon["muzzle_offset"] = offset.duplicate()
	_weapon["muzzle_forward_offset"] = forward
	_weapon["projectile"]["travel_pixels_per_second"] = speed


## 让尚未发生预测爆炸的同一发炮弹，在收到权威命中或失效时结束，避免穿过已死亡目标继续飞。
## [param event] 包含本玩家意图序号、最终交点的权威事件。
func _finish_authoritative_projectile(event: Dictionary) -> void:
	var sequence := int(event.get("input_sequence", -1))
	var point: Variant = event.get("impact_position", [])
	if sequence < 0 or not point is Array or point.size() != 2:
		return
	var impact := Vector2(float(point[0]), float(point[1]))
	if not impact.is_finite():
		return
	for index in range(_projectiles.size() - 1, -1, -1):
		var state: Dictionary = _projectiles[index]
		if int(state["input_sequence"]) != sequence:
			continue
		var wrapper := state["node"] as Node2D
		CombatTraceLogger.record(&"client", &"visual_projectile_authoritative_finish", {
			"visual_shot_id": state["visual_shot_id"], "input_sequence": sequence,
			"shot_id": event.get("shot_id", ""), "weapon_id": state["weapon_id"],
			"visual_position": wrapper.position, "impact_position": impact,
			"correction_distance": wrapper.position.distance_to(impact),
			"elapsed_seconds": state["elapsed"], "event_type": event["event_type"],
		})
		if bool(event.get("projectile_continues", false)):
			_spawn_impact(impact, state)
			return
		_free_state_node(state)
		_projectiles.remove_at(index)
		_spawn_impact(impact, state)
		return


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
	_confirmed_shots.clear()
	_last_authoritative_event_id = 0
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
		(String(effect.get("resource", "")).is_empty() and String(effect.get("ale_reference", "")).is_empty())
		or int(effect.get("frames", 0)) <= 0
		or float(effect.get("fps", 0.0)) <= 0.0
	):
		return false
	return not requires_speed or float(effect.get("travel_pixels_per_second", 0.0)) > 0.0


## 从受控的本地效果配置加载 SpriteFrames 或已有 ALE 内容包。
## [param effect] 清单中的弹体、爆炸或炮口表现。
## 返回合法 raw 动画；资源缺失时为 null。
func _load_effect_frames(effect: Dictionary) -> SpriteFrames:
	var reference := String(effect.get("ale_reference", ""))
	var frames := CombatAnimationLibrary.load_ale(reference) if not reference.is_empty() \
		else ResourceLoader.load(String(effect.get("resource", "")), "SpriteFrames") as SpriteFrames
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
		"input_sequence": -1,
		"weapon_id": String(_weapon_id),
		"impact_frames": _impact_frames,
		"impact_config": _weapon["impact"].duplicate(true),
		"speed": float(projectile["travel_pixels_per_second"]),
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


## 使用发射时冻结的装备特效创建爆炸，换装不能改变已在途的弹体效果。
## [param shot] 发射时保留的爆炸资源和时长配置。
## [param position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _spawn_impact(position: Vector2, shot: Dictionary) -> void:
	var wrapper := _create_effect_node("WeaponImpact", position, shot["impact_frames"])
	_impacts.append({"node": wrapper, "elapsed": 0.0, "config": shot["impact_config"]})


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
	if frames.has_meta("ale_origins"):
		sprite.centered = false
		sprite.offset = frames.get_meta("ale_origins")[0]
		sprite.frame_changed.connect(func() -> void:
			sprite.offset = frames.get_meta("ale_origins")[sprite.frame]
		)
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
		var collision := {"hit": false} if bool(state.get("piercing", false)) else _resolve_visual_collision(previous_position, next_position)
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
			_spawn_impact(Vector2(collision.get("position", next_position)), state)
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
		_spawn_impact(Vector2(state["target"]), state)
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
	var speed := float(state["speed"])
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
	_spawn_impact(target, state)
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
	for index in range(_impacts.size() - 1, -1, -1):
		var state: Dictionary = _impacts[index]
		var frame_count := int(state["config"].get("frames", 0))
		var fps := float(state["config"].get("fps", 0.0))
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
