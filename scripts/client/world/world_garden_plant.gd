class_name WorldGardenPlant
extends Node2D

const HOVER_SHADER := preload("res://scripts/client/presentation/combat/ground_loot_hover_glow.gdshader")
var plant_id := ""
var display_name := ""
var _offset := Vector2.ZERO
var _sprite := Sprite2D.new()
var _timer := Timer.new()
var _known := false
var _material := ShaderMaterial.new()
var status_label := Label.new()
var _hovered := false
var _selected := false
var _fruit_bounds := Rect2()


## 为原场景树添加果实层，使用现有 ALE 资源仓储，不重复创建树木素材。
## [param plant] 配置中的树锚点。[param catalog] 当前客户端物品目录。
## 返回纹理与身份是否完整。
func configure(plant: BotanicalGardenCatalog.Plant, catalog: ItemCatalog) -> bool:
	plant_id = plant.id
	position = plant.position
	_offset = plant.fruit_offset
	var item := catalog.definition(plant.item_id)
	display_name = String(item.get("display_name", ""))
	var visual: Dictionary = item.get("presentation", {}).get("world", {})
	if not plant.variant.is_empty(): visual = visual.get("variants", {}).get(plant.variant, {})
	var resolved := ItemPresentationTextureResolver.resolve(visual)
	_sprite.texture = resolved.get("texture")
	if _sprite.texture == null: return false
	# fruit_offset 是原植物上的挂点；ALE 原点决定有效像素相对挂点的位置，不能把整帧居中。
	_sprite.centered = false
	_sprite.position = _offset + Vector2(resolved.get("origin", Vector2.ZERO))
	var fruit_rect := Rect2(_sprite.position, _sprite.texture.get_size())
	_fruit_bounds = fruit_rect.grow(4.0)
	_sprite.visible = false
	_material.shader = HOVER_SHADER
	_material.set_shader_parameter("glow_color", Color("33ff00"))
	_material.set_shader_parameter("glow_radius", 4.0)
	_material.set_shader_parameter("hover_amount", 0.0)
	if _sprite.texture is AtlasTexture:
		var atlas := _sprite.texture as AtlasTexture
		var page_size := atlas.atlas.get_size()
		_material.set_shader_parameter("source_region", Vector4(atlas.region.position.x / page_size.x,
			atlas.region.position.y / page_size.y, atlas.region.size.x / page_size.x, atlas.region.size.y / page_size.y))
	_sprite.material = _material
	add_child(_sprite)
	_timer.one_shot = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	status_label.position = Vector2(fruit_rect.get_center().x - 100, fruit_rect.position.y - 30)
	status_label.size = Vector2(200, 26)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status_label.add_theme_font_override("font", preload("res://assets/ui/fonts/legacy_panel_bold_font.tres"))
	status_label.add_theme_font_size_override("font_size", 14)
	status_label.add_theme_color_override("font_outline_color", Color.BLACK)
	status_label.add_theme_constant_override("outline_size", 3)
	status_label.z_index = 100
	add_child(status_label)
	_refresh()
	return true


## 果实图片与状态名称接收点击，装饰植物不会拦截移动。
## [param point] 鼠标世界坐标。
## 返回是否命中果实范围。
func hit_test(point: Vector2) -> bool:
	if not is_visible_in_tree(): return false
	return (_sprite.visible and _fruit_bounds.has_point(to_local(point))) \
		or status_label.get_global_rect().has_point(point)


## 按服务端成熟状态提供语义动作，倒计时只控制本地展示。
## 返回共用 NPC 菜单需要的数据。
func get_interaction_data() -> Dictionary:
	var ripe := _known and _timer.is_stopped()
	return {"title": display_name, "body": "走近果树后可采摘" if ripe else "果实尚未成熟",
		"actions": [{"id": "harvest_garden", "label": "采摘"}] if ripe else []}


## 接入共用交互菜单的选中光晕。
## [param active] 是否选中当前果实。
func set_interaction_active(active: bool) -> void:
	_selected = active
	_refresh_highlight()


## 鼠标悬浮与菜单选中分别持有高亮状态，关闭菜单不会消除仍在悬浮的提示。
## [param hovered] 鼠标是否命中当前果实或可见名称。
func set_hovered(hovered: bool) -> void:
	_hovered = hovered
	_refresh_highlight()


## 复用地面掉落物的绿色晕染；未成熟时只强调名称，不点亮不存在的果实。
func _refresh_highlight() -> void:
	var active := _hovered or _selected
	_material.set_shader_parameter("hover_amount", 1.0 if active and _sprite.visible else 0.0)
	status_label.modulate = Color.WHITE if active else Color(0.9, 0.9, 0.9)


## 应用权威再生状态，第一次查询前不显示可采摘果实。
## [param remaining] 服务器返回的剩余秒数。
func apply_regrowth(remaining: int) -> void:
	_known = true
	_timer.stop()
	if remaining > 0: _timer.start(remaining)
	_refresh()


## 仅切换果实显示；计时结束不能直接增加物品。
func _refresh() -> void:
	_sprite.visible = _known and _timer.is_stopped()
	var state := "可采摘" if _sprite.visible else ("生长中" if _known else "状态加载中")
	status_label.text = "%s · %s" % [display_name, state]
	status_label.add_theme_color_override("font_color", Color("b7ff80") if _sprite.visible else Color("c8c8c8"))
	_refresh_highlight()
