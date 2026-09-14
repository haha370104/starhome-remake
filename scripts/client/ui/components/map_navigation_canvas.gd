class_name MapNavigationCanvas
extends Control

signal destination_requested(world_position: Vector2)

var map_texture: Texture2D
var world_size := Vector2.ONE
var player_position := Vector2.ZERO
var points: Array[MapNavigationPoint] = []
var selected_position := Vector2.INF


## 启用独立地图输入，所有地图点击由 GUI 消费，避免穿透为世界攻击或移动。
func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "左键点击地图，自动寻路"
	resized.connect(queue_redraw)


## 查询等比缩放后的地图矩形，绘制与点击共用同一投影。
## 返回留出内边距的图片区域。
func image_rect() -> Rect2:
	return MapProjection.fit(map_texture.get_size(), Rect2(Vector2(10, 10), size - Vector2(20, 20))) \
		if map_texture != null else Rect2()


## 消费鼠标点击，仅左键按下且命中真实底图时发出世界坐标。
## [param event] 当前控件局部输入。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		accept_event()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var target := MapProjection.to_world(event.position, image_rect(), world_size)
			if target.is_finite():
				selected_position = target
				queue_redraw()
				destination_requested.emit(target)


## 绘制地图、当前玩家及兴趣点；位置始终来自世界坐标快照。
func _draw() -> void:
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	var rect := image_rect()
	if not rect.has_area():
		return
	draw_texture_rect(map_texture, rect, false)
	for point: MapNavigationPoint in points:
		var location := rect.position + point.position / world_size * rect.size
		var color := Color("78d9f4") if point.category == "传送点" else Color("e9c77b")
		draw_circle(location, 4, Color("101b28"))
		draw_circle(location, 2.5, color)
	if selected_position.is_finite():
		var target := rect.position + selected_position / world_size * rect.size
		draw_arc(target, 7, 0, TAU, 24, Color("ffdf86"), 2, true)
	var player := rect.position + player_position / world_size * rect.size
	draw_circle(player, 6, Color("10291e"))
	draw_circle(player, 4, Color("71f3a0"))


## 创建地图背景与边框样式。
## 返回不影响地图投影区域的底板。
func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("0b141f")
	style.border_color = Color("304b5e")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style
