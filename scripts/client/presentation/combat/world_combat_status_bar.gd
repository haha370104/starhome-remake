class_name WorldCombatStatusBar
extends Node2D

var _bar_width := 58.0
var _show_energy := false
var _health_ratio := 1.0
var _energy_ratio := 1.0


## 配置脚点下方状态条的 [param width]、[param show_energy] 与本地 [param offset]。
## Design: 使用 CanvasItem 绘制替代带主题背景的 ProgressBar，避免旧白色控件遮住怪物。
func configure(width: float, show_energy: bool, offset: Vector2) -> void:
	_bar_width = maxf(width, 12.0)
	_show_energy = show_energy
	position = offset
	z_index = 20
	queue_redraw()


## 按 [param current] / [param maximum] 更新生命比例。
func set_health(current: float, maximum: float) -> void:
	_health_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	queue_redraw()


## 按 [param current] / [param maximum] 更新当前能量比例。
func set_energy(current: float, maximum: float) -> void:
	_energy_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	queue_redraw()


## 绘制黑色边框、红色生命条，以及战车专用蓝色能量条。
func _draw() -> void:
	_draw_bar(0.0, _health_ratio, Color(0.92, 0.08, 0.08))
	if _show_energy:
		_draw_bar(6.0, _energy_ratio, Color(0.05, 0.52, 1.0))


## 在本地纵坐标 [param y] 绘制比例 [param ratio] 和颜色 [param color] 的单条状态。
func _draw_bar(y: float, ratio: float, color: Color) -> void:
	var outer := Rect2(-_bar_width * 0.5, y, _bar_width, 5.0)
	draw_rect(outer, Color(0.02, 0.02, 0.02, 0.95), true)
	draw_rect(Rect2(outer.position + Vector2.ONE, Vector2((_bar_width - 2.0) * ratio, 3.0)), color, true)
