class_name AleCombatVisualPresenter
extends Node2D

var current_actor_id: StringName = &""
var current_action_id: StringName = &"idle"
var current_direction := 0

var _repository: RefCounted
var _definition: Dictionary = {}
var _body := Sprite2D.new()
var _shadow := Sprite2D.new()
var _animation_cache: Dictionary = {}
var _elapsed_seconds := 0.0


## 配置一个由 npcinfo 三态 ALE 引用驱动的怪物表现器。
func configure(
	repository: RefCounted,
	actor_id: String,
	definition: Dictionary,
) -> Error:
	if repository == null or actor_id.is_empty() or definition.is_empty():
		return ERR_INVALID_PARAMETER
	_repository = repository
	_definition = definition.duplicate(true)
	current_actor_id = StringName(actor_id)
	_body.name = "Body"
	_body.centered = false
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.name = "Shadow"
	_shadow.centered = false
	_shadow.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_shadow.z_index = -1
	add_child(_shadow)
	add_child(_body)
	return _apply_pose()


func set_action(action_id: StringName) -> bool:
	if action_id not in [&"idle", &"move", &"attack"]:
		return false
	current_action_id = action_id
	_elapsed_seconds = 0.0
	return _apply_pose() == OK


func set_direction(direction: int) -> void:
	current_direction = posmod(direction, maxi(1, int(_definition.get("directions", 8))))
	_apply_pose()


func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0:
		return
	_elapsed_seconds += delta_seconds
	_apply_pose()


func _apply_pose() -> Error:
	var body_reference := _action_reference("actions", String(current_action_id))
	if body_reference.is_empty():
		body_reference = _action_reference("actions", "idle")
	if body_reference.is_empty():
		return ERR_FILE_NOT_FOUND
	var body_animation := _load_animation(body_reference)
	if body_animation.is_empty():
		return ERR_CANT_OPEN
	_apply_animation_frame(_body, body_animation)
	var shadow_reference := _action_reference("shadow_actions", String(current_action_id))
	if shadow_reference.is_empty():
		shadow_reference = _action_reference("shadow_actions", "idle")
	if shadow_reference.is_empty():
		_shadow.visible = false
	else:
		var shadow_animation := _load_animation(shadow_reference)
		_shadow.visible = not shadow_animation.is_empty()
		if _shadow.visible:
			_apply_animation_frame(_shadow, shadow_animation)
	return OK


func _action_reference(group_name: String, action_name: String) -> String:
	var group: Variant = _definition.get(group_name, {})
	return String((group as Dictionary).get(action_name, "")).strip_edges() \
		if group is Dictionary else ""


func _load_animation(reference: String) -> Dictionary:
	var cached: Variant = _animation_cache.get(reference)
	if cached is Dictionary:
		return cached
	var loaded: Dictionary = _repository.load_animation(
		reference, String(_definition.get("preferred_prefix", "pic3/npc"))
	)
	_animation_cache[reference] = loaded
	return loaded


## ALE 原点是相对实体脚点的负偏移；每帧应用可消除不同尺寸帧的抖动。
func _apply_animation_frame(sprite: Sprite2D, animation: Dictionary) -> void:
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		sprite.visible = false
		return
	var directions := maxi(1, int(_definition.get("directions", 8)))
	var frames_per_direction := maxi(1, frames.size() / directions) \
		if frames.size() % directions == 0 else frames.size()
	var direction_slot := current_direction if frames.size() % directions == 0 else 0
	var local_frame := int(floor(_elapsed_seconds * float(_definition.get("fps", 10.0))))
	if current_action_id == &"attack":
		local_frame = mini(local_frame, frames_per_direction - 1)
	else:
		local_frame = posmod(local_frame, frames_per_direction)
	var frame: Dictionary = frames[direction_slot * frames_per_direction + local_frame]
	sprite.texture = frame["texture"] as Texture2D
	sprite.position = frame["origin"] as Vector2
	sprite.visible = true
