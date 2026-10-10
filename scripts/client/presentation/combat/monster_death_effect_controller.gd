class_name MonsterDeathEffectController
extends Node

const RAW_ANIMATION := &"raw"

var _clock := 0.0
var _epoch := 0
var _world_parent: Node2D
var _effect_definitions: Dictionary = {}
var _active_effects: Array[Dictionary] = []
var _presented_generations: Dictionary = {}
var _glory_presentations: RefCounted


## 配置怪物死亡特效控制器，并校验业务清单中的动画描述。
## [param manifest] 战斗表现清单。
## [param world_parent] 承载独立死亡特效的世界节点。
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
	for actor_value: Variant in _effect_definitions.values():
		if not actor_value is Dictionary or not _valid_effect((actor_value as Dictionary).get("death", {})):
			_effect_definitions.clear()
			return ERR_INVALID_DATA
	return OK


## 注入荣耀怪物的明确素材映射，资源加载统一交给共享队列。
## [param presentations] 怪物表现目录。
func configure_glory(presentations: RefCounted) -> void:
	_glory_presentations = presentations


## 当前地图出现该类怪物时预取死亡动画，不读取其他地图资源。
## [param combat_actor_id] 已登记的怪物表现身份。
func prefetch(combat_actor_id: String) -> void:
	_request_effect(combat_actor_id, Callable())


## 接收唯一死亡代际，权威死亡不等待资源；异步结果按原时间播放。
## [param entity_id] 实体身份。[param combat_actor_id] 表现身份。[param world_position] 死亡脚点。[param death_generation] 代际。
## 返回是否接受新事件，重复或无明确素材映射时为 false。
func present_death(entity_id: String, combat_actor_id: String, world_position: Vector2, death_generation: int) -> bool:
	if entity_id.is_empty() or combat_actor_id.is_empty() or death_generation <= 0: return false
	if int(_presented_generations.get(entity_id, 0)) >= death_generation: return false
	_presented_generations[entity_id] = death_generation
	return _request_effect(combat_actor_id,
		_on_effect_ready.bind(entity_id, world_position, death_generation, _epoch, _clock))


## 只按明确的旧 SpriteFrames 或荣耀 ALE 映射请求资源。
## [param actor_id] 表现身份。[param callback] 可选消费回调，预取不创建节点。
## 返回是否有可用的资源映射。
func _request_effect(actor_id: String, callback: Callable) -> bool:
	var effect: Dictionary = _effect_definitions.get(actor_id, {}).get("death", {})
	if not effect.is_empty():
		if not _valid_effect(effect): return false
		var receiver := _on_legacy_ready.bind(effect, callback) if callback.is_valid() else Callable()
		SpriteResources.request_frames(String(effect.resource), receiver)
		return true
	if _glory_presentations == null: return false
	var presentation: Dictionary = _glory_presentations.definition_for_actor(actor_id)
	var reference := String(presentation.get("death_effect", "")).strip_edges()
	if reference.is_empty(): return false
	SpriteResources.request_animation(reference, String(presentation.get("preferred_prefix", "pic3/npc")), callback)
	return true


## 合并已加载的旧动画与既有帧率、原点配置。
## [param visual] 异步动画。[param effect] 业务配置。[param callback] 已绑定的死亡实例回调。
func _on_legacy_ready(visual: Dictionary, effect: Dictionary, callback: Callable) -> void:
	var result := visual.duplicate()
	result["effect"] = effect
	if callback.is_valid(): callback.call(result)


