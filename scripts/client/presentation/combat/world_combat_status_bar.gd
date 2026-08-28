class_name WorldCombatStatusBar
extends Node2D

var _bar_width := 58.0
var _bar_height := 4.0
var _energy_offset_y := 4.0
var _show_energy := false
var _health_ratio := 1.0
var _energy_ratio := 1.0


## 配置生物脚点下方的旧客户端样式生命条及可选能量条。
## [param width] 两种条共用的像素宽度。
## [param show_energy] 是否在生命条下方绘制蓝色能量条。
## [param offset] 相对角色脚点的绘制偏移。
## 设计：使用 CanvasItem 绘制替代带主题背景的 ProgressBar，避免旧白色控件遮住怪物。
func configure(width: float, show_energy: bool, offset: Vector2) -> void:
	_bar_width = maxf(width, 12.0)
	_show_energy = show_energy
	position = offset
	z_index = 20
	queue_redraw()


## 根据当前值和上限更新生命比例并请求重绘。
## [param current] 当前生命值。
## [param maximum] 最大生命值。
func set_health(current: float, maximum: float) -> void:
	_health_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	queue_redraw()


## 根据当前值和上限更新能量比例并请求重绘。
## [param current] 当前工作能量。
## [param maximum] 工作能量上限。
func set_energy(current: float, maximum: float) -> void:
	_energy_ratio = clampf(current / maxf(maximum, 1.0), 0.0, 1.0)
	queue_redraw()


## 绘制黑色边框、红色生命条，以及战车专用蓝色能量条。
func _draw() -> void:
	_draw_bar(0.0, _health_ratio, Color(0.92, 0.08, 0.08))
	if _show_energy:
		_draw_bar(_energy_offset_y, _energy_ratio, Color(0.05, 0.52, 1.0))


## 绘制一条四像素高、带一像素黑边的状态条。
## [param y] 状态条相对节点的纵向起点。
## [param ratio] 已限制在零到一之间的填充比例。
## [param color] 状态条内部填充颜色。
func _draw_bar(y: float, ratio: float, color: Color) -> void:
	var outer := Rect2(-_bar_width * 0.5, y, _bar_width, _bar_height)
	draw_rect(outer, Color(0.02, 0.02, 0.02, 0.95), true)
	draw_rect(
		Rect2(outer.position + Vector2.ONE, Vector2((_bar_width - 2.0) * ratio, _bar_height - 2.0)),
		color,
		true,
	)
