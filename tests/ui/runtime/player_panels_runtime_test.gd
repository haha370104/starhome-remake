extends SceneTree

const ManagerScript := preload("res://scripts/client/ui/windows/game_window_manager.gd")

var failures: PackedStringArray = []
var assertions := 0


## 延迟运行人物、背包和战车面板运行时测试。
func _initialize() -> void:
	call_deferred("_run")


## 实例化显式离线权威，验证窗口布局、拖动命令和换装快照联动。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var manager = ManagerScript.new()
	root.add_child(manager)
	_expect(manager.configure(Callable(), true), "离线三面板管理器应初始化")
	await process_frame
	_expect(not manager.character_panel.visible, "人物面板初始应隐藏")
	_expect(not manager.inventory_panel.visible, "背包面板初始应隐藏")
	_expect(not manager.vehicle_panel.visible, "战车面板初始应隐藏")
	_expect(manager.toggle("character") and manager.character_panel.visible, "人物按钮应切换单例窗口")
	_expect(manager.toggle("inventory") and manager.inventory_panel.visible, "背包按钮应切换单例窗口")
	_expect(manager.toggle("vehicle_equipment") and manager.vehicle_panel.visible, "战车按钮应切换单例窗口")
	await process_frame
	_expect(manager.character_panel.size == Vector2(355, 450), "人物面板应保持荣耀版原始尺寸")
	_expect(manager.inventory_panel.size == Vector2(338, 469), "背包面板应保持荣耀版原始尺寸")
	_expect(manager.vehicle_panel.size == Vector2(604, 460), "战车面板应保持荣耀版原始尺寸")
	_expect(manager.inventory_panel._item_canvas.get_child_count() == 2, "背包应呈现两个权威物品实例")
	_expect(manager.vehicle_panel._slot_root.get_child_count() == 3, "战车应呈现三个已装备槽位")
	manager.inventory_panel._request_move("inventory.spare_engine", Vector2i(92, 61))
	await process_frame
	var moved_found := false
	for item in manager.inventory_panel._item_canvas.get_children():
		if String(item.item_snapshot.get("instance_id", "")) == "inventory.spare_engine":
			moved_found = item.position == Vector2(90, 60)
	_expect(moved_found, "权威回包应将拖动位置吸附到 15 像素网格")
	manager.character_panel.position = Vector2(5000, 5000)
	manager.character_panel.clamp_to_viewport(Vector2(1280, 720))
	_expect(manager.character_panel.position == Vector2(925, 270), "拖动窗口必须限制在当前视口")
	_finish(manager)


## 汇总测试结果并释放窗口管理器。
## [param manager] 本次测试创建的窗口管理器。
func _finish(manager: Control) -> void:
	if failures.is_empty():
		print("PLAYER_PANELS_RUNTIME_OK (%d assertions)" % assertions)
		manager.free()
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	manager.free()
	quit(1)


## 记录一个运行时布尔断言。
## [param condition] 预期成立的条件。
## [param message] 失败信息。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
