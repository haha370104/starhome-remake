class_name CombatVisualPresenter
extends Node2D

const RAW_ANIMATION := &"raw"

var current_actor_id: StringName = &""
var current_action_id: StringName = &""
var current_direction := 0

var _manifest: Dictionary = {}
var _actor: Dictionary = {}
var _layers: Dictionary = {}
var _layer_configs: Dictionary = {}
var _layer_action_overrides: Dictionary = {}
var _layer_direction_overrides: Dictionary = {}
var _elapsed_seconds := 0.0


## 执行 `configure` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：表现器只消费业务化运行时清单；来源审计和旧客户端路径不进入运行时解析。
func configure(manifest: Dictionary) -> Error:
	if not _is_valid_manifest(manifest):
		return ERR_INVALID_DATA
	_manifest = manifest.duplicate(true)
	clear_actor()
	return OK


## 执行 `present_actor` 对应的模块操作。
## [param actor_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func present_actor(actor_id: StringName) -> Error:
	clear_actor()
	var actors_value: Variant = _manifest.get("actors", {})
	if not actors_value is Dictionary:
		return ERR_UNCONFIGURED
	var actors: Dictionary = actors_value
	var actor_value: Variant = actors.get(String(actor_id), {})
	if not actor_value is Dictionary or (actor_value as Dictionary).is_empty():
		return ERR_DOES_NOT_EXIST
	_actor = (actor_value as Dictionary).duplicate(true)
	current_actor_id = actor_id
	current_action_id = StringName(_actor.get("default_action", "idle"))
	var layers_value: Variant = _actor.get("layers", [])
	if not layers_value is Array:
		clear_actor()
		return ERR_INVALID_DATA
	for layer_value: Variant in layers_value:
		if not layer_value is Dictionary:
			clear_actor()
			return ERR_INVALID_DATA
		var layer: Dictionary = layer_value
		var layer_id := StringName(layer.get("id", ""))
		if layer_id == &"" or _layers.has(layer_id):
			clear_actor()
			return ERR_INVALID_DATA
		var sprite := AnimatedSprite2D.new()
		sprite.name = String(layer_id).to_pascal_case()
		sprite.centered = false
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.z_index = int(layer.get("z_index", 0))
		add_child(sprite)
		_layers[layer_id] = sprite
		_layer_configs[layer_id] = layer.duplicate(true)
	var apply_error := _apply_pose()
	if apply_error != OK:
		clear_actor()
	return apply_error


## 清空当前角色的表现图层及动作计时，但保留已配置清单。
func clear_actor() -> void:
	for sprite_value: Variant in _layers.values():
		var sprite := sprite_value as AnimatedSprite2D
		if sprite != null:
			sprite.free()
	_layers.clear()
	_layer_configs.clear()
	_layer_action_overrides.clear()
	_layer_direction_overrides.clear()
	_actor.clear()
	current_actor_id = &""
	current_action_id = &""
	current_direction = 0
	_elapsed_seconds = 0.0


## 执行 `set_action` 对应的模块操作。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func set_action(action_id: StringName) -> bool:
	if current_actor_id == &"" or not _actor_supports_action(action_id):
		return false
	current_action_id = action_id
	_elapsed_seconds = 0.0
	return _apply_pose() == OK


## 执行 `set_direction` 对应的模块操作。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func set_direction(direction: int) -> void:
	current_direction = posmod(direction, 8)
	_apply_pose()


## 执行 `set_layer_action` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：炮塔瞄准/开火属于装备局部状态，不能污染角色移动状态机。
func set_layer_action(layer_id: StringName, action_id: StringName) -> bool:
	if not _layer_configs.has(layer_id):
		return false
	var layer: Dictionary = _layer_configs[layer_id]
	var actions_value: Variant = layer.get("actions", {})
	if not actions_value is Dictionary or not (actions_value as Dictionary).has(String(action_id)):
		return false
	_layer_action_overrides[layer_id] = action_id
	return _apply_pose() == OK


## 执行 `clear_layer_action` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func clear_layer_action(layer_id: StringName) -> void:
	_layer_action_overrides.erase(layer_id)
	_apply_pose()


## 执行 `set_layer_direction` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param direction] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func set_layer_direction(layer_id: StringName, direction: int) -> bool:
	if not _layer_configs.has(layer_id):
		return false
	_layer_direction_overrides[layer_id] = posmod(direction, 8)
	return _apply_pose() == OK


## 执行 `clear_layer_direction` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func clear_layer_direction(layer_id: StringName) -> void:
	_layer_direction_overrides.erase(layer_id)
	_apply_pose()


