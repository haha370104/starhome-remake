class_name MapDestinationList
extends ScrollContainer

signal point_clicked(index: int)

var points: Array[MapNavigationPoint] = []
var rows: Array[Button] = []
var _column: VBoxContainer
var _group := ButtonGroup.new()


## 创建可滚动的双行目的地列表，名称与坐标分别排版。
func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = VBoxContainer.new()
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.add_theme_constant_override("separation", 3)
	add_child(_column)


## 更新坐标；实体集合不变时保留控件、键盘焦点、选中态和滚动位置。
## [param snapshot] 当前地图目的地快照。
func set_points(snapshot: Array[MapNavigationPoint]) -> void:
	var same_ids := snapshot.size() == points.size()
	if same_ids:
		for index in snapshot.size():
			if snapshot[index].id != points[index].id:
				same_ids = false
				break
	if not same_ids:
		for row: Button in rows:
			row.free()
		rows.clear()
		for index in snapshot.size():
			_build_row(index)
	points = snapshot
	for index in points.size():
		var point := points[index]
		var title := rows[index].get_node("Title") as Label
		var coordinates := rows[index].get_node("Coordinates") as Label
		title.text = point.label
		title.add_theme_color_override("font_color", Color("78d9f4") if point.category == "传送点" else Color("e9c77b"))
		coordinates.text = "%s  ·  (%d, %d)" % [point.category, point.position.x, point.position.y]
		rows[index].tooltip_text = "%s\n%s\n左键点击，自动前往" % [title.text, coordinates.text]


## 创建两行按钮；重复点击已选中按钮仍发布导航意图。
## [param index] 在目的地快照中的稳定行索引。
func _build_row(index: int) -> void:
	var row := Button.new()
	row.custom_minimum_size = Vector2(0, 58)
	row.toggle_mode = true
	row.button_group = _group
	row.pressed.connect(func() -> void: point_clicked.emit(index))
	for state: String in ["normal", "hover", "pressed", "hover_pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("192c3b") if state == "normal" else Color("28566a")
		style.border_color = Color("63c5d6")
		style.set_corner_radius_all(3)
		if state == "focus":
			style.draw_center = false
			style.set_border_width_all(1)
		row.add_theme_stylebox_override(state, style)
	_column.add_child(row)
	for line in 2:
		var label := Label.new()
		label.name = "Title" if line == 0 else "Coordinates"
		label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
		label.offset_left = 10
		label.offset_right = -10
		label.offset_top = 5 + line * 25
		label.offset_bottom = 30 + line * 25
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if line == 1:
			label.add_theme_font_size_override("font_size", 14)
			label.add_theme_color_override("font_color", Color("a7bacb"))
		row.add_child(label)
	rows.append(row)
