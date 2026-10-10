class_name GroundLootWorldView
extends Node2D

const HOVER_GLOW_SHADER := preload(
	"res://scripts/client/presentation/combat/ground_loot_hover_glow.gdshader"
)
const HOVER_GLOW_COLOR := Color("33ff00")
const HOVER_GLOW_RADIUS := 4.0

var loot_id := ""
var item_definition_id := ""
var quantity := 0
var item: GameItem
var _hover_material: ShaderMaterial
var _sprite: Sprite2D
var _tooltip: Label
var _local_hit_rect := Rect2()
var _presentation: Dictionary


## 使用权威掉落快照与业务表现定义创建地面物品视图。
## [param ground_item] 与背包共用类型的领域物品实例。
## [param snapshot] 含 loot_id、物品定义、数量与世界坐标的权威快照。
## 空物品返回错误；贴图异步加载，缺少素材时显示可拾取的名称。
## 设计：节点脚点等于权威世界坐标，纹理严格按原客户端 ALE 原点以 1:1 像素绘制。
func configure(ground_item: GameItem, snapshot: Dictionary) -> Error:
	if ground_item == null:
		return ERR_INVALID_PARAMETER
	item = ground_item
	_presentation = item.presentation_for("world")
	if _presentation.is_empty(): _presentation = item.presentation_for("inventory")
	_sprite = Sprite2D.new()
	_sprite.name = "WorldIcon"
	_sprite.centered = false
	_hover_material = ShaderMaterial.new()
	_hover_material.shader = HOVER_GLOW_SHADER
	_hover_material.set_shader_parameter("glow_color", HOVER_GLOW_COLOR)
	_hover_material.set_shader_parameter("glow_radius", HOVER_GLOW_RADIUS)
	_hover_material.set_shader_parameter("hover_amount", 0.0)
	_sprite.material = _hover_material
	add_child(_sprite)
	_tooltip = Label.new()
	_tooltip.name = "HoverTooltip"
	_tooltip.z_index = 100
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_font_size_override("font_size", 13)
	_tooltip.add_theme_color_override("font_color", Color(0.72, 1.0, 0.58))
	_tooltip.add_theme_color_override("font_shadow_color", Color.BLACK)
	_tooltip.add_theme_constant_override("shadow_offset_x", 1)
	_tooltip.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_tooltip)
	apply_snapshot(item, snapshot)
	if not _presentation.is_empty(): SpriteResources.request(_presentation, _apply_texture.bind(loot_id))
	return OK


## 应用同一掉落实例的最新权威位置、数量和提示文字。
## [param ground_item] 持有稳定实例身份、数量与显示名的领域物品。
## [param snapshot] 服务端地面掉落 DTO，仅提供世界实体状态。
func apply_snapshot(ground_item: GameItem, snapshot: Dictionary) -> void:
	item = ground_item
	loot_id = String(snapshot.get("loot_id", loot_id))
	item_definition_id = item.definition_id
	quantity = item.quantity
	var point_value: Variant = snapshot.get("position", [])
	if point_value is Array and (point_value as Array).size() == 2:
		position = Vector2(float(point_value[0]), float(point_value[1]))
	if _tooltip != null:
		_tooltip.text = "%s × %d" % [item.display_name, quantity]
		if _sprite.texture == null:
			_tooltip.position = -_tooltip.get_minimum_size() * 0.5
			_local_hit_rect = Rect2(_tooltip.position, _tooltip.get_minimum_size())


## 判断一个世界坐标是否落在原始 ALE 帧的真实矩形内。
## [param world_position] 鼠标对应的世界坐标。
## 返回该坐标是否命中当前掉落图像。
func contains_world_point(world_position: Vector2) -> bool:
	return visible and _local_hit_rect.has_point(to_local(world_position))


## 判断拾取命中，包含原图、四像素发光边缘和当前可见的物品名称。
## [param world_position] 鼠标对应的世界坐标。
## 返回是否应优先拾取；名称隐藏时不保留不可见的点击区域。
func contains_pickup_point(world_position: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	var local_point := to_local(world_position)
	if _local_hit_rect.grow(HOVER_GLOW_RADIUS).has_point(local_point):
		return true
	return _tooltip != null and _tooltip.visible \
		and Rect2(_tooltip.position, _tooltip.size).grow(HOVER_GLOW_RADIUS).has_point(local_point)


## 切换原客户端风格的地面物品悬浮反馈。
## [param hovered] 当前鼠标是否命中该掉落物。
func set_hovered(hovered: bool) -> void:
	if _hover_material != null:
		_hover_material.set_shader_parameter("hover_amount", 1.0 if hovered else 0.0)
	if _tooltip != null:
		_tooltip.visible = hovered or _sprite.texture == null


## 查询原版绿色晕染材质是否已启用，供表现回归测试使用。
## 返回当前掉落物是否正在以完整强度显示发光。
func is_hover_glow_enabled() -> bool:
	if _hover_material == null:
		return false
	return is_equal_approx(float(_hover_material.get_shader_parameter("hover_amount")), 1.0)


## 读取地面掉落悬浮晕染的外扩半径，供原版参数回归测试使用。
## 返回着色器使用的像素半径。
func hover_glow_radius() -> float:
	if _hover_material == null:
		return 0.0
	return float(_hover_material.get_shader_parameter("glow_radius"))


## 读取 `local_hit_rect`，返回本视图使用的 ALE 原始本地命中矩形。
## 返回以权威脚点为原点的本地矩形。
func local_hit_rect() -> Rect2:
	return _local_hit_rect


## 只给仍在当前世界的同一掉落实例绑定异步纹理。
## [param visual] 已就绪的图标。[param requested_id] 请求时的实例身份。
func _apply_texture(visual: Dictionary, requested_id: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion() or requested_id != loot_id: return
	_sprite.texture = visual.get("texture") as Texture2D
	if _sprite.texture == null:
		var inventory := item.presentation_for("inventory")
		if not inventory.is_empty() and inventory != _presentation:
			_presentation = inventory
			SpriteResources.request(_presentation, _apply_texture.bind(loot_id))
		return
	_tooltip.visible = is_hover_glow_enabled()
	var native_size := _sprite.texture.get_size()
	if _sprite.texture is AtlasTexture:
		var atlas := _sprite.texture as AtlasTexture
		var page_size := atlas.atlas.get_size()
		_hover_material.set_shader_parameter("source_region", Vector4(atlas.region.position.x / page_size.x,
			atlas.region.position.y / page_size.y, atlas.region.size.x / page_size.x, atlas.region.size.y / page_size.y))
	var origin: Vector2 = visual.origin if _presentation.has("ale_reference") else -native_size * 0.5
	if _presentation.has("origin"):
		origin = Vector2(_presentation.origin[0], _presentation.origin[1])
	_sprite.position = origin
	_local_hit_rect = Rect2(origin, native_size)
	_tooltip.position = Vector2(origin.x + native_size.x + 6.0, origin.y - 2.0)
