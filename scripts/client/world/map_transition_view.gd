class_name MapTransitionView
extends Node2D

var transition_id: StringName = &""
var approach_point := Vector2.ZERO

var _sprite: AnimatedSprite2D
var _interaction_rect := Rect2()


## 以 [param transition] 的业务标识和 [param presentation] 的动画资源构建传送视图。
## Returns 资源、动画与锚点完整时返回 `OK`，否则返回明确错误码。
## Design: 旧客户端路径只允许存在于数据审计；运行时仅消费业务化 `res://` 资源。
func configure(transition: MapTransition, presentation: Dictionary) -> Error:
	if transition == null or transition.transition_id.is_empty():
		return ERR_INVALID_PARAMETER
	if String(presentation.get("kind", "")) != "animated_sprite":
		return ERR_INVALID_DATA
	var resource_path := String(presentation.get("resource", ""))
	var animation := StringName(presentation.get("animation", ""))
	var frames := ResourceLoader.load(resource_path, "SpriteFrames") as SpriteFrames
	if frames == null or animation.is_empty() or not frames.has_animation(animation):
		return ERR_CANT_OPEN
	var anchor_value: Variant = presentation.get("anchor", [])
	var offset_value: Variant = presentation.get("offset", [0, 0])
	var interaction_value: Variant = presentation.get("interaction_rect", [])
	if (
		not _is_vector_pair(anchor_value)
		or not _is_vector_pair(offset_value)
		or not interaction_value is Array
		or (interaction_value as Array).size() != 4
		or String(presentation.get("interaction_space", "")) != "asset_local_fixed_bounds"
	):
		return ERR_INVALID_DATA
	var anchor_values: Array = anchor_value
	var offset_values: Array = offset_value
	var anchor := Vector2(float(anchor_values[0]), float(anchor_values[1]))
	var offset := Vector2(float(offset_values[0]), float(offset_values[1]))
	var sort_baseline := float(presentation.get("sort_baseline", anchor.y))
	var interaction_values: Array = interaction_value
	_interaction_rect = Rect2(
		float(interaction_values[0]),
		float(interaction_values[1]),
		float(interaction_values[2]),
		float(interaction_values[3]),
	)
	if _interaction_rect.size.x <= 0.0 or _interaction_rect.size.y <= 0.0:
		return ERR_INVALID_DATA

	transition_id = transition.transition_id
	approach_point = transition.approach_point
	position = Vector2(anchor.x, sort_baseline)
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "AnimatedIcon"
	_sprite.sprite_frames = frames
	_sprite.animation = animation
	_sprite.centered = bool(presentation.get("centered", false))
	_sprite.position = offset + Vector2(0.0, anchor.y - sort_baseline)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sprite)
	_sprite.play(animation)
	return OK


## 判断世界坐标 [param world_position] 是否落在数据声明的固定本地交互矩形内。
## Returns 命中固定区域时返回 `true`，结果不随动画帧透明像素变化。
func hit_test(world_position: Vector2) -> bool:
	if _sprite == null:
		return false
	return _interaction_rect.has_point(_sprite.to_local(world_position))


## 验证 [param value] 是否是可转换为二维坐标的两个元素数组。
## Returns 恰有两个元素时返回 `true`。
func _is_vector_pair(value: Variant) -> bool:
	return value is Array and (value as Array).size() == 2
