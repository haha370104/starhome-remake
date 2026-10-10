class_name PlayerLoginScreen
extends CanvasLayer

signal login_requested(include_llm: bool)

var _human_checkbox: CheckBox
var _llm_checkbox: CheckBox
var _login_button: Button
var _status_label: Label


## 创建进入游戏前的角色选择界面。
func _ready() -> void:
	layer = 2000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_view()


## 设置本地可选择的角色名称；普通玩家默认选中，LLM 玩家默认不选中。
func configure(human_name: String, llm_name: String) -> void:
	if _human_checkbox == null:
		return
	_human_checkbox.text = human_name
	_llm_checkbox.text = "%s (LLM)" % llm_name
	_human_checkbox.button_pressed = true
	_llm_checkbox.button_pressed = false


## 显示启动阶段，暂时锁定角色选择。
func set_busy(message: String) -> void:
	_human_checkbox.disabled = true
	_llm_checkbox.disabled = true
	_login_button.disabled = true
	_status_label.text = message


## 恢复可操作状态并显示失败原因。
func show_error(message: String) -> void:
	_human_checkbox.disabled = false
	_llm_checkbox.disabled = false
	_login_button.disabled = false
	_status_label.text = message


## 登录按钮必须至少保留一个人类玩家；当前客户端只承载一个本地人类会话。
func _on_login_pressed() -> void:
	if not _human_checkbox.button_pressed:
		_status_label.text = "当前客户端至少需要选择一名人类玩家"
		return
	login_requested.emit(_llm_checkbox.button_pressed)


## 以代码构造不依赖地图资源的登录界面。
func _build_view() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color("071116")
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(480.0, 300.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("101f28")
	panel_style.border_color = Color("19d8ff")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 32.0
	panel_style.content_margin_right = 32.0
	panel_style.content_margin_top = 26.0
	panel_style.content_margin_bottom = 26.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)

	var title := Label.new()
	title.text = "星际家园复刻版"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("55eaff"))
	content.add_child(title)

	var prompt := Label.new()
	prompt.text = "选择本次上线的玩家"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 18)
	prompt.add_theme_color_override("font_color", Color("d9f8ff"))
	content.add_child(prompt)

	_human_checkbox = _make_player_row(content, "玩家1", true)
	_llm_checkbox = _make_player_row(content, "Riko (LLM)", false)

	_login_button = Button.new()
	_login_button.text = "登录"
	_login_button.custom_minimum_size = Vector2(0.0, 42.0)
	_login_button.pressed.connect(_on_login_pressed)
	content.add_child(_login_button)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_color_override("font_color", Color("ffd28a"))
	content.add_child(_status_label)


func _make_player_row(parent: VBoxContainer, label_text: String, checked: bool) -> CheckBox:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0.0, 34.0)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 18)
	row.add_child(label)
	var checkbox := CheckBox.new()
	checkbox.button_pressed = checked
	row.add_child(checkbox)
	return checkbox
