class_name CentralSystemMessageFeed
extends Control

const HOLD_SECONDS := 1.5
const FLOAT_SECONDS := 1.0
const FLOAT_DISTANCE := 56.0

const ROW_GAP := 6.0
const HORIZONTAL_MARGIN := 24.0

class MessageEntry extends RefCounted:
	var label: Label
	var elapsed := 0.0

var _entries: Array[MessageEntry] = []
var _text_color := Color("fff36b")


## 调整现有与后续消息的文字颜色，不改变每条消息的排序和停留时间。
## [param value] 当前用户选择的通用提示颜色。
func set_text_color(value: Color) -> void:
	_text_color = value
	for entry in _entries: entry.label.add_theme_color_override("font_color", value)


## 初始化中央消息层；每条消息独立计时，不占用鼠标事件。
func configure() -> void:
	name = "CentralSystemMessageFeed"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout_messages)
	set_process(false)


## 立即展示新消息并按接收顺序向上排开旧消息，无需等待已有消息消失。
## [param message] 需要展示的非空中文系统消息。
func show_message(message: String) -> void:
	if message.is_empty():
		return
	var entry := MessageEntry.new()
	entry.label = Label.new()
	entry.label.text = message
	entry.label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	entry.label.add_theme_font_size_override("font_size", 20)
	entry.label.add_theme_color_override("font_color", _text_color)
	entry.label.add_theme_color_override("font_outline_color", Color.BLACK)
	entry.label.add_theme_constant_override("outline_size", 2)
	entry.label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(entry.label)
	_entries.append(entry)
	_layout_messages()
	set_process(true)


## 根据帧间隔更新所有正在展示的消息。
## [param delta] 本帧经过的秒数。
func _process(delta: float) -> void:
	advance(delta)


## 独立推进每条消息的停留与淡出，到期立即释放，不向后续提示累积等待时间。
## [param delta] 需要推进的秒数，非正值不改变状态。
func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		entry.elapsed += delta
		if entry.elapsed >= HOLD_SECONDS + FLOAT_SECONDS:
			remove_child(entry.label)
			entry.label.queue_free()
			_entries.remove_at(index)
	_layout_messages()
	set_process(not _entries.is_empty())


## 查询当前展示的全部消息，供语义回归使用，不暴露内部控件。
## 返回按接收顺序排列的消息文本副本。
func displayed_messages() -> PackedStringArray:
	var messages := PackedStringArray()
	for entry: MessageEntry in _entries:
		messages.append(entry.label.text)
	return messages


## 查询当前是否存在正在展示的系统消息。
## 返回至少有一条活动消息时为真。
func is_presenting() -> bool:
	return not _entries.is_empty()


## 以最新消息位于视口中央为基准，从下往上排列旧消息并分别应用淡出。
## 设计：旧消息年龄不小于新消息，额外上浮不会压住下一条；换行高度参与间距计算。
func _layout_messages() -> void:
	var viewport_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	var width := maxf(1.0, viewport_size.x - HORIZONTAL_MARGIN * 2.0)
	var offset := 0.0
	for index in range(_entries.size() - 1, -1, -1):
		var entry := _entries[index]
		entry.label.size = Vector2(width, 0.0)
		var height := entry.label.get_minimum_size().y
		# 首次设置宽度后，Label 仍可能保留旧换行高度；同步收紧，保证第一帧也正确居中。
		entry.label.size.y = height
		var progress := clampf((entry.elapsed - HOLD_SECONDS) / FLOAT_SECONDS, 0.0, 1.0)
		if index == _entries.size() - 1:
			offset = height * 0.5
		else:
			offset += height
		entry.label.position = Vector2(HORIZONTAL_MARGIN,
			viewport_size.y * 0.5 - offset - FLOAT_DISTANCE * progress)
		entry.label.modulate.a = 1.0 - progress
		offset += ROW_GAP
