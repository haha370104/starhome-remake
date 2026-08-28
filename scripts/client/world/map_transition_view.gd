class_name MapTransitionView
extends Node2D

var transition_id: StringName = &""
var approach_point := Vector2.ZERO

var _sprite: AnimatedSprite2D
var _interaction_rect := Rect2()


## 按已解析的共享表现数据创建一个可点击、循环播放的地图传送点。
## [param transition] 传送业务数据，提供唯一标识与寻路接近点。
## [param presentation] 由共享目录解析出的动画资源、锚点和固定命中框。
## 返回：[enum Error]；创建成功返回 [constant OK]，非法配置或资源缺失返回错误码。
## 设计：本组件不识别旧客户端文件名；方向到资源的映射由共享目录集中完成。
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


## 判断一个世界坐标是否落在传送点固定交互矩形内。
## [param world_position] 鼠标点击对应的地图世界坐标。
## 返回：位于命中框内且精灵已创建时为 [code]true[/code]。
func hit_test(world_position: Vector2) -> bool:
	if _sprite == null:
		return false
	return _interaction_rect.has_point(_sprite.to_local(world_position))


## 判断动态值是否为可转换为 [Vector2] 的二元素数组。
## [param value] 待校验的 JSON 动态值。
## 返回：值为长度二的数组时为 [code]true[/code]。
func _is_vector_pair(value: Variant) -> bool:
	return value is Array and (value as Array).size() == 2
