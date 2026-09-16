class_name SpecialEquipmentPanel
extends Panel

signal unequip_requested(location: int)

const EquipmentLayer := preload("res://scripts/client/ui/components/equipment_layer_view.gd")
var _items_root: Control


## 创建独立特殊装备区，三列保留撒玛、奥斯格兰和晶源体各四个逻辑位置。
func _ready() -> void:
	position = Vector2(22, 46)
	size = Vector2(425, 383)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101d28")
	style.border_color = Color("42c9dc")
	style.set_border_width_all(1)
	add_theme_stylebox_override("panel", style)
	var close := Button.new()
	close.text = "返回战车"
	close.position = Vector2(310, 7)
	close.size = Vector2(104, 28)
	close.pressed.connect(hide)
	add_child(close)
	var title := Label.new()
	title.text = "特殊装备 · 独立装配区"
	title.position = Vector2(12, 10)
	add_child(title)
	for index in range(3):
		var label := Label.new()
		label.text = ["撒玛", "奥斯格兰", "晶源体"][index]
		label.position = Vector2(22 + index * 138, 43)
		add_child(label)
	_items_root = Control.new()
	_items_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_items_root)


## 按系列和行展示已安装装备，并为缺失位置保留明确空格。
## [param equipped] 服务端投影的全量战车装备。
func apply_equipment(equipped: Array) -> void:
	for child in _items_root.get_children():
		child.queue_free()
	for location in [19, 20, 21, 22, 24, 25, 26, 27, 28, 29, 30, 31]:
		var series := EquipmentSlotRegistry.special_series(location)
		var column := ["sama", "austin_glens", "crystal"].find(series)
		var row := EquipmentSlotRegistry.special_row(location)
		var rect := Rect2(18 + column * 138, 72 + row * 76, 115, 65)
		var empty := Label.new()
		empty.text = EquipmentSlotRegistry.display_name(location)
		empty.position = rect.position
		empty.size = rect.size
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.modulate = Color("8195a3")
		_items_root.add_child(empty)
		for item: Dictionary in equipped:
			if int(item.get("location", -1)) != location:
				continue
			var visual := EquipmentLayer.new()
			if visual.configure(item, Vector2.ZERO, rect):
				visual.name = "SpecialLocation_%d" % location
				empty.hide()
				visual.gui_input.connect(_on_item_input.bind(location))
				_items_root.add_child(visual)
			else:
				visual.free()
				empty.hide()
				var fallback := Button.new()
				fallback.name = "SpecialLocation_%d" % location
				fallback.text = String(item.get("display_name", "特殊装备")) + "\n图像未导入"
				fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				fallback.position = rect.position
				fallback.size = rect.size
				fallback.add_theme_font_size_override("font_size", 12)
				fallback.tooltip_text = "双击卸下：" + String(item.get("display_name", "特殊装备"))
				fallback.gui_input.connect(_on_item_input.bind(location))
				_items_root.add_child(fallback)


## 双击只发布卸装意图，由父窗口附上事务版本。
## [param event] GUI 鼠标事件。
## [param location] 特殊装备的稳定位置。
func _on_item_input(event: InputEvent, location: int) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed and event.double_click:
		unequip_requested.emit(location)
		accept_event()
