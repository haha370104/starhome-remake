class_name ModernNavigationWindow
extends NavigationWindow


## 创建使用共享字体、深色底板和一致按钮状态的业务窗口。
## [param dimensions] 窗口尺寸。
## [param title_text] 窗口标题。
func build_modern_window(dimensions: Vector2, title_text: String) -> void:
	build_window(dimensions, null, "")
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("e4edf4"))
	theme.set_color("default_color", "RichTextLabel", Color("c3d0dc"))
	get_node("Background").hide()
	get_node("CloseButton").hide()
	var surface := Panel.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface_style := _surface_style("111d29", "3c7286")
	surface_style.shadow_color = Color(0, 0, 0, 0.35)
	surface_style.shadow_size = 8
	surface.add_theme_stylebox_override("panel", surface_style)
	add_child(surface)
	move_child(surface, 0)
	var title := make_label(title_text, Rect2(20, 16, dimensions.x - 100, 28))
	title.add_theme_font_size_override("font_size", 20)
	_style_button(make_button("×", Rect2(dimensions.x - 50, 14, 30, 30), request_close))


## 创建日志内统一的圆角底板，保留文字与边框之间的留白。
## [param fill] 底色的十六进制字符串。
## [param border] 边框颜色的十六进制字符串。
## 返回供背景、列表和按钮复用的样式。
func _surface_style(fill: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## 配置日志按钮的悬停、选中与键盘焦点状态。
## [param button] 已挂接到日志窗口的按钮。
func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _surface_style("192c3b", "304b5e"))
	button.add_theme_stylebox_override("hover", _surface_style("27485a", "63c5d6"))
	button.add_theme_stylebox_override("pressed", _surface_style("28566a", "63c5d6"))
	button.add_theme_stylebox_override("hover_pressed", _surface_style("306578", "8edee8"))
	var focus := _surface_style("192c3b", "8edee8")
	focus.draw_center = false
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color("b9cbd8"))
	button.add_theme_color_override("font_pressed_color", Color("edfcff"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_hover_pressed_color", Color("ffffff"))
