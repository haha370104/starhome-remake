class_name MapNavigationPanel
extends ModernNavigationWindow

signal navigation_requested(world_position: Vector2, point_id: StringName)
signal points_refresh_requested

var canvas: MapNavigationCanvas
var listing: MapDestinationList
var map_label: Label
var status: Label
var _points: Array[MapNavigationPoint] = []
var _refresh_timer: Timer


## 创建独立的当前地图窗口；只发布导航意图，不持有玩家或寻路服务。
func build() -> void:
	name = "MapNavigationPanel"
	build_modern_window(Vector2(900, 510), "当前地图")
	map_label = make_label("", Rect2(20, 54, 540, 26))
	map_label.add_theme_color_override("font_color", Color("a7bacb"))
	canvas = MapNavigationCanvas.new()
	canvas.position = Vector2(20, 90)
	canvas.size = Vector2(540, 350)
	canvas.destination_requested.connect(_on_map_destination)
	content_root.add_child(canvas)
	make_label("NPC / 设施 / 传送点", Rect2(580, 54, 300, 26))
	listing = MapDestinationList.new()
	listing.name = "Destinations"
	listing.position = Vector2(580, 90)
	listing.size = Vector2(300, 360)
	listing.add_theme_stylebox_override("panel", _surface_style("0b141f", "304b5e"))
	listing.point_clicked.connect(_on_point_clicked)
	content_root.add_child(listing)
	status = make_label("左键选择目的地 · Tab 关闭", Rect2(20, 478, 860, 24))
	status.add_theme_color_override("font_color", Color("a7bacb"))
	for item: Array in [["● 你的位置", "71f3a0"], ["● NPC / 设施", "e9c77b"], ["● 传送点", "78d9f4"]]:
		var legend := make_label(item[0], Rect2(20 + ["71f3a0", "e9c77b", "78d9f4"].find(item[1]) * 150, 447, 150, 26))
		legend.add_theme_color_override("font_color", Color(item[1]))
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 0.5
	_refresh_timer.timeout.connect(points_refresh_requested.emit)
	add_child(_refresh_timer)
	close_requested.connect(hide)
	visibility_changed.connect(_on_visibility_changed)
	hide()


## 替换当前地图底图并清除旧目的地，窗口保持当前开关状态。
## [param world_size] 当前世界像素尺寸。
## [param texture] 当前专用小地图。
## [param display_name] 当前地图名称。
func set_map(world_size: Vector2, texture: Texture2D, display_name: String) -> void:
	canvas.world_size = world_size.max(Vector2.ONE)
	canvas.map_texture = texture
	canvas.selected_position = Vector2.INF
	map_label.text = display_name
	set_points([])
	status.text = "左键选择目的地 · Tab 关闭"
	canvas.queue_redraw()


## 刷新巡逻实体的坐标，同时保留相同目的地列表的滚动位置和选择。
## [param points] 当前地图的类型化目的地快照。
func set_points(points: Array[MapNavigationPoint]) -> void:
	_points = points
	listing.set_points(points)
	canvas.points = points
	canvas.queue_redraw()


## 同步玩家位置与标记，无需重建地图控件。
## [param world_position] 当前世界像素坐标。
func update_player_position(world_position: Vector2) -> void:
	canvas.player_position = world_position
	canvas.queue_redraw()


## 拦截无修饰 Tab 切换窗口；编辑文字时保留输入控件的键盘行为。
## [param event] 视口输入，长按重复事件不切换面板。
func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo \
			or event.keycode != KEY_TAB or event.alt_pressed or event.ctrl_pressed \
			or event.meta_pressed or event.shift_pressed:
		return
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit or not content_root.is_inside_tree():
		return
	if visible:
		hide()
	else:
		position = (get_viewport_rect().size - size) / 2.0
		clamp_to_viewport(get_viewport_rect().size)
		show()
		move_to_front()
	get_viewport().set_input_as_handled()


## 仅在窗口可见时拉取实时 NPC 坐标，关闭后停止刷新。
func _on_visibility_changed() -> void:
	if is_visible_in_tree():
		points_refresh_requested.emit()
		_refresh_timer.start()
	else:
		_refresh_timer.stop()


## 将底图点击转换为普通位置导航，不隐式选择附近的传送目的地。
## [param world_position] 底图已经校验过的世界位置。
func _on_map_destination(world_position: Vector2) -> void:
	status.text = "已选择位置 (%d, %d) · Tab 关闭" % [world_position.x, world_position.y]
	navigation_requested.emit(world_position, &"")


## 单击列表即发布稳定目的地标识；重复点击同一项也能重新规划路线。
## [param index] 当前列表索引。
func _on_point_clicked(index: int) -> void:
	if index < 0 or index >= _points.size():
		return
	var point := _points[index]
	canvas.selected_position = point.position
	canvas.queue_redraw()
	status.text = "已选择：%s · Tab 关闭" % point.label
	navigation_requested.emit(point.destination, point.id)
