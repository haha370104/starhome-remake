class_name LegacyItemTooltip
extends PanelContainer

const REGULAR_FONT := preload("res://assets/ui/fonts/legacy_panel_font.tres")
const BOLD_FONT := preload("res://assets/ui/fonts/legacy_panel_bold_font.tres")
const FONT_SIZE := 12
const CONTENT_WIDTH := 218.0

var _title_label: Label
var _body_label: Label


## 创建接近荣耀 MiniFormStyle 的物品复杂说明窗。
func _init() -> void:
	name = "LegacyItemTooltip"
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 4096
	custom_minimum_size = Vector2(CONTENT_WIDTH + 16.0, 0.0)
	add_theme_stylebox_override("panel", _panel_style())

	var content := VBoxContainer.new()
	content.name = "Content"
	content.custom_minimum_size = Vector2(CONTENT_WIDTH, 0.0)
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)

	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.add_theme_font_override("font", BOLD_FONT)
	_title_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_title_label.add_theme_color_override("font_color", Color.WHITE)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_title_label)

	_body_label = Label.new()
	_body_label.name = "Body"
	_body_label.add_theme_font_override("font", REGULAR_FONT)
	_body_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_body_label.add_theme_color_override("font_color", Color.WHITE)
	_body_label.add_theme_constant_override("line_spacing", 1)
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_body_label)


## 更新物品说明内容，首行使用原版 SETFONT2 粗体标题。
## [param text] TooltipFormatter 生成的多行说明。
func set_content(text: String) -> void:
	var line_break := text.find("\n")
	if line_break < 0:
		_title_label.text = text
		_body_label.text = ""
		_body_label.visible = false
	else:
		_title_label.text = text.left(line_break)
		_body_label.text = text.substr(line_break + 1)
		_body_label.visible = true
	reset_size()


## 构造荣耀小窗的深蓝底、青蓝细边和轻阴影。
func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("00182de8")
	style.border_color = Color("2996c9")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 2
	style.corner_radius_top_right = 2
	style.corner_radius_bottom_left = 2
	style.corner_radius_bottom_right = 2
	style.content_margin_left = 8.0
	style.content_margin_top = 6.0
	style.content_margin_right = 8.0
	style.content_margin_bottom = 6.0
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.75)
	style.shadow_size = 3
	return style
