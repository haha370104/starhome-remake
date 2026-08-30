class_name MonsterWorldView
extends Node2D

const CombatVisualPresenterScript := preload("res://scripts/client/presentation/combat/combat_visual_presenter.gd")
const ProjectileSweep := preload("res://scripts/domain/combat/projectile_sweep.gd")
const WorldCombatStatusBarScript := preload("res://scripts/client/presentation/combat/world_combat_status_bar.gd")

const NAME_LABEL_SIZE := Vector2(100.0, 18.0)
const HEALTH_BAR_OFFSET := Vector2(0.0, 10.0)
const NAME_TO_HEALTH_GAP := 2.0

var entity_id := ""
var combat_actor_id := ""
var presenter: CombatVisualPresenter
var name_label: Label
var health_bar: WorldCombatStatusBar
var visual_collision_offset := Vector2.ZERO
var visual_collision_radius := 24.0
var _last_action_sequence := -1


## 执行 `configure` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(manifest: Dictionary, snapshot: Dictionary) -> Error:
	entity_id = String(snapshot["entity_id"])
	combat_actor_id = String(snapshot["combat_actor_id"])
	presenter = CombatVisualPresenterScript.new()
	add_child(presenter)
	var error := presenter.configure(manifest)
	if error != OK:
		return error
	error = presenter.present_actor(StringName(combat_actor_id))
	if error != OK:
		return error
	var actor_value: Variant = (manifest.get("actors", {}) as Dictionary).get(
		String(snapshot["combat_actor_id"]), {}
	)
	if actor_value is Dictionary:
		var collision: Dictionary = (actor_value as Dictionary).get("visual_collision", {})
		var offset_value: Variant = collision.get("offset", [0, -24])
		if offset_value is Array and (offset_value as Array).size() == 2:
			visual_collision_offset = Vector2(float(offset_value[0]), float(offset_value[1]))
		visual_collision_radius = maxf(4.0, float(collision.get("radius", 24.0)))
	name_label = Label.new()
	name_label.name = "HoverName"
	name_label.size = NAME_LABEL_SIZE
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color.RED)
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	name_label.add_theme_constant_override("shadow_offset_x", 1)
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	var name_height := maxf(NAME_LABEL_SIZE.y, name_label.get_combined_minimum_size().y)
	name_label.size = Vector2(NAME_LABEL_SIZE.x, name_height)
	name_label.position = Vector2(
		-NAME_LABEL_SIZE.x * 0.5,
		HEALTH_BAR_OFFSET.y - name_height - NAME_TO_HEALTH_GAP,
	)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.z_index = 21
	name_label.visible = false
	add_child(name_label)
	health_bar = WorldCombatStatusBarScript.new()
	health_bar.configure(58.0, false, HEALTH_BAR_OFFSET)
	add_child(health_bar)
	apply_snapshot(snapshot)
	return OK


## 执行 `apply_snapshot` 对应的模块操作。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func apply_snapshot(snapshot: Dictionary) -> void:
	var point: Array = snapshot["position"]
	position = Vector2(float(point[0]), float(point[1]))
	visible = bool(snapshot["alive"])
	name_label.text = String(snapshot["display_name"])
	health_bar.set_health(float(snapshot["health"]), float(snapshot["max_health"]))
	presenter.set_direction(int(snapshot["facing_index"]))
	var action := StringName(snapshot["action"])
	var action_sequence := int(snapshot.get("action_sequence", 0))
	if action != presenter.current_action_id or action_sequence != _last_action_sequence:
		presenter.set_action(action)
		_last_action_sequence = action_sequence


## 按渲染帧推进当前节点的表现状态。
## [param delta] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func _process(delta: float) -> void:
	if presenter != null and visible:
		presenter.advance(delta)


## 执行 `is_selectable_at` 对应的模块操作。
## [param world_position] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param radius] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func is_selectable_at(world_position: Vector2, radius: float) -> bool:
	return visible and position.distance_to(world_position) <= radius


## 判断世界坐标是否落在怪物本体的悬浮命中区域内。
## [param world_position] 鼠标对应的世界坐标。
## 返回坐标是否命中由表现清单定义的怪物本体圆形区域。
## 设计：悬浮与弹体预碰撞共用同一份表现几何，避免为每种怪物另写热点补丁。
func is_hovered_at(world_position: Vector2) -> bool:
	if not visible:
		return false
	var collision_center := position + visual_collision_offset
	return collision_center.distance_squared_to(world_position) <= visual_collision_radius ** 2


## 切换原客户端式怪物悬浮名称显示状态。
## [param hovered] 当前怪物是否是唯一的鼠标悬浮目标。
func set_hovered(hovered: bool) -> void:
	if name_label != null:
		name_label.visible = hovered and visible


## 执行 `visual_segment_collision` 对应的模块操作。
## [param segment_start] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param segment_end] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
## 设计：该几何只用于提前结束客户端弹体，不参与伤害、命中或服务端状态预测。
func visual_segment_collision(segment_start: Vector2, segment_end: Vector2) -> Dictionary:
	if not visible:
		return {"hit": false}
	var center := position + visual_collision_offset
	var result := ProjectileSweep.segment_circle_intersection(
		segment_start, segment_end, center, visual_collision_radius
	)
	if bool(result.get("hit", false)):
		result["entity_id"] = entity_id
		result["monster_view_position"] = position
		result["collision_center"] = center
		result["collision_radius"] = visual_collision_radius
	return result
