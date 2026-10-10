class_name WorldGardenPlant
extends Node2D

const HOVER_GLOW_SHADER := preload("res://scripts/client/presentation/combat/ground_loot_hover_glow.gdshader")
const HOVER_GLOW_COLOR := Color("33ff00")
const HOVER_GLOW_RADIUS := 4.0
const HIT_SIZE := Vector2(38, 38)

var plant_id := ""
var display_name := ""
var _fruit_offset := Vector2.ZERO
var _sprite: Sprite2D
var _hover_material: ShaderMaterial
var _timer: Timer
var _visual: Dictionary = {}


## 在已有树的脚点叠加原版果实图片，不重复绘制树。
## [param plant] 权威目录中的果实身份与树锚点。
## [param item_catalog] 与背包共用的物品表现定义。
## 返回贴图或身份无效时的具体错误。
func configure(plant: Dictionary, item_catalog: ItemCatalog) -> Error:
	if item_catalog == null: return ERR_INVALID_PARAMETER
	plant_id = String(plant.get("id", ""))
	var item: Dictionary = item_catalog.definition(String(plant.get("item_definition_id", "")))
	var visual: Dictionary = item.get("presentation", {}).get("world", {})
	var point: Variant = plant.get("position")
	var offset: Variant = plant.get("fruit_offset")
	if plant_id.is_empty() or visual.is_empty() or not point is Vector2 or not offset is Vector2:
		return ERR_INVALID_DATA
	display_name = String(item.get("display_name", ""))
	var variant := String(plant.get("fruit_variant", ""))
	_visual = visual.get("variants", {}).get(variant, {}) if not variant.is_empty() else visual
	if _visual.is_empty(): return ERR_INVALID_DATA
	position = point
	_fruit_offset = offset
	_sprite = Sprite2D.new()
	_sprite.position = _fruit_offset
	_sprite.visible = false
	_hover_material = ShaderMaterial.new()
	_hover_material.shader = HOVER_GLOW_SHADER
	_hover_material.set_shader_parameter("glow_color", HOVER_GLOW_COLOR)
	_hover_material.set_shader_parameter("glow_radius", HOVER_GLOW_RADIUS)
	_hover_material.set_shader_parameter("hover_amount", 0.0)
	_sprite.material = _hover_material
	add_child(_sprite)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_finish_regrowth)
	add_child(_timer)
	return OK


## 节点入树后请求果实纹理，防止缓存命中回调早于节点暂存完成。
func _ready() -> void:
	SpriteResources.request(_visual, _apply_texture)


## 用果实实际绘制区附近的固定区域接收点击。
## [param world_position] 当前鼠标的世界坐标。
## 返回是否点中这棵树上的果实。
func hit_test(world_position: Vector2) -> bool:
	return Rect2(global_position + _fruit_offset - HIT_SIZE * 0.5, HIT_SIZE).grow(HOVER_GLOW_RADIUS).has_point(world_position)


## 返回当前是否已成熟且允许提交一次采摘意图。
func is_harvestable() -> bool:
	return _timer != null and _timer.is_stopped()


## 按成熟状态提供与其他世界实体共用的交互菜单。
## 返回当前可用动作。
func get_interaction_data() -> Dictionary:
	if not is_harvestable():
		return {"title": display_name, "body": "果实尚未成熟", "actions": []}
	return {"title": display_name, "body": "", "actions": [{"id": "harvest_garden", "label": "采摘"}]}


## 兼容旧交互接口并切换果实悬停反馈，不改动权威成熟状态。
## [param active] 是否处于当前交互状态。
func set_interaction_active(active: bool) -> void:
	set_hovered(active)


## 切换成熟果实的原版绿色悬停光晕。
## [param hovered] 当前鼠标是否命中果实。
func set_hovered(hovered: bool) -> void:
	if _hover_material != null:
		_hover_material.set_shader_parameter("hover_amount", 1.0 if hovered else 0.0)


## 应用服务端返回的剩余生长时间；本地计时仅决定显示。
## [param remaining_seconds] 服务端权威剩余秒数。
func apply_regrowth(remaining_seconds: int) -> void:
	_timer.stop()
	if remaining_seconds > 0: _timer.start(remaining_seconds)
	_update_color()


## 对未知交互动作给出明确提示。
## [param _action_id] 未处理的动作标识。
## 返回玩家提示。
func handle_action(_action_id: String) -> String:
	return "请选择采摘"


## 原版果实图像异步就绪后绑定到仍有效的当前节点。
## [param visual] 共享资源队列返回的贴图。
func _apply_texture(visual: Dictionary) -> void:
	if not is_inside_tree() or is_queued_for_deletion(): return
	_sprite.texture = visual.get("texture") as Texture2D
	_sprite.visible = _sprite.texture != null


## 本地成熟倒计时结束时恢复可采摘外观，最终结算仍由服务端确认。
func _finish_regrowth() -> void:
	_update_color()


## 反映生长状态，保留果实的原始颜色。
func _update_color() -> void:
	if _sprite == null: return
	_sprite.modulate = Color(0.65, 0.65, 0.65, 0.8) if not is_harvestable() else Color.WHITE
