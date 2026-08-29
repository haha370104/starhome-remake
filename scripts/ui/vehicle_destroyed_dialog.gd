class_name VehicleDestroyedDialog
extends PanelContainer

signal wait_selected
signal return_to_base_requested

const DESTROYED_TEXT := "你已经被击毁，你可以选择"

var message_label: Label
var wait_button: Button
var or_label: Label
var return_button: Button
var countdown_label: Label
var _remaining_seconds := 0.0


## 创建荣耀版死亡窗的两项选择，并保持在任意窗口尺寸的中央。
func configure() -> void:
	name = "VehicleDestroyedDialog"
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -150.0
	offset_right = 150.0
	offset_top = -95.0
	offset_bottom = 95.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", _panel_style())
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)
	message_label = Label.new()
	message_label.text = DESTROYED_TEXT
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 18)
	message_label.add_theme_color_override("font_color", Color.WHITE)
	column.add_child(message_label)
	wait_button = _choice_button("原地等待其他玩家营救")
	wait_button.pressed.connect(_select_wait)
	column.add_child(wait_button)
	or_label = Label.new()
	or_label.text = "或"
	or_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	or_label.add_theme_font_size_override("font_size", 14)
	or_label.add_theme_color_override("font_color", Color("b8cbd5"))
	column.add_child(or_label)
	return_button = _choice_button("返回基地中心")
	return_button.pressed.connect(_select_return_to_base)
	column.add_child(return_button)
	countdown_label = Label.new()
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.add_theme_font_size_override("font_size", 15)
	countdown_label.add_theme_color_override("font_color", Color("7de8ff"))
	column.add_child(countdown_label)
	hide_dialog()


## 在生命首次降到零时显示完整选择。
func show_destroyed() -> void:
	_remaining_seconds = 0.0
	countdown_label.text = ""
	wait_button.disabled = false
	return_button.disabled = false
	visible = true


## 显示服务器已接受的三秒基地救援倒计时。
func show_recovery_scheduled(delay_seconds: float) -> void:
	_remaining_seconds = maxf(delay_seconds, 0.0)
	wait_button.disabled = true
	return_button.disabled = true
	visible = true
	_update_countdown_text()


## 结束死亡态并清空倒计时。
func hide_dialog() -> void:
	_remaining_seconds = 0.0
	visible = false


## 按渲染帧更新提示文字；实际传送时刻仍只接受服务器消息。
func _process(delta: float) -> void:
	if not visible or _remaining_seconds <= 0.0:
		return
	_remaining_seconds = maxf(0.0, _remaining_seconds - delta)
	_update_countdown_text()


## 选择原地等待后关闭窗口；击毁状态与半透明表现继续保留。
func _select_wait() -> void:
	hide_dialog()
	wait_selected.emit()


## 请求基地救援并立即锁定按钮，等待服务器确认具体时刻。
func _select_return_to_base() -> void:
	wait_button.disabled = true
	return_button.disabled = true
	countdown_label.text = "正在呼叫基地救援…"
	return_to_base_requested.emit()


## 恢复一次被服务器拒绝的选择，让玩家能够重试或继续等待。
func show_recovery_failed(message: String) -> void:
	_remaining_seconds = 0.0
	countdown_label.text = message
	wait_button.disabled = false
	return_button.disabled = false
	visible = true


## 更新仅用于表现的向上取整秒数。
func _update_countdown_text() -> void:
	countdown_label.text = "基地救援将在 %d 秒后抵达" % ceili(_remaining_seconds)


## 创建一项与旧客户端文字按钮相近的高亮按钮。
func _choice_button(text_value: String) -> Button:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(0, 34)
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Color("72dfff"))
	button.add_theme_color_override("font_hover_color", Color("fff36c"))
	return button


## 创建中央提示窗的深蓝底和青色描边。
func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0a1826e8")
	style.border_color = Color("35cceb")
	style.set_border_width_all(2)
	style.set_corner_radius_all(5)
	return style
