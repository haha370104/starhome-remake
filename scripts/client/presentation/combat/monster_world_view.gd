class_name MonsterWorldView
extends Node2D

const CombatVisualPresenterScript := preload("res://scripts/client/presentation/combat/combat_visual_presenter.gd")
const WorldCombatStatusBarScript := preload("res://scripts/client/presentation/combat/world_combat_status_bar.gd")

var entity_id := ""
var presenter: CombatVisualPresenter
var name_label: Label
var health_bar: WorldCombatStatusBar
var visual_collision_offset := Vector2.ZERO
var visual_collision_radius := 24.0


## Configures this view from [param manifest] and one authoritative [param snapshot].
## [param manifest] Business combat visual manifest containing the declared monster actor.
## [param snapshot] Validated public monster snapshot from the authority boundary.
## Returns `OK` after all presentation children are ready, otherwise a resource/data error.
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


## Applies one authoritative [param snapshot] to position, pose and combat bars.
## [param snapshot] Validated state for this exact monster identity.
func apply_snapshot(snapshot: Dictionary) -> void:
	var point: Array = snapshot["position"]
	position = Vector2(float(point[0]), float(point[1]))
	visible = bool(snapshot["alive"])
	name_label.text = String(snapshot["display_name"])
	health_bar.set_health(float(snapshot["health"]), float(snapshot["max_health"]))
	presenter.set_direction(int(snapshot["facing_index"]))
	presenter.set_action(StringName(snapshot["action"]))


## Advances animation presentation by [param delta].
## [param delta] Frame time in seconds; combat state itself is never simulated here.
func _process(delta: float) -> void:
	if presenter != null and visible:
		presenter.advance(delta)


## Reports whether [param world_position] lies within [param radius] of the monster foot point.
## [param world_position] World click coordinate used only for target selection.
## [param radius] Maximum client-side selection distance in pixels.
## Returns true only for a visible living presentation.
func is_selectable_at(world_position: Vector2, radius: float) -> bool:
	return visible and position.distance_to(world_position) <= radius


## 检测世界线段 [param segment_start] 到 [param segment_end] 是否穿过怪物表现圆。
## Returns 命中时返回最早参数 `t` 和视觉碰撞点，否则返回 `hit=false`。
## Design: 该几何只用于提前结束客户端弹体，不参与伤害、命中或服务端状态预测。
func visual_segment_collision(segment_start: Vector2, segment_end: Vector2) -> Dictionary:
	if not visible:
		return {"hit": false}
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.000001:
		return {"hit": false}
	var center := position + visual_collision_offset
	var relative_start := segment_start - center
	var radius_squared := visual_collision_radius * visual_collision_radius
	if relative_start.length_squared() <= radius_squared:
		return {"hit": true, "t": 0.0, "position": segment_start, "entity_id": entity_id}
	var half_linear := relative_start.dot(segment)
	var discriminant := half_linear * half_linear - length_squared * (
		relative_start.length_squared() - radius_squared
	)
	if discriminant < 0.0:
		return {"hit": false}
	var first_t := (-half_linear - sqrt(discriminant)) / length_squared
	if first_t < 0.0 or first_t > 1.0:
		return {"hit": false}
	return {
		"hit": true,
		"t": first_t,
		"position": segment_start + segment * first_t,
		"entity_id": entity_id,
	}
