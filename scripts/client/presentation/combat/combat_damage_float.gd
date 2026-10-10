class_name CombatDamageFloat
extends Node2D

var _release_callback: Callable
var _tween: Tween
var _label: Label


func set_release_callback(callback: Callable) -> void:
	_release_callback = callback


func reset_for_pool() -> void:
	_clear_presentation()
	modulate = Color.WHITE
	position = Vector2.ZERO


func _clear_presentation() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _label != null:
		_label.hide()


## 执行 `present` 对应的模块操作。
## [param damage] 调用方传入的参数；具体约束由函数签名和所在模块定义。
func present(damage: int) -> void:
	present_status("-%d" % maxi(0, damage), Color(1.0, 0.08, 0.08))


## 展示权威装备触发反馈，共用瞬时飘字生命周期。
## [param text] 数值或效果名称。[param color] 语义颜色。
func present_status(text: String, color: Color) -> void:
	_clear_presentation()
	modulate = Color.WHITE
	if _label == null:
		_label = Label.new()
		_label.size = Vector2(200, 24)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 18)
		_label.add_theme_color_override("font_shadow_color", Color.BLACK)
		_label.add_theme_constant_override("shadow_offset_x", 1)
		_label.add_theme_constant_override("shadow_offset_y", 1)
		add_child(_label)
	_label.text = text
	_label.position = Vector2(-100, -74)
	_label.modulate = Color.WHITE
	_label.add_theme_color_override("font_color", color)
	_label.show()
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(_label, "position:y", -112.0, 0.75)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.75).set_delay(0.18)
	_tween.set_parallel(false)
	_tween.tween_callback(_finish_presentation)


func _finish_presentation() -> void:
	_tween = null
	if _release_callback.is_valid():
		_release_callback.call(self)
	else:
		queue_free()
