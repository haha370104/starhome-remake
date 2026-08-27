class_name CharacterFactory
extends RefCounted

const MOVE_ANIMATION_FPS := 14.0


## Builds the requested runtime object from configuration data.
## [param catalog] Configuration data that controls the operation.
## [param key] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
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


## Builds the requested runtime object from configuration data.
## [param group] Input value consumed by the operation.
## Returns the result produced by the operation.
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


## Performs the `action_offsets` operation.
## [param group] Input value consumed by the operation.
## Returns Structured result data produced by the operation.
static func _action_offsets(group: Dictionary) -> Dictionary:
	return {
		"move": Vector2(group["move"]["offset"][0], group["move"]["offset"][1]),
		"stand": Vector2(group["stand"]["offset"][0], group["stand"]["offset"][1]),
	}


## Performs the `atlas_frame` operation.
## [param texture] Input value consumed by the operation.
## [param metadata] Input value consumed by the operation.
## [param index] Sequence, tick, or index value used by the operation.
## Returns the result produced by the operation.
static func _atlas_frame(texture: Texture2D, metadata: Dictionary, index: int) -> AtlasTexture:
	var cell := Vector2(metadata["cell"][0], metadata["cell"][1])
	var columns := int(metadata["columns"])
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(Vector2(index % columns, floori(index / float(columns))) * cell, cell)
	atlas.filter_clip = true
	return atlas
