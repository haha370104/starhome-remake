class_name ModernNavigationWindow
extends NavigationWindow

const GENERIC_FRAME := preload("res://assets/ui/windows/navigation/scene_players.png")
const BOLD_FONT := preload("res://assets/ui/fonts/NotoSansCJKsc-Bold.otf")


## 创建使用共享字体、深色底板和一致按钮状态的业务窗口。
## [param dimensions] 窗口尺寸。
## [param title_text] 窗口标题。
func build_modern_window(dimensions: Vector2, title_text: String) -> void:
	build_window(dimensions, null, "")
	theme.default_font_size = 12
	theme.set_color("font_color", "Label", Color("e4edf4"))
	theme.set_color("default_color", "RichTextLabel", Color("c3d0dc"))
	get_node("Background").hide()
	_build_frame(dimensions)
	var title := make_label(title_text, Rect2(20, 16, dimensions.x - 100, 28))
	title.add_theme_font_override("font", BOLD_FONT)
	title.add_theme_font_size_override("font_size", 18)


func _build_frame(dimensions: Vector2) -> void:
	var surface := Panel.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_theme_stylebox_override("panel", _frame_style("02070fE6", "000000", 0))
	add_child(surface)
	move_child(surface, 0)
	var outer := Panel.new()
	outer.position = Vector2(1, 2)
	outer.size = dimensions - Vector2(2, 4)
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer_style := _frame_style("02080c", "54d9f3", 1)
	outer_style.draw_center = false
	outer.add_theme_stylebox_override("panel", outer_style)
	add_child(outer)
	move_child(outer, 1)
	var inner := Panel.new()
	inner.position = Vector2(6, 9)
	inner.size = dimensions - Vector2(12, 14)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := _frame_style("02080c", "2f9bb4", 1)
	inner_style.draw_center = false
	inner.add_theme_stylebox_override("panel", inner_style)
	add_child(inner)
	move_child(inner, 2)
	var tab := TextureRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = GENERIC_FRAME
	atlas.region = Rect2(105, 0, 110, 11)
	tab.texture = atlas
	tab.position = Vector2((dimensions.x - 110) / 2.0, 0)
	tab.size = Vector2(110, 11)
	tab.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tab.stretch_mode = TextureRect.STRETCH_SCALE
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tab)
	move_child(tab, 3)


func _frame_style(fill: String, border: String, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(width)
	return style


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
