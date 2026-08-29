class_name GroundLootWorldView
extends Node2D

var loot_id := ""
var item_definition_id := ""
var quantity := 0
var _hover_background: Panel
var _sprite: Sprite2D
var _tooltip: Label
var _local_hit_rect := Rect2()


## 使用权威掉落快照与业务表现定义创建地面物品视图。
## [param presentation] 含语义化纹理、ALE 原始尺寸与原点的表现定义。
## [param snapshot] 含 loot_id、物品定义、数量与世界坐标的权威快照。
## 返回配置是否成功；未知纹理或非法尺寸返回对应 Error。
## 设计：节点脚点等于权威世界坐标，纹理严格按原客户端 ALE 原点以 1:1 像素绘制。
func configure(presentation: Dictionary, snapshot: Dictionary) -> Error:
	var texture_path := String(presentation.get("texture", ""))
	var native_size_value: Variant = presentation.get("native_size", [])
	var origin_value: Variant = presentation.get("origin", [])
	if (
		texture_path.is_empty()
		or not ResourceLoader.exists(texture_path)
		or not native_size_value is Array
		or (native_size_value as Array).size() != 2
		or not origin_value is Array
		or (origin_value as Array).size() != 2
	):
		return ERR_INVALID_DATA
	var native_size := Vector2(float(native_size_value[0]), float(native_size_value[1]))
	var origin := Vector2(float(origin_value[0]), float(origin_value[1]))
	if native_size.x <= 0.0 or native_size.y <= 0.0:
		return ERR_INVALID_DATA
	_hover_background = Panel.new()
	_hover_background.name = "HoverBackground"
	_hover_background.position = origin - Vector2(2.0, 2.0)
	_hover_background.size = native_size + Vector2(4.0, 4.0)
	_hover_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover_background.visible = false
	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.08, 0.34, 0.08, 0.48)
	hover_style.border_color = Color("33ff00")
	hover_style.set_border_width_all(1)
	_hover_background.add_theme_stylebox_override("panel", hover_style)
	add_child(_hover_background)
	_sprite = Sprite2D.new()
	_sprite.name = "WorldIcon"
	_sprite.texture = load(texture_path)
	_sprite.centered = false
	_sprite.position = origin
	add_child(_sprite)
	_local_hit_rect = Rect2(origin, native_size)
	_tooltip = Label.new()
	_tooltip.name = "HoverTooltip"
	_tooltip.position = Vector2(origin.x + native_size.x + 6.0, origin.y - 2.0)
	_tooltip.z_index = 100
	_tooltip.visible = false
	_tooltip.add_theme_font_size_override("font_size", 13)
	_tooltip.add_theme_color_override("font_color", Color(0.72, 1.0, 0.58))
	_tooltip.add_theme_color_override("font_shadow_color", Color.BLACK)
	_tooltip.add_theme_constant_override("shadow_offset_x", 1)
	_tooltip.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_tooltip)
	apply_snapshot(snapshot, String(presentation.get("display_name", item_definition_id)))
	return OK


## 应用同一掉落实例的最新权威位置、数量和提示文字。
## [param snapshot] 服务端地面掉落 DTO。
## [param display_name] 客户端语义目录提供的中文名称。
func apply_snapshot(snapshot: Dictionary, display_name: String) -> void:
	loot_id = String(snapshot.get("loot_id", loot_id))
	item_definition_id = String(snapshot.get("item_definition_id", item_definition_id))
	quantity = maxi(1, int(snapshot.get("quantity", quantity)))
	var point_value: Variant = snapshot.get("position", [])
	if point_value is Array and (point_value as Array).size() == 2:
		position = Vector2(float(point_value[0]), float(point_value[1]))
	if _tooltip != null:
		_tooltip.text = "%s × %d" % [display_name, quantity]


## 判断一个世界坐标是否落在原始 ALE 帧的真实矩形内。
## [param world_position] 鼠标对应的世界坐标。
## 返回该坐标是否命中当前掉落图像。
func contains_world_point(world_position: Vector2) -> bool:
	return visible and _local_hit_rect.has_point(to_local(world_position))


## 切换原客户端风格的地面物品悬浮反馈。
## [param hovered] 当前鼠标是否命中该掉落物。
func set_hovered(hovered: bool) -> void:
	if _hover_background != null:
		_hover_background.visible = hovered
	if _tooltip != null:
		_tooltip.visible = hovered


## 查询原版绿色发光语义对应的悬浮背景是否可见，供表现回归测试使用。
## 返回当前掉落物是否正在显示独立背景层。
func is_hover_background_visible() -> bool:
	return _hover_background != null and _hover_background.visible


## 读取 `local_hit_rect`，返回本视图使用的 ALE 原始本地命中矩形。
## 返回以权威脚点为原点的本地矩形。
func local_hit_rect() -> Rect2:
	return _local_hit_rect
