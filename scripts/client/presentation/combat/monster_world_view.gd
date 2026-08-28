class_name MonsterWorldView
extends Node2D

const CombatVisualPresenterScript := preload("res://scripts/client/presentation/combat/combat_visual_presenter.gd")

var entity_id := ""
var presenter: CombatVisualPresenter
var name_label: Label
var health_bar: ProgressBar


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
	name_label = Label.new()
	name_label.position = Vector2(-44, -88)
	name_label.size = Vector2(88, 18)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.45))
	name_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	add_child(name_label)
	health_bar = ProgressBar.new()
	health_bar.position = Vector2(-30, -69)
	health_bar.size = Vector2(60, 7)
	health_bar.show_percentage = false
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	health_bar.max_value = maxi(1, int(snapshot["max_health"]))
	health_bar.value = clampi(int(snapshot["health"]), 0, int(health_bar.max_value))
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