## 只在同一地图、同一死亡代际且尚未过期时创建动画节点。
## [param visual] 共享动画。[param entity_id] 怪物。[param point] 脚点。[param generation] 死亡代际。
## [param epoch] 地图世代。[param started] 接收死亡时的表现时钟。
func _on_effect_ready(visual: Dictionary, entity_id: String, point: Vector2, generation: int, epoch: int, started: float) -> void:
	if epoch != _epoch or is_queued_for_deletion() or not is_instance_valid(_world_parent): return
	if int(_presented_generations.get(entity_id, 0)) != generation: return
	var elapsed := maxf(0.0, _clock - started)
	var frames: Array = visual.get("frames", [])
	var legacy := visual.get("sprite_frames") as SpriteFrames
	var effect: Dictionary = visual.get("effect", {})
	var fps := float(effect.get("fps", 10.0))
	var count := int(effect.get("frames", 0)) if legacy != null else frames.size()
	var frame := int(floor(elapsed * fps))
	if frame >= count or (legacy != null and not legacy.has_animation(RAW_ANIMATION)): return
	var wrapper := Node2D.new()
	wrapper.name = "MonsterDeath_%s_%d" % [entity_id.replace(".", "_"), generation]
	wrapper.position = point
	var state := {"node": wrapper, "elapsed": elapsed, "frames": count, "fps": fps}
	if legacy != null:
		var sprite := AnimatedSprite2D.new()
		sprite.name = "Sprite"
		sprite.sprite_frames = legacy
		sprite.animation = RAW_ANIMATION
		sprite.frame = frame
		sprite.centered = false
		sprite.offset = Vector2(float(effect.offset[0]), float(effect.offset[1]))
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		wrapper.add_child(sprite)
	else:
		var sprite := Sprite2D.new()
		sprite.name = "Sprite"
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_apply_ale_frame(sprite, frames[frame])
		wrapper.add_child(sprite)
		state["ale_frames"] = frames
	_world_parent.add_child(wrapper)
	_active_effects.append(state)


## 按渲染时间推进全部独立死亡特效。
## [param delta_seconds] 本帧秒数。
func advance(delta_seconds: float) -> void:
	_clock += maxf(0.0, delta_seconds)
	if delta_seconds <= 0.0:
		return
	for index in range(_active_effects.size() - 1, -1, -1):
		var state: Dictionary = _active_effects[index]
		state["elapsed"] = float(state["elapsed"]) + delta_seconds
		var frame := int(floor(float(state["elapsed"]) * float(state["fps"])))
		if frame >= int(state["frames"]):
			_free_effect(state)
			_active_effects.remove_at(index)
			continue
		var wrapper := state["node"] as Node2D
		if wrapper != null and is_instance_valid(wrapper):
			var ale_frames: Variant = state.get("ale_frames")
			if ale_frames is Array:
				var ale_sprite := wrapper.get_node_or_null("Sprite") as Sprite2D
				if ale_sprite != null:
					_apply_ale_frame(ale_sprite, (ale_frames as Array)[frame])
			else:
				var sprite := wrapper.get_node_or_null("Sprite") as AnimatedSprite2D
				if sprite != null:
					sprite.frame = frame


## 清除地图切换前残留的瞬态特效和事件代际游标。
func clear() -> void:
	_epoch += 1
	for state in _active_effects:
		_free_effect(state)
	_active_effects.clear()
	_presented_generations.clear()


## 统计当前仍在播放的死亡特效数量。
## 返回活跃的独立死亡动画节点数。
func active_effect_count() -> int:
	return _active_effects.size()


## 将节点生命周期时钟转发到可测试的显式推进入口。
## [param delta] 本帧秒数。
func _process(delta: float) -> void:
	advance(delta)


## 校验死亡特效描述符的必需字段。
## [param effect_value] 待校验的清单值。
## 返回字段能否安全用于加载和播放。
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


## 立即释放一个瞬态特效节点。
## [param state] 活跃特效状态。
func _free_effect(state: Dictionary) -> void:
	var node := state.get("node") as Node
	if node != null and is_instance_valid(node):
		node.free()


## 执行 `apply_ale_frame` 对应的模块操作。
## [param sprite] 调用方传入的 `sprite` 参数。
## [param frame] 调用方传入的 `frame` 参数。
func _apply_ale_frame(sprite: Sprite2D, frame: Dictionary) -> void:
	sprite.texture = frame["texture"] as Texture2D
	sprite.position = frame["origin"] as Vector2
