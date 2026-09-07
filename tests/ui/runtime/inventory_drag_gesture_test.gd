extends SceneTree

var failures := PackedStringArray()
var commands: Array[Dictionary] = []


## 延迟验证实际物品控件的鼠标手势。
func _initialize() -> void:
	call_deferred("_run")


## 覆盖普通单击、抖动、双击、真实拖动和权威坐标显示。
func _run() -> void:
	var catalog := ItemCatalog.new()
	_expect(catalog.initialize().is_ok, "目录初始化")
	var first: GameItem = catalog.create("beginner_engine", {
		"instance_id": "first", "position_px": [17, 43],
	}).value
	var second: GameItem = catalog.create("beginner_engine", {
		"instance_id": "second", "position_px": [17, 43],
	}).value
	var inventory := Inventory.new()
	_expect(inventory.restore_items([first, second]).is_ok, "重叠坐标应能从快照恢复")
	var panel := InventoryPanel.new()
	root.add_child(panel)
	panel.command_requested.connect(func(command: Dictionary) -> void: commands.append(command))
	panel.apply_inventory(inventory)
	var view := panel._item_canvas.get_child(0) as InventoryItemView
	_expect(view.position == Vector2(17, 43) \
		and panel._item_canvas.get_child(1).position == view.position, "UI 不自动排格，也允许重叠")
	view._on_gui_input(_button(true))
	view._on_gui_input(_button(false))
	_expect(commands.is_empty(), "普通单击不能发送移动请求")
	view._on_gui_input(_button(true))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(2, 1)
	view._on_gui_input(motion)
	view._on_gui_input(_button(false))
	_expect(commands.is_empty() and view.position == Vector2(17, 43), "轻微抖动不是拖动")
	view._on_gui_input(_button(true, true))
	view._on_gui_input(_button(false))
	_expect(commands.size() == 1 and commands[0].type == "equip_vehicle_item",
		"双击只发送一次装备命令，不夹带移动")
	commands.clear()
	view._on_gui_input(_button(true))
	motion.relative = Vector2(75, 18)
	view._on_gui_input(motion)
	view._on_gui_input(_button(false))
	_expect(commands.size() == 1 and commands[0].type == "move_inventory_item" \
		and commands[0].position_px == [92, 61], "真正拖动只提交精确坐标，不吸附")
	_expect(view.position == Vector2(17, 43) and view.modulate.a == 1.0,
		"松开恢复预览，拒绝命令时不留下错误位置")
	_expect(inventory.move_item("first", Vector2i(92, 61), inventory.revision).is_ok,
		"权威端接受拖动")
	panel.apply_inventory(inventory)
	await process_frame
	_expect(panel._item_canvas.get_child(0).position == Vector2(92, 61), "回包显示真实坐标")
	_expect(inventory.arrange(inventory.revision).is_ok, "手动整理成功")
	panel.apply_inventory(inventory)
	await process_frame
	_expect(panel._item_canvas.get_child(0).position == Vector2.ZERO \
		and panel._item_canvas.get_child(1).position == Vector2(55, 0), "整理后才对齐虚拟格子")
	panel.free()
	for failure: String in failures:
		push_error(failure)
	if failures.is_empty():
		print("INVENTORY_DRAG_GESTURE_OK")
	quit(0 if failures.is_empty() else 1)


## 构造在图标相同抓取点按下/松开的鼠标事件。
## [param pressed] 是否按下。
## [param double_click] 是否双击。
func _button(pressed: bool, double_click: bool = false) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.double_click = double_click
	event.position = Vector2(10, 10)
	return event


## 记录交互断言。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
