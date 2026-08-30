class_name MonsterDeathEffectController
extends Node

const RAW_ANIMATION := &"raw"

var _world_parent: Node2D
var _effect_definitions: Dictionary = {}
var _active_effects: Array[Dictionary] = []
var _presented_generations: Dictionary = {}
var _ale_repository: RefCounted
var _glory_presentations: RefCounted


## 配置怪物死亡特效控制器，并校验业务清单中的 SpriteFrames。
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


## 注入全量荣耀 ALE 仓储，供不在首批手工清单中的怪物使用。
func configure_glory(repository: RefCounted, presentations: RefCounted) -> void:
	_ale_repository = repository
	_glory_presentations = presentations


## 在怪物原脚点播放一次权威死亡代际对应的爆散动画。
## [param entity_id] 怪物实体 ID。
## [param combat_actor_id] 怪物表现角色 ID。
## [param world_position] 权威死亡脚点。
## [param death_generation] 服务端生命周期代际。
## 返回是否创建了新特效；重复事件与未知素材返回 false。
func present_death(
	entity_id: String,
	combat_actor_id: String,
	world_position: Vector2,
	death_generation: int,
) -> bool:
	if entity_id.is_empty() or combat_actor_id.is_empty() or death_generation <= 0:
		return false
	if int(_presented_generations.get(entity_id, 0)) >= death_generation:
		return false
	var actor_value: Variant = _effect_definitions.get(combat_actor_id, {})
	if not actor_value is Dictionary or (actor_value as Dictionary).is_empty():
		return _present_ale_death(entity_id, combat_actor_id, world_position, death_generation)
	var effect: Dictionary = (actor_value as Dictionary).get("death", {})
	if not _valid_effect(effect):
		return false
	var frames := ResourceLoader.load(String(effect["resource"]), "SpriteFrames") as SpriteFrames
	if frames == null or not frames.has_animation(RAW_ANIMATION):
		return false
	var wrapper := Node2D.new()
	wrapper.name = "MonsterDeath_%s_%d" % [entity_id.replace(".", "_"), death_generation]
	wrapper.position = world_position
	var sprite := AnimatedSprite2D.new()
	sprite.name = "Sprite"
	sprite.sprite_frames = frames
	sprite.animation = RAW_ANIMATION
	sprite.frame = 0
	sprite.centered = false
	var offset_values: Array = effect["offset"]
	sprite.offset = Vector2(float(offset_values[0]), float(offset_values[1]))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	_active_effects.append({
		"node": wrapper,
		"elapsed": 0.0,
		"frames": int(effect["frames"]),
		"fps": float(effect["fps"]),
	})
	_presented_generations[entity_id] = death_generation
	return true


func _present_ale_death(
	entity_id: String,
	combat_actor_id: String,
	world_position: Vector2,
	death_generation: int,
) -> bool:
	if _ale_repository == null or _glory_presentations == null:
		return false
	var presentation: Dictionary = _glory_presentations.definition_for_actor(combat_actor_id)
	var reference := String(presentation.get("death_effect", "")).strip_edges()
	if reference.is_empty():
		return false
	var animation: Dictionary = _ale_repository.load_animation(
		reference, String(presentation.get("preferred_prefix", "pic3/npc"))
	)
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return false
	var wrapper := Node2D.new()
	wrapper.name = "MonsterDeath_%s_%d" % [entity_id.replace(".", "_"), death_generation]
	wrapper.position = world_position
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.centered = false
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_apply_ale_frame(sprite, frames[0])
	wrapper.add_child(sprite)
	_world_parent.add_child(wrapper)
	_active_effects.append({
		"node": wrapper, "elapsed": 0.0, "frames": frames.size(), "fps": 10.0,
		"ale_frames": frames,
	})
	_presented_generations[entity_id] = death_generation
	return true


## 按渲染时间推进全部独立死亡特效。
## [param delta_seconds] 本帧秒数。
func advance(delta_seconds: float) -> void:
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


func _apply_ale_frame(sprite: Sprite2D, frame: Dictionary) -> void:
	sprite.texture = frame["texture"] as Texture2D
	sprite.position = frame["origin"] as Vector2
