class_name MineralWorldView
extends Node2D

const HOVER_GLOW_SHADER := preload(
	"res://scripts/client/presentation/combat/ground_loot_hover_glow.gdshader"
)
const WorldHoverTooltipScript := preload("res://scripts/client/ui/world_hover_tooltip.gd")
const HOVER_GLOW_COLOR := Color("33ff00")
const HOVER_GLOW_RADIUS := 4.0

var source_id := ""
var mineral_id := ""
var remaining := 0
var required_mining_level := 0
var visual_variant := 0
var _sprite: Sprite2D
var _tooltip
var _hover_material: ShaderMaterial
var _local_hit_rect := Rect2()


## 以荣耀版 ALE 帧表和权威矿源快照创建一处矿物表现。
## [param snapshot] 调用方传入的 `snapshot` 参数。
## [param presentation] 调用方传入的 `presentation` 参数。
## 返回该函数计算、查询或操作得到的结果。
func configure(snapshot: Dictionary, presentation: Dictionary) -> Error:
	var runtime_animation: Variant = presentation.get("runtime_animation", {})
	if runtime_animation is Dictionary and not runtime_animation.is_empty():
		return _configure_runtime_animation(snapshot, runtime_animation)
	var texture_path := String(presentation.get("world_texture", ""))
	var cell_value: Variant = presentation.get("cell_size", [])
	var origin_value: Variant = presentation.get("origin", [])
	if texture_path.is_empty() or not ResourceLoader.exists(texture_path) \
			or not cell_value is Array or (cell_value as Array).size() != 2 \
			or not origin_value is Array or (origin_value as Array).size() != 2:
		return ERR_INVALID_DATA
	var cell_size := Vector2(float(cell_value[0]), float(cell_value[1]))
	var origin := Vector2(float(origin_value[0]), float(origin_value[1]))
	var frame_count := int(presentation.get("frame_count", 0))
	if cell_size.x <= 0.0 or cell_size.y <= 0.0 or frame_count <= 0:
		return ERR_INVALID_DATA
	visual_variant = clampi(int(snapshot.get("visual_variant", 0)), 0, frame_count - 1)
	var atlas := AtlasTexture.new()
	atlas.atlas = load(texture_path)
	atlas.region = Rect2(
		Vector2(cell_size.x * float(visual_variant), 0.0),
		cell_size,
	)
	_sprite = Sprite2D.new()
	_sprite.name = "MineralSprite"
	_sprite.texture = atlas
	_sprite.centered = false
	_sprite.position = origin
	_hover_material = ShaderMaterial.new()
	_hover_material.shader = HOVER_GLOW_SHADER
	_hover_material.set_shader_parameter("glow_color", HOVER_GLOW_COLOR)
	_hover_material.set_shader_parameter("glow_radius", HOVER_GLOW_RADIUS)
	_hover_material.set_shader_parameter("hover_amount", 0.0)
	_set_shader_frame_region(atlas)
	_sprite.material = _hover_material
	add_child(_sprite)
	_local_hit_rect = Rect2(origin, cell_size)
	_tooltip = WorldHoverTooltipScript.new()
	add_child(_tooltip)
	apply_snapshot(snapshot)
	return OK


## 执行 `configure_runtime_animation` 对应的模块操作。
## [param snapshot] 调用方传入的 `snapshot` 参数。
## [param animation] 调用方传入的 `animation` 参数。
## 返回该函数计算、查询或操作得到的结果。
func _configure_runtime_animation(snapshot: Dictionary, animation: Dictionary) -> Error:
	var frames: Array = animation.get("frames", [])
	if frames.is_empty():
		return ERR_INVALID_DATA
	visual_variant = clampi(int(snapshot.get("visual_variant", 0)), 0, frames.size() - 1)
	var frame: Dictionary = frames[visual_variant]
	var texture := frame.get("texture") as Texture2D
	var size := Vector2(frame.get("size", Vector2.ZERO))
	var origin := Vector2(frame.get("origin", Vector2.ZERO))
	if texture == null or size.x <= 0.0 or size.y <= 0.0:
		return ERR_INVALID_DATA
	var hit_origin := Vector2(animation.get("bounds_origin", origin))
	var hit_size := Vector2(animation.get("bounds_size", size))
	_create_visual_nodes(texture, origin, hit_size, hit_origin)
	apply_snapshot(snapshot)
	return OK


