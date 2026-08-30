class_name MonsterAttackEffectController
extends Node

const RAW_ANIMATION := &"raw"

var _world_parent: Node2D
var _effect_definitions: Dictionary = {}
var _active_projectiles: Array[Dictionary] = []
var _active_impacts: Array[Dictionary] = []
var _presented_attack_ids: Dictionary = {}
var _presented_impact_ids: Dictionary = {}
var _ale_repository: RefCounted
var _glory_presentations: RefCounted


## 配置怪物远程攻击表现所需的业务清单和世界节点。
## [param manifest] 战斗表现清单。
## [param world_parent] 承载独立弹体节点的世界节点。
## 返回配置是否成功。
func configure(manifest: Dictionary, world_parent: Node2D) -> Error:
	clear()
	_world_parent = world_parent
	if _world_parent == null:
		return ERR_INVALID_PARAMETER
	var effects_value: Variant = manifest.get("monster_effects", {})
	if not effects_value is Dictionary:
		return ERR_INVALID_DATA
	_effect_definitions = (effects_value as Dictionary).duplicate(true)
	return OK


## 注入全量荣耀 ALE 仓储，供生成目录中的弹体和贴身命中特效使用。
func configure_glory(repository: RefCounted, presentations: RefCounted) -> void:
	_ale_repository = repository
	_glory_presentations = presentations


## 根据权威攻击开始事件创建荣耀版怪物弹体；贴身攻击不创建弹体。
## [param event] `monster_attack_started` 权威事件。
## 返回是否创建了新的弹体表现。
func present_attack(event: Dictionary) -> bool:
	var attack_id := String(event.get("attack_id", ""))
	if attack_id.is_empty() or _presented_attack_ids.has(attack_id):
		return false
	if StringName(event.get("attack_archetype", "")) == &"contact_melee":
		_presented_attack_ids[attack_id] = true
		return false
	var actor_id := String(event.get("combat_actor_id", ""))
	var actor_value: Variant = _effect_definitions.get(actor_id, {})
	if not actor_value is Dictionary or (actor_value as Dictionary).is_empty():
		return _present_ale_projectile(event, actor_id)
	var projectile_value: Variant = (actor_value as Dictionary).get("projectile", {})
	if not _valid_projectile(projectile_value):
		return false
	var projectile: Dictionary = projectile_value
	var origin := _vector_from_event(event.get("origin", []))
	var target := _vector_from_event(event.get("target_position", []))
	var speed := float(event.get("projectile_speed", 0.0))
	if not origin.is_finite() or not target.is_finite() or speed <= 0.0:
		return false
	var frames := ResourceLoader.load(String(projectile["resource"]), "SpriteFrames") as SpriteFrames
	if frames == null or not frames.has_animation(RAW_ANIMATION):
		return false
	var wrapper := Node2D.new()
	wrapper.name = "MonsterProjectile_%s" % attack_id.replace(".", "_")
	wrapper.position = origin
	wrapper.rotation = origin.angle_to_point(target)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.animation = RAW_ANIMATION
	sprite.frame = 0
	sprite.centered = false
	var offset_values: Array = projectile["offset"]
	sprite.offset = Vector2(float(offset_values[0]), float(offset_values[1]))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	_active_projectiles.append({
		"node": wrapper,
		"origin": origin,
		"target": target,
		"elapsed": 0.0,
		"duration": maxf(origin.distance_to(target) / speed, 0.001),
		"frames": int(projectile["frames"]),
		"fps": float(projectile["fps"]),
	})
	_presented_attack_ids[attack_id] = true
	return true


func _present_ale_projectile(event: Dictionary, actor_id: String) -> bool:
	if _ale_repository == null or _glory_presentations == null:
		return false
	var presentation: Dictionary = _glory_presentations.definition_for_actor(actor_id)
	var reference := String(presentation.get("projectile", "")).strip_edges()
	var origin := _vector_from_event(event.get("origin", []))
	var target := _vector_from_event(event.get("target_position", []))
	var speed := float(event.get("projectile_speed", 0.0))
	if reference.is_empty() or not origin.is_finite() or not target.is_finite() or speed <= 0.0:
		return false
	var animation: Dictionary = _ale_repository.load_animation(
		reference, String(presentation.get("preferred_prefix", "pic3/npc"))
	)
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return false
	var attack_id := String(event["attack_id"])
	var wrapper := Node2D.new()
	wrapper.name = "MonsterProjectile_%s" % attack_id.replace(".", "_")
	wrapper.position = origin
	wrapper.rotation = origin.angle_to_point(target)
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_ale_frame(sprite, frames[0])
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	_active_projectiles.append({
		"node": wrapper, "origin": origin, "target": target, "elapsed": 0.0,
		"duration": maxf(origin.distance_to(target) / speed, 0.001),
		"frames": frames.size(), "fps": 10.0, "ale_frames": frames,
	})
	_presented_attack_ids[attack_id] = true
	return true


