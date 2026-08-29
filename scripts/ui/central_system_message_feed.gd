class_name CentralSystemMessageFeed
extends Control

const HOLD_SECONDS := 1.5
const FLOAT_SECONDS := 1.0
const FLOAT_DISTANCE := 56.0

var message_label: Label
var _queue: Array[String] = []
var _elapsed := 0.0
var _active := false


## 构建位于视口中央上方的系统消息标签并初始化队列状态。
func configure() -> void:
	name = "CentralSystemMessageFeed"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	message_label = Label.new()
	message_label.name = "Message"
	# 使用左上原点配合完整视口宽度计算，避免锚点偏移在窗口缩放后重复叠加。
	message_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	message_label.position = Vector2.ZERO
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 20)
	message_label.add_theme_color_override("font_color", Color("fff36b"))
	message_label.add_theme_color_override("font_outline_color", Color.BLACK)
	message_label.add_theme_constant_override("outline_size", 2)
	message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	message_label.visible = false
	add_child(message_label)
	resized.connect(_on_feed_resized)
	set_process(false)


## 将一条权威系统消息加入串行展示队列，保证消息不会彼此覆盖。
## [param message] 需要展示的非空中文系统消息。
func show_message(message: String) -> void:
	if message.is_empty():
		return
	_queue.append(message)
	if not _active:
		_begin_next_message()


## 按渲染帧推进当前系统消息的停留和上浮表现。
## [param delta] 本帧经过的秒数。
func _process(delta: float) -> void:
	advance(delta)


## 显式推进消息表现状态，供运行时和确定性无头测试共同使用。
## [param delta] 需要推进的秒数。
func advance(delta: float) -> void:
	if not _active or delta <= 0.0:
		return
	_elapsed += delta
	if _elapsed <= HOLD_SECONDS:
		_apply_progress(0.0)
		return
	var float_progress := (_elapsed - HOLD_SECONDS) / FLOAT_SECONDS
	_apply_progress(clampf(float_progress, 0.0, 1.0))
	if float_progress >= 1.0:
		_active = false
		_begin_next_message()


## 查询尚未开始展示的系统消息数量。
## 返回等待队列中的消息数量。
func queued_message_count() -> int:
	return _queue.size()


## 查询当前是否正在展示一条系统消息。
## 返回存在活动消息时为真。
func is_presenting() -> bool:
	return _active


## 从队列取出下一条消息并重置其停留与上浮状态。
func _begin_next_message() -> void:
	if _queue.is_empty():
		message_label.visible = false
		message_label.text = ""
		set_process(false)
		return
	_active = true
	_elapsed = 0.0
	message_label.text = _queue.pop_front()
	message_label.visible = true
	message_label.modulate = Color.WHITE
	_apply_progress(0.0)
	set_process(true)


## 根据归一化上浮进度更新标签位置和透明度。
## [param progress] 取值零到一的上浮淡出进度。
func _apply_progress(progress: float) -> void:
	var viewport_size := size if size.x > 0.0 and size.y > 0.0 else get_viewport_rect().size
	var label_height := message_label.get_minimum_size().y
	message_label.position = Vector2(
		0.0,
		viewport_size.y * 0.5 - label_height * 0.5
			- FLOAT_DISTANCE * progress,
	)
	message_label.size = Vector2(viewport_size.x, label_height)
	message_label.modulate.a = 1.0 - progress


## 在窗口尺寸变化后重新以屏幕正中心为基准排布当前系统提示。
func _on_feed_resized() -> void:
	if not _active:
		return
	var progress := clampf((_elapsed - HOLD_SECONDS) / FLOAT_SECONDS, 0.0, 1.0) \
		if _elapsed > HOLD_SECONDS else 0.0
	_apply_progress(progress)
