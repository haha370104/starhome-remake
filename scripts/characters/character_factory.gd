class_name CharacterFactory
extends RefCounted

const MOVE_ANIMATION_FPS := 14.0


## 创建 `build_character_set` 对应的模块状态。
## [param catalog] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param key] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func build_character_set(catalog: Dictionary, key: String) -> Dictionary:
	var body_group: Dictionary = catalog["shared_body"]
	var shadow_group: Dictionary = catalog["shared_shadow"]
	var equipment_group: Dictionary = catalog[key]["equipment"]
	return {
		"body_frames": _build_frames(body_group),
		"body_offsets": _action_offsets(body_group),
		"equipment_frames": _build_frames(equipment_group),
		"equipment_offsets": _action_offsets(equipment_group),
		"shadow_frames": _build_frames(shadow_group),
		"shadow_offsets": _action_offsets(shadow_group),
	}


## 创建 `build_frames` 对应的模块状态。
## [param group] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _build_frames(group: Dictionary) -> SpriteFrames:
	var frames := SpriteFrames.new()
	if frames.has_animation(&"default"):
		frames.remove_animation(&"default")
	for direction in range(8):
		for action in ["stand", "move"]:
			var animation_name := StringName("%s_%d" % [action, direction])
			frames.add_animation(animation_name)
			frames.set_animation_loop(animation_name, action == "move")
			frames.set_animation_speed(
				animation_name,
				MOVE_ANIMATION_FPS if action == "move" else 1.0,
			)
			var metadata: Dictionary = group[action]
			var texture := load(String(metadata["texture"])) as Texture2D
			var count := 8 if action == "move" else 1
			for frame_in_direction in range(count):
				var index := direction * 8 + frame_in_direction if action == "move" else direction
				frames.add_frame(animation_name, _atlas_frame(texture, metadata, index))
	return frames


## 执行 `action_offsets` 对应的模块操作。
## [param group] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _action_offsets(group: Dictionary) -> Dictionary:
	return {
		"move": Vector2(group["move"]["offset"][0], group["move"]["offset"][1]),
		"stand": Vector2(group["stand"]["offset"][0], group["stand"]["offset"][1]),
	}


## 执行 `atlas_frame` 对应的模块操作。
## [param texture] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param metadata] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param index] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
static func _atlas_frame(texture: Texture2D, metadata: Dictionary, index: int) -> AtlasTexture:
	var cell := Vector2(metadata["cell"][0], metadata["cell"][1])
	var columns := int(metadata["columns"])
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2(index % columns, floori(index / float(columns))) * cell, cell)
	atlas.filter_clip = true
	return atlas
