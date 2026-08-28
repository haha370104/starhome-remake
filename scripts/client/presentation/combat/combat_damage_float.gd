class_name CombatDamageFloat
extends Node2D


## 显示红色 [param damage] 扣血值并向上淡出，结束后自动释放节点。
func present(damage: int) -> void:
	var label := Label.new()
	label.text = "-%d" % maxi(0, damage)
	label.position = Vector2(-32, -74)
	label.size = Vector2(64, 24)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.08, 0.08))
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", -112.0, 0.75)
	tween.tween_property(label, "modulate:a", 0.0, 0.75).set_delay(0.18)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