## 创建 `create_visual_nodes` 对应的运行时对象。
## [param texture] 调用方传入的 `texture` 参数。
## [param origin] 调用方传入的 `origin` 参数。
## [param size] 调用方传入的 `size` 参数。
## [param hit_origin] 调用方传入的 `hit_origin` 参数。
func _create_visual_nodes(
	texture: Texture2D,
	origin: Vector2,
	size: Vector2,
	hit_origin := Vector2.INF,
) -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "MineralSprite"
	_sprite.texture = texture
	_sprite.centered = false
	_sprite.position = origin
	_hover_material = ShaderMaterial.new()
	_hover_material.shader = HOVER_GLOW_SHADER
	_hover_material.set_shader_parameter("glow_color", HOVER_GLOW_COLOR)
	_hover_material.set_shader_parameter("glow_radius", HOVER_GLOW_RADIUS)
	_hover_material.set_shader_parameter("hover_amount", 0.0)
	_set_shader_frame_region(texture)
	_sprite.material = _hover_material
	add_child(_sprite)
	_local_hit_rect = Rect2(origin if not hit_origin.is_finite() else hit_origin, size)
	_tooltip = WorldHoverTooltipScript.new()
	add_child(_tooltip)


## 将当前图集帧边界交给晕染材质，防止采样其它随机款式或挤压整个图集。
## [param texture] 当前 ALE 帧或独立矿物纹理。
func _set_shader_frame_region(texture: Texture2D) -> void:
	if texture is AtlasTexture:
		var atlas := texture as AtlasTexture
		var page_size := atlas.atlas.get_size()
		_hover_material.set_shader_parameter("source_region", Vector4(
			atlas.region.position.x / page_size.x, atlas.region.position.y / page_size.y,
			atlas.region.size.x / page_size.x, atlas.region.size.y / page_size.y
		))


## 应用矿源的可变权威状态；储量变化不切换 ALE 外观帧。
## [param snapshot] 调用方传入的 `snapshot` 参数。
func apply_snapshot(snapshot: Dictionary) -> void:
	source_id = String(snapshot.get("source_id", source_id))
	mineral_id = String(snapshot.get("mineral_id", mineral_id))
	remaining = int(snapshot.get("remaining", remaining))
	required_mining_level = int(snapshot.get("required_mining_level", required_mining_level))
	var point_value: Variant = snapshot.get("position", [])
	if point_value is Array and (point_value as Array).size() == 2:
		position = Vector2(float(point_value[0]), float(point_value[1]))
	modulate.a = clampf(float(snapshot.get("alpha", 1.0)), 0.0, 1.0)
	if _tooltip != null:
		_tooltip.set_content("%s，需要采矿等级%d级" % [
			String(snapshot.get("display_name", mineral_id)),
			required_mining_level,
		])


## 判断世界坐标是否命中此矿点的原始 ALE 帧矩形。
## [param world_position] 调用方传入的 `world_position` 参数。
## 返回该函数计算、查询或操作得到的结果。
func contains_world_point(world_position: Vector2) -> bool:
	return visible and _local_hit_rect.has_point(to_local(world_position))


## 切换荣耀版地面资源通用的绿色悬浮描边与说明文字。
## [param hovered] 调用方传入的 `hovered` 参数。
func set_hovered(hovered: bool) -> void:
	if _hover_material != null:
		_hover_material.set_shader_parameter("hover_amount", 1.0 if hovered else 0.0)
	if _tooltip != null:
		if hovered:
			_tooltip.show_near(to_local(get_global_mouse_position()))
		else:
			_tooltip.visible = false


## 返回当前 ALE 图集帧，供表现回归测试读取。
## 执行 `displayed_variant` 对应的模块操作。
func displayed_variant() -> int:
	return visual_variant


## 返回本地命中矩形，供坐标和原点回归测试读取。
## 执行 `local_hit_rect` 对应的模块操作。
func local_hit_rect() -> Rect2:
	return _local_hit_rect
