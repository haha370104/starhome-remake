class_name DraggableGameWindow
extends Control

signal close_requested

const CLOSE_NORMAL := preload("res://assets/ui/windows/common/close/normal.png")
const CLOSE_HOVER := preload("res://assets/ui/windows/common/close/hover.png")
const CLOSE_PRESSED := preload("res://assets/ui/windows/common/close/pressed.png")

var content_root: Control
var _dragging := false
var _drag_offset := Vector2.ZERO
var _header_height := 38.0


## 创建保持原始像素尺寸的可拖动游戏窗口。
## [param window_size] 背景和交互区域尺寸。
## [param background_texture] 对应荣耀版面板背景。
## [param close_position] 关闭按钮左上角位置。
## 设计：本基类只管理窗口生命周期、拖动、置顶与视口约束，不理解任何业务状态。
func configure(window_size: Vector2, background_texture: Texture2D, close_position: Vector2) -> void:
	custom_minimum_size = window_size
	size = window_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_window_gui_input)

	var background := TextureRect.new()
	background.name = "Background"
	background.texture = background_texture
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	content_root = Control.new()
	content_root.name = "Content"
	content_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content_root)

	var close_button := TextureButton.new()
	close_button.name = "CloseButton"
	close_button.texture_normal = CLOSE_NORMAL
	close_button.texture_hover = CLOSE_HOVER
	close_button.texture_pressed = CLOSE_PRESSED
	close_button.position = close_position
	close_button.size = Vector2(17, 17)
	close_button.ignore_texture_size = true
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(request_close)
	add_child(close_button)


## 通过统一关闭意图结束窗口，供关闭按钮和窗口管理器复用。
func request_close() -> void:
	if visible:
		close_requested.emit()


## 将窗口中心限制在当前 HUD 可见区域内。
## [param viewport_size] 当前根视口像素尺寸。
func clamp_to_viewport(viewport_size: Vector2) -> void:
	position.x = clampf(position.x, 0.0, maxf(0.0, viewport_size.x - size.x))
	position.y = clampf(position.y, 0.0, maxf(0.0, viewport_size.y - size.y))


## 处理标题区域拖动及点击置顶。
## [param event] Godot GUI 输入事件。
func _on_window_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			move_to_front()
			if event.position.y <= _header_height:
				_dragging = true
				_drag_offset = event.position
		else:
			_dragging = false
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		position += event.relative
		clamp_to_viewport(get_viewport_rect().size)
		accept_event()
