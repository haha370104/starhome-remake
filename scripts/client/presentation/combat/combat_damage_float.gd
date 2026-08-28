class_name CombatDamageFloat
extends Node2D


## 执行 `present` 对应的模块操作。
## [param damage] 调用方传入的参数；具体约束由函数签名和所在模块定义。
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
