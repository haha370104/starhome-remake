class_name NavigationWindow
extends DraggableGameWindow

signal notice_requested(message: String)

const FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")


## 配置导航窗口的固定尺寸、原版背景与统一字体。
## [param dimensions] 窗口像素尺寸。
## [param background] 受控业务路径的原版背景。
## [param title] 窗口标题；为空时不叠加文字。
func build_window(dimensions: Vector2, background: Texture2D, title: String) -> void:
	configure(dimensions, background, Vector2(dimensions.x - 25, 15))
	var window_theme := Theme.new()
	window_theme.default_font = FONT
	window_theme.default_font_size = 12
	theme = window_theme
	if not title.is_empty():
		make_label(title, Rect2(20, 16, dimensions.x - 52, 20))


## 创建不阻止窗口拖动的文字标签。
## [param text] 显示文字。
## [param rect] 窗口内的位置与尺寸。
## 返回已挂接到内容层的标签。
func make_label(text: String, rect: Rect2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = rect.position
	label.size = rect.size
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_root.add_child(label)
	return label


## 创建独立可点击的文字按钮。
## [param text] 按钮文字。
## [param rect] 按钮在窗口内的位置与大小。
## [param callback] 按下时执行的语义动作。
## 返回可供调用方设置选中状态的按钮。
func make_button(text: String, rect: Rect2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = rect.position
	button.size = rect.size
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("14334a")
	normal.border_color = Color("4291a8")
	normal.set_border_width_all(1)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("28586e")
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", hover)
	button.pressed.connect(callback)
	content_root.add_child(button)
	return button


## 为尚未开放的操作显示明确提示，不调用收费、外链或退出游戏等实际业务。
## [param feature] 被点击的功能名称。
func unavailable(feature: String) -> void:
	notice_requested.emit("%s暂未实现" % feature)