## 在权威贴身攻击结算时，于受击战车位置播放荣耀版命中特效。
## [param event] `monster_attack_resolved` 权威事件。
## [param target_position] 受击目标在世界父节点坐标系内的位置。
## 返回是否创建了新的命中特效。
func present_contact_impact(event: Dictionary, target_position: Vector2) -> bool:
	var attack_id := String(event.get("attack_id", ""))
	if (
		attack_id.is_empty()
		or _presented_impact_ids.has(attack_id)
		or StringName(event.get("attack_archetype", "")) != &"contact_melee"
		or not target_position.is_finite()
	):
		return false
	var actor_value: Variant = _effect_definitions.get(String(event.get("combat_actor_id", "")), {})
	if (not actor_value is Dictionary or (actor_value as Dictionary).is_empty()) \
		and _effect_definitions.has("photosensitive_orb_standard"):
		actor_value = _effect_definitions["photosensitive_orb_standard"]
	if not actor_value is Dictionary or (actor_value as Dictionary).is_empty():
		return _present_ale_contact_impact(event, target_position)
	var impact_value: Variant = (actor_value as Dictionary).get("contact_impact", {})
	if not _valid_effect(impact_value):
		return false
	var impact: Dictionary = impact_value
	var frames := ResourceLoader.load(String(impact["resource"]), "SpriteFrames") as SpriteFrames
	if frames == null or not frames.has_animation(RAW_ANIMATION):
		return false
	var wrapper := Node2D.new()
	wrapper.name = "MonsterContactImpact_%s" % attack_id.replace(".", "_")
	wrapper.position = target_position
	wrapper.z_index = 1
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.animation = RAW_ANIMATION
	sprite.frame = 0
	sprite.centered = false
	var offset_values: Array = impact["offset"]
	sprite.offset = Vector2(float(offset_values[0]), float(offset_values[1]))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	_active_impacts.append({
		"node": wrapper,
		"elapsed": 0.0,
		"frames": int(impact["frames"]),
		"fps": float(impact["fps"]),
	})
	_presented_impact_ids[attack_id] = true
	return true


func _present_ale_contact_impact(event: Dictionary, target_position: Vector2) -> bool:
	if _ale_repository == null or _glory_presentations == null:
		return false
	var presentation: Dictionary = _glory_presentations.definition_for_actor(
		String(event.get("combat_actor_id", ""))
	)
	var reference := String(presentation.get("hit_effect", "")).strip_edges()
	if reference.is_empty():
		return false
	var animation: Dictionary = _ale_repository.load_animation(
		reference, String(presentation.get("preferred_prefix", "pic3/npc"))
	)
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return false
	var attack_id := String(event["attack_id"])
	var wrapper := Node2D.new()
	wrapper.name = "MonsterContactImpact_%s" % attack_id.replace(".", "_")
	wrapper.position = target_position
	wrapper.z_index = 1
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_ale_frame(sprite, frames[0])
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	_active_impacts.append({
		"node": wrapper, "elapsed": 0.0, "frames": frames.size(), "fps": 10.0,
		"ale_frames": frames,
	})
	_presented_impact_ids[attack_id] = true
	return true


