class_name FrameRateDisplay
extends Label

var _timer := Timer.new()


## 创建不拦截输入的低频读数，默认关闭时没有逐帧工作。
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 14)
	add_theme_color_override("font_outline_color", Color.BLACK)
	add_theme_constant_override("outline_size", 4)
	_timer.wait_time = 0.5
	_timer.timeout.connect(_refresh)
	add_child(_timer)
	set_enabled(false)


## 开关显示并同步计时器，不改变游戏帧率限制。
## [param enabled] 是否显示性能读数。
func set_enabled(enabled: bool) -> void:
	visible = enabled
	if enabled:
		_refresh()
		_timer.start()
	else:
		_timer.stop()


## 读取引擎现有帧率统计，避免在展示层采集额外每帧数据。
func _refresh() -> void:
	text = "FPS  %d" % Engine.get_frames_per_second()
