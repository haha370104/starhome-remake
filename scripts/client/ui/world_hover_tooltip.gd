class_name WorldHoverTooltip
extends Label

const REGULAR_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const CURSOR_OFFSET := Vector2(12.0, 18.0)


## 初始化接近 Windows 原生提示框的即时世界悬浮说明。
## 设计：矿物与传送点只负责提供文本和鼠标局部坐标，视觉规范由本组件统一维护。
func _init() -> void:
	name = "HoverTooltip"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 100
	add_theme_font_override("font", REGULAR_FONT)
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color("111111"))
	add_theme_stylebox_override("normal", _background_style())


## 更新提示内容，并按内容重新计算紧凑尺寸。
## [param value] 面向玩家显示的单行或多行说明文字。
func set_content(value: String) -> void:
	text = value
	reset_size()
	size = get_combined_minimum_size()


## 在鼠标附近显示提示，并避免提示自身盖住当前命中点。
## [param local_mouse_position] 鼠标相对于提示节点父级的局部坐标。
func show_near(local_mouse_position: Vector2) -> void:
	position = local_mouse_position + CURSOR_OFFSET
	visible = true


## 创建白底、灰色单像素边框的通用提示背景。
## 返回可供 Label normal 样式使用的 StyleBoxFlat。
static func _background_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("ffffe1")
	style.border_color = Color("767676")
	style.set_border_width_all(1)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	return style
