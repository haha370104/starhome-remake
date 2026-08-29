class_name InitialLoadingScreen
extends CanvasLayer

var _status_label: Label
var _elapsed_seconds := 0.0
var _base_message := "正在读取角色与地图数据"


## 创建覆盖整个游戏视口的启动加载画面，并保证其始终位于 HUD 与世界之上。
func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_view()
	show_loading(_base_message)


## 显示加载画面并更新当前初始化阶段文案。
## [param message] 不包含动态省略号的加载阶段说明。
func show_loading(message: String) -> void:
	_base_message = message if not message.is_empty() else "正在读取角色与地图数据"
	_elapsed_seconds = 0.0
	visible = true
	set_process(true)
	_update_status_text()


## 更新加载阶段说明，同时保留当前画面和省略号动画。
## [param message] 新的初始化阶段说明。
func set_status(message: String) -> void:
	if not message.is_empty():
		_base_message = message
	_update_status_text()


## 在首份权威角色与地图状态原子提交后关闭加载画面。
func finish_loading() -> void:
	visible = false
	set_process(false)


## 按帧推进加载文案的省略号动画，使连接或资源预载期间仍有明确反馈。
## [param delta] 自上一渲染帧以来经过的秒数。
func _process(delta: float) -> void:
	_elapsed_seconds += maxf(0.0, delta)
	_update_status_text()


## 以代码构造无业务素材依赖的全屏遮罩、标题和加载状态卡片。
## 设计：启动画面不得依赖尚未确定的初始地图，否则持久化地图恢复时仍会闪现错误场景。
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
	panel.custom_minimum_size = Vector2(420.0, 150.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color("101f28")
	panel_style.border_color = Color("19d8ff")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(6)
	panel_style.content_margin_left = 28.0
	panel_style.content_margin_right = 28.0
	panel_style.content_margin_top = 22.0
	panel_style.content_margin_bottom = 22.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var content := VBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 14)
	panel.add_child(content)

	var title := Label.new()
	title.text = "星际家园复刻版"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color("55eaff"))
	content.add_child(title)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 18)
	_status_label.add_theme_color_override("font_color", Color("d9f8ff"))
	content.add_child(_status_label)


## 根据经过时间生成 0 至 3 个循环省略号并刷新状态标签。
func _update_status_text() -> void:
	if _status_label == null:
		return
	var dot_count := int(floor(_elapsed_seconds * 2.0)) % 4
	_status_label.text = _base_message + ".".repeat(dot_count)
