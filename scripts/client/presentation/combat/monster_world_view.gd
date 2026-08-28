class_name MonsterWorldView
extends Node2D

const CombatVisualPresenterScript := preload("res://scripts/client/presentation/combat/combat_visual_presenter.gd")
const ProjectileSweep := preload("res://scripts/domain/combat/projectile_sweep.gd")
const WorldCombatStatusBarScript := preload("res://scripts/client/presentation/combat/world_combat_status_bar.gd")

var entity_id := ""
var presenter: CombatVisualPresenter
var name_label: Label
var health_bar: WorldCombatStatusBar
var visual_collision_offset := Vector2.ZERO
var visual_collision_radius := 24.0


## 执行 `configure` 对应的模块操作。
## [param manifest] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## [param snapshot] 调用方传入的参数；具体约束由函数签名和所在模块定义。
## 返回该函数计算、查询或操作得到的结果。
func configure(manifest: Dictionary, snapshot: Dictionary) -> Error:
	entity_id = String(snapshot["entity_id"])
	presenter = CombatVisualPresenterScript.new()
	add_child(presenter)
	var error := presenter.configure(manifest)
	if error != OK:
		return error
	error = presenter.present_actor(StringName(snapshot["combat_actor_id"]))
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
	name_label.position = Vector2(-44, -88)
	name_label.size = Vector2(88, 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(name_label)
	health_bar = WorldCombatStatusBarScript.new()
	health_bar.configure(58.0, false, Vector2(0, 10))
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
	presenter.set_action(StringName(snapshot["action"]))


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
	return result
