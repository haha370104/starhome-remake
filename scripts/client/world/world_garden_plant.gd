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
	_sprite.position = _offset
	_sprite.visible = false
	_material.shader = HOVER_SHADER
	_material.set_shader_parameter("glow_color", Color("33ff00"))
	_material.set_shader_parameter("glow_radius", 4.0)
	_material.set_shader_parameter("hover_amount", 0.0)
	_sprite.material = _material
	add_child(_sprite)
	_timer.one_shot = true
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	return true


## 果实实际图片附近接收点击，树干不会拦截移动。
## [param point] 鼠标世界坐标。
## 返回是否命中果实范围。
func hit_test(point: Vector2) -> bool:
	return Rect2(global_position + _offset - Vector2(23, 23), Vector2(46, 46)).has_point(point)


## 按服务端成熟状态提供语义动作，倒计时只控制本地展示。
## 返回共用 NPC 菜单需要的数据。
func get_interaction_data() -> Dictionary:
	var ripe := _known and _timer.is_stopped()
	return {"title": display_name, "body": "走近果树后可采摘" if ripe else "果实尚未成熟",
		"actions": [{"id": "harvest_garden", "label": "采摘"}] if ripe else []}


## 接入共用交互菜单的选中光晕。
## [param active] 是否选中当前果实。
func set_interaction_active(active: bool) -> void:
	_material.set_shader_parameter("hover_amount", 1.0 if active else 0.0)


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
