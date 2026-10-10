extends SceneTree

var failures: Array[String] = []
var commands: Array[Dictionary] = []
var transfers: Array[Dictionary] = []
var mouse_position := Vector2.ZERO


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200, 850)
	var catalog := ItemCatalog.new()
	assert(catalog.initialize().is_ok)
	var inventory := Inventory.new()
	inventory.add_reward(catalog.create("beginner_engine", {"instance_id": "engine"}).value)
	inventory.move_item("engine", Vector2i(80, 80), inventory.revision)
	var panel := InventoryPanel.new()
	var manager := GameWindowManager.new()
	root.add_child(manager)
	manager.size = Vector2(1200, 850)
	manager.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manager.add_child(panel)
	panel.position = Vector2(20, 20)
	panel.scale = Vector2(1.5, 1.5)
	panel.command_requested.connect(func(command: Dictionary) -> void: commands.append(command))
	panel.apply_inventory(inventory)
	var target := InventoryCanvas.new()
	target.position = Vector2(750, 150)
	target.transfer_requested.connect(func(identity: String, _source: InventoryCanvas, center: Vector2i) -> void: transfers.append({"id": identity, "position": center}))
	manager.add_child(target)
	var world_drops: Array[Vector2] = []
	manager.set_drag_forwarding(Callable(), func(at: Vector2, _data: Variant) -> bool: return at.distance_to(Vector2(1100, 500)) < 100,
		func(at: Vector2, _data: Variant) -> void: world_drops.append(at))
	await process_frame
	var canvas := panel._item_canvas
	var start: Vector2 = canvas.get_global_transform() * Vector2(72, 76)
	_button(start, true)
	_button(start, false)
	_check(commands.is_empty(), "单击不移动")
	_button(start, true)
	_motion(start + Vector2(60, 30))
	await process_frame
	_check(root.gui_is_dragging(), "真实鼠标输入启动原生拖放")
	var preview: Control = manager.get_child(-1).get_child(0)
	_check(not canvas.get_child(0).visible and preview.modulate.a == 1.0, "拖动只有鼠标下的完整物品，无原位副本或半透明阴影")
	_check(preview.get_global_rect().get_center().is_equal_approx(canvas.get_global_transform() * Vector2(120, 100)), "预览中心与实际落点一致，保留非中心抓取偏移")
	_button(start + Vector2(60, 30), false)
	_check(canvas.get_child(0).visible, "释放后恢复物品显示")
	_check(commands.size() == 1 and commands[0].position_px == [120, 100], "缩放1.5倍后落点仍为局部坐标")
	_check(inventory.find("engine").position_px == Vector2i(80, 80), "拖放不提前修改权威状态")
	_button(start, true)
	_motion(start + Vector2(30, 0))
	await process_frame
	var drop := target.get_global_transform() * Vector2(80, 80)
	_motion(drop)
	await process_frame
	_button(drop, false)
	_check(transfers == [{"id": "engine", "position": Vector2i(92, 86)}], "跨不同缩放窗口保留抓取偏移及自由落点")
	_button(start, true)
	_motion(start + Vector2(30, 0))
	await process_frame
	_motion(Vector2(1150, 800))
	_button(Vector2(1150, 800), false)
	_check(commands.size() == 1 and transfers.size() == 1, "窗外取消")
	_button(start, true)
	_motion(start + Vector2(30, 0))
	await process_frame
	_motion(Vector2(1100, 500))
	_button(Vector2(1100, 500), false)
	_check(world_drops == [Vector2(1100, 500)], "世界空白处接收地面拖放")
	manager.set_drag_forwarding(Callable(), func(_at: Vector2, _data: Variant) -> bool: return true,
		func(at: Vector2, _data: Variant) -> void: world_drops.append(at))
	_button(start, true)
	_motion(start + Vector2(30, 0))
	await process_frame
	_motion(Vector2(300, 660))
	_button(Vector2(300, 660), false)
	_check(world_drops.size() == 1, "其他窗口区域不穿透为地面丢弃")
	manager.free()
	await process_frame
	for failure in failures: push_error(failure)
	print("Inventory drag failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _button(point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = point
	event.global_position = point
	mouse_position = point
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = point - mouse_position
	mouse_position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