## 按渲染时间推进怪物弹体，并在权威目标点结束表现。
## [param delta_seconds] 本帧秒数。
func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	for index in range(_active_projectiles.size() - 1, -1, -1):
		var state: Dictionary = _active_projectiles[index]
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		var progress := minf(float(state["elapsed"]) / float(state["duration"]), 1.0)
		var wrapper := state["node"] as Node2D
		if wrapper != null and is_instance_valid(wrapper):
			wrapper.position = Vector2(state["origin"]).lerp(Vector2(state["target"]), progress)
			var next_frame := posmod(
				int(floor(float(state["elapsed"]) * float(state["fps"]))), int(state["frames"])
			)
			var ale_frames: Variant = state.get("ale_frames")
			if ale_frames is Array:
				var ale_sprite := wrapper.get_node_or_null("Sprite") as Sprite2D
				if ale_sprite != null:
					_apply_ale_frame(ale_sprite, (ale_frames as Array)[next_frame])
			else:
				var sprite := wrapper.get_node_or_null("Sprite") as AnimatedSprite2D
				if sprite != null:
					sprite.frame = next_frame
		if progress >= 1.0:
			_free_projectile(state)
			_active_projectiles.remove_at(index)
	for index in range(_active_impacts.size() - 1, -1, -1):
		var state: Dictionary = _active_impacts[index]
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		var frame_count := int(state["frames"])
		var fps := float(state["fps"])
		var wrapper := state["node"] as Node2D
		if wrapper != null and is_instance_valid(wrapper):
			var next_frame := mini(int(floor(float(state["elapsed"]) * fps)), frame_count - 1)
			var ale_frames: Variant = state.get("ale_frames")
			if ale_frames is Array:
				var ale_sprite := wrapper.get_node_or_null("Sprite") as Sprite2D
				if ale_sprite != null:
					_apply_ale_frame(ale_sprite, (ale_frames as Array)[next_frame])
			else:
				var sprite := wrapper.get_node_or_null("Sprite") as AnimatedSprite2D
				if sprite != null:
					sprite.frame = next_frame
		if float(state["elapsed"]) >= float(frame_count) / fps:
			_free_effect_node(state)
			_active_impacts.remove_at(index)


## 清除地图切换前仍在飞行的弹体与事件游标。
func clear() -> void:
	for state in _active_projectiles:
		_free_projectile(state)
	for state in _active_impacts:
		_free_effect_node(state)
	_active_projectiles.clear()
	_active_impacts.clear()
	_presented_attack_ids.clear()
	_presented_impact_ids.clear()


## 统计当前仍在飞行的怪物弹体。
## 返回活跃弹体节点数量。
func active_projectile_count() -> int:
	return _active_projectiles.size()


## 统计当前仍在播放的贴身攻击命中特效。
## 返回活跃命中特效节点数量。
func active_contact_impact_count() -> int:
	return _active_impacts.size()


## 将节点时钟转发到显式可测试的推进入口。
## [param delta] 本帧秒数。
func _process(delta: float) -> void:
	advance(delta)


## 校验怪物弹体表现描述符。
## [param projectile_value] 待校验的清单值。
## 返回字段是否足够加载和播放。
func _valid_projectile(projectile_value: Variant) -> bool:
	return _valid_effect(projectile_value)


## 校验一次性怪物表现描述符。
## [param effect_value] 待校验的清单值。
## 返回字段是否足够加载和播放。
func _valid_effect(effect_value: Variant) -> bool:
	if not effect_value is Dictionary:
		return false
	var effect: Dictionary = effect_value
	var offset_value: Variant = effect.get("offset", [])
	return (
		not String(effect.get("resource", "")).is_empty()
		and int(effect.get("frames", 0)) > 0
		and float(effect.get("fps", 0.0)) > 0.0
		and offset_value is Array
		and (offset_value as Array).size() == 2
	)


## 将事件二维数组转换为坐标，无效输入返回非有限向量。
## [param value] 事件字段值。
## 返回解析后的坐标。
func _vector_from_event(value: Variant) -> Vector2:
	if not value is Array or (value as Array).size() != 2:
		return Vector2.INF
	return Vector2(float(value[0]), float(value[1]))


## 立即释放一个弹体节点。
## [param state] 活跃弹体状态。
func _free_projectile(state: Dictionary) -> void:
	_free_effect_node(state)


## 立即释放一个一次性怪物表现节点。
## [param state] 活跃表现状态。
func _free_effect_node(state: Dictionary) -> void:
	var node := state.get("node") as Node
	if node != null and is_instance_valid(node):
		node.free()


func _apply_ale_frame(sprite: Sprite2D, frame: Dictionary) -> void:
	sprite.texture = frame["texture"] as Texture2D
	sprite.position = frame["origin"] as Vector2
