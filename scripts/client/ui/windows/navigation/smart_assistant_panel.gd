class_name SmartAssistantPanel
extends NavigationWindow

signal settings_changed(values: Dictionary)
var toggles: Dictionary[String, CheckButton] = {}
var threshold: HSlider
var threshold_label: Label
var status: Label


## 创建免费版智脑功能的复刻设置，所有开关默认关闭。
func _ready() -> void:
	build_window(Vector2(500, 370), null, "智脑系统")
	theme.default_font_size = 16
	var background := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101f2b")
	style.border_color = Color("43849a")
	style.set_border_width_all(2)
	background.add_theme_stylebox_override("panel", style)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	move_child(background, 0)
	var labels := {"enabled": "启用智脑", "auto_attack": "站定时自动攻击当前武器射程内的怪物",
		"auto_pickup": "自动拾取身边掉落物", "auto_repair": "低生命时自助维修（同 Z）"}
	var index := 0
	for key: String in labels:
		var toggle := CheckButton.new()
		toggle.text = labels[key]
		toggle.position = Vector2(24, 52 + index * 40)
		toggle.size = Vector2(450, 34)
		toggle.toggled.connect(func(_value: bool) -> void: _changed())
		content_root.add_child(toggle)
		toggles[key] = toggle
		index += 1
	threshold_label = make_label("自维修阈值：50%", Rect2(24, 224, 240, 26))
	threshold = HSlider.new()
	threshold.position = Vector2(250, 230)
	threshold.size = Vector2(220, 24)
	threshold.min_value = 10
	threshold.max_value = 90
	threshold.step = 10
	threshold.value = 50
	threshold.value_changed.connect(func(_value: float) -> void: _changed())
	content_root.add_child(threshold)
	status = make_label("未启用", Rect2(24, 276, 450, 26))
	make_label("设置自动保存；重新进入游戏后需手动启用。", Rect2(24, 318, 455, 24))


## 将保存的偏好投影到控件，避免初始化时反向写配置。
## [param values] 已规范化的用户偏好。
func apply_settings(values: Dictionary) -> void:
	for key: String in toggles:
		toggles[key].set_pressed_no_signal(bool(values.get(key, false)))
	threshold.set_value_no_signal(float(values.get("repair_threshold", 0.5)) * 100)
	threshold_label.text = "自维修阈值：%d%%" % int(threshold.value)


## 显示控制器提供的运行状态，不向外暴露文字控件的写入细节。
## [param message] 当前运行或暂停原因。
func show_status(message: String) -> void:
	status.text = message


## 发布用户设置并同步阈值文字。
func _changed() -> void:
	var values: Dictionary = {"repair_threshold": threshold.value / 100.0}
	for key: String in toggles:
		values[key] = toggles[key].button_pressed
	threshold_label.text = "自维修阈值：%d%%" % int(threshold.value)
	settings_changed.emit(values)
