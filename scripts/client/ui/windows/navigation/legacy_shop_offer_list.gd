class_name LegacyShopOfferList
extends Control

signal item_selected(index: int)

const ROW_HEIGHT := 27
const PAGE_ROWS := 12
var item_count: int:
	get: return _entries.size()
var _entries: Array[String] = []
var _selected := -1
var _first := 0


## 清空商品及选择，背景横线完全由原版素材绘制。
func clear() -> void:
	_entries.clear()
	_selected = -1
	_first = 0
	_rebuild()


## 加入一项商品显示文字，不创建额外底板或分隔线。
## [param text] 权威商品投影中的名称及价格。
func add_item(text: String) -> void:
	_entries.append(text)
	_rebuild()


## 更新程序选择，保持与现有商城调用约定一致。
## [param index] 商品索引。
func select(index: int) -> void:
	_selected = index
	_rebuild()


## 查询当前选择以构造购买意图。
## 返回零个或一个选中索引。
func get_selected_items() -> PackedInt32Array:
	return PackedInt32Array([_selected]) if _selected >= 0 else PackedInt32Array()


## 按原版27像素行距创建透明按钮，只在选中或悬停时显示单行反馈。
func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	for index in range(_first, mini(_first + PAGE_ROWS, _entries.size())):
		var row := Button.new()
		row.text = _entries[index]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.position = Vector2(0, (index - _first) * ROW_HEIGHT)
		row.size = Vector2(size.x, ROW_HEIGHT)
		row.clip_text = true
		row.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		var highlight := StyleBoxFlat.new()
		highlight.bg_color = Color(0, 0, 0, 0.22)
		row.add_theme_stylebox_override("hover", highlight)
		row.add_theme_stylebox_override("pressed", highlight)
		if index == _selected:
			row.add_theme_stylebox_override("normal", highlight)
		row.pressed.connect(func() -> void:
			select(index)
			item_selected.emit(index))
		row.gui_input.connect(_on_scroll)
		add_child(row)


## 整行滚动商品，确保文字始终对齐背景中固定的横线。
## [param event] 列表行接收的鼠标事件。
func _on_scroll(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		_first = clampi(_first + (1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1),
			0, maxi(0, item_count - PAGE_ROWS))
		_rebuild()
		accept_event()