## 执行 `advance` 对应的模块操作。
## [param delta_seconds] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func advance(delta_seconds: float) -> void:
	if delta_seconds <= 0.0 or current_actor_id == &"":
		return
	_elapsed_seconds += delta_seconds
	_apply_pose()


## 执行 `layer_frame` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func layer_frame(layer_id: StringName) -> int:
	var sprite := _layers.get(layer_id) as AnimatedSprite2D
	return sprite.frame if sprite != null else -1


## 执行 `layer_frames_resource` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func layer_frames_resource(layer_id: StringName) -> SpriteFrames:
	var sprite := _layers.get(layer_id) as AnimatedSprite2D
	return sprite.sprite_frames if sprite != null else null


## 执行 `is_valid_manifest` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _is_valid_manifest(manifest: Dictionary) -> bool:
	var directions_value: Variant = manifest.get("direction_order", [])
	var actors_value: Variant = manifest.get("actors", {})
	return (
		directions_value is Array
		and (directions_value as Array).size() == 8
		and actors_value is Dictionary
		and not (actors_value as Dictionary).is_empty()
	)


## 执行 `actor_supports_action` 对应的模块操作。
## [param action_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _actor_supports_action(action_id: StringName) -> bool:
	for layer_value: Variant in _layer_configs.values():
		var layer: Dictionary = layer_value
		var actions_value: Variant = layer.get("actions", {})
		if actions_value is Dictionary and (actions_value as Dictionary).has(String(action_id)):
			return true
	return false


## 将当前动作、方向与计时原子投影到全部图层。
## 返回该函数计算、查询或操作得到的结果。
## 设计：缺少当前动作的辅助图层回退到角色默认动作，确保攻击时底盘仍保持稳定姿态。
func _apply_pose() -> Error:
	if current_actor_id == &"":
		return ERR_UNCONFIGURED
	for layer_id_value: Variant in _layers.keys():
		var layer_id := StringName(layer_id_value)
		var sprite := _layers[layer_id] as AnimatedSprite2D
		var layer: Dictionary = _layer_configs[layer_id]
		var action := _resolve_layer_action(layer_id, layer)
		if action.is_empty():
			return ERR_INVALID_DATA
		var resource_path := String(action.get("resource", ""))
		var frames_resource := sprite.sprite_frames
		if frames_resource == null or frames_resource.resource_path != resource_path:
			var loaded := ResourceLoader.load(resource_path, "SpriteFrames") as SpriteFrames
			if loaded == null or not loaded.has_animation(RAW_ANIMATION):
				return ERR_CANT_OPEN
			sprite.sprite_frames = loaded
			frames_resource = loaded
		sprite.animation = RAW_ANIMATION
		var offset_value: Variant = action.get("offset", [0, 0])
		if not offset_value is Array or (offset_value as Array).size() < 2:
			return ERR_INVALID_DATA
		var offset_values: Array = offset_value
		sprite.offset = Vector2(float(offset_values[0]), float(offset_values[1]))
		var frames_per_direction := int(action.get("frames_per_direction", 0))
		if frames_per_direction <= 0:
			return ERR_INVALID_DATA
		var resolved_direction := int(_layer_direction_overrides.get(layer_id, current_direction))
		var direction_slot := resolved_direction if String(action.get("direction_mode", "")) == "eight_way" else 0
		var local_frame := int(floor(_elapsed_seconds * float(action.get("fps", 10.0))))
		if bool(action.get("loop", true)):
			local_frame = posmod(local_frame, frames_per_direction)
		else:
			local_frame = mini(local_frame, frames_per_direction - 1)
		var atlas_frame := direction_slot * frames_per_direction + local_frame
		if atlas_frame >= frames_resource.get_frame_count(RAW_ANIMATION):
			return ERR_INVALID_DATA
		sprite.frame = atlas_frame
	return OK


## 执行 `resolve_layer_action` 对应的模块操作。
## [param layer_id] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param layer] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func _resolve_layer_action(layer_id: StringName, layer: Dictionary) -> Dictionary:
	var actions_value: Variant = layer.get("actions", {})
	if not actions_value is Dictionary:
		return {}
	var actions: Dictionary = actions_value
	var requested_action := StringName(_layer_action_overrides.get(layer_id, current_action_id))
	var action_value: Variant = actions.get(String(requested_action), {})
	if action_value is Dictionary and not (action_value as Dictionary).is_empty():
		return action_value
	var fallback_value: Variant = actions.get(String(_actor.get("default_action", "idle")), {})
	return fallback_value if fallback_value is Dictionary else {}
