extends SceneTree

class WorldInputProbe:
	extends Node
	var clicks := 0

	## 记录穿过 GUI 的鼠标按下，地图操作不应到达这里。
	## [param event] 未被界面处理的输入。
	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			clicks += 1

var checks := 0
var failures: Array[String] = []
var requests: Array[Vector2] = []
var ids: Array[StringName] = []


## 等待根视口就绪后验证真实 GUI 路由及大小地图投影。
func _initialize() -> void:
	call_deferred("_run")


## 驱动实际键鼠事件，覆盖点击穿透、留白、滚动偏移和窗口生命周期。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var probe := WorldInputProbe.new()
	root.add_child(probe)
	var hud := HallHud.new()
	var texture := GradientTexture2D.new()
	texture.width = 300
	texture.height = 150
	hud.configure(Vector2(2000, 1000), texture, "测试地图")
	root.add_child(hud)
	hud.map_navigation_requested.connect(func(point: Vector2, id: StringName) -> void:
		requests.append(point)
		ids.append(id))
	await process_frame
	var dock := hud.minimap_dock as FreeMinimapDock
	hud.state.set_minimap_size("large")
	_click(dock.map_viewport.global_position + Vector2(150, 75))
	_expect(requests.size() == 1 and requests.back().is_equal_approx(Vector2(1000, 500)), "展开小地图中心准确映射到世界中心")
	_expect(probe.clicks == 0, "小地图左键不穿透为攻击")
	_click(dock.map_viewport.global_position + Vector2(150, 75), MOUSE_BUTTON_RIGHT)
	_expect(requests.size() == 1 and probe.clicks == 0, "地图右键被消费但不寻路")
	hud.state.set_minimap_size("small")
	hud.update_player_dot(Vector2(1000, 500))
	_click(dock.map_viewport.global_position + Vector2(75, 60))
	_expect(requests.back().is_equal_approx(Vector2(1100, 500)), "跟随玩家滚动的小地图正确逆算偏移")
	hud.update_player_dot(Vector2.ZERO)
	var count := requests.size()
	_click(dock.map_viewport.global_position + Vector2(10, 10))
	_expect(requests.size() == count, "小地图越过地图边缘的留白不产生目标")
	hud.state.set_minimap_collapsed(true)
	_expect(not dock.map_viewport.is_visible_in_tree(), "收起后地图不接收点击")
	var panel := hud.map_navigation_panel
	_tab()
	_expect(panel.visible, "Tab 打开地图面板")
	_tab(true)
	_expect(panel.visible, "长按 Tab 不反复切换")
	await process_frame
	_click(panel.canvas.global_position + panel.canvas.image_rect().get_center())
	_expect(requests.back().is_equal_approx(Vector2(1000, 500)), "Tab 底图等比缩放后准确映射")
	count = requests.size()
	_click(panel.canvas.global_position + Vector2(20, 20))
	_expect(requests.size() == count and probe.clicks == 0, "Tab 地图上下留白不寻路也不穿透")
	var point := MapNavigationPoint.new(&"transition:test", "龙之城东南侧出口", "传送点",
		Vector2(1500, 700), Vector2(1400, 650), &"test")
	hud.set_map_navigation_points([point])
	await process_frame
	_click(panel.listing.global_position + Vector2(30, 22))
	_expect(ids.back() == point.id and requests.back() == point.destination, "侧栏左键单击发出独立入口坐标及标识")
	count = requests.size()
	_click(panel.listing.global_position + Vector2(30, 22))
	_expect(requests.size() == count + 1, "重复单击已选中目的地仍可重新寻路")
	hud.update_player_dot(Vector2(777, 333))
	_expect(panel.canvas.player_position == Vector2(777, 333), "地图面板实时订阅玩家位置")
	hud.set_map(Vector2(6000, 3000), texture, "新地图")
	_expect(panel.visible and panel.listing.points.size() == 0 and panel.map_label.text == "新地图", "切图保留面板并清除旧目的地")
	_expect(not panel.canvas.selected_position.is_finite(), "切图清除旧选点标记")
	_click(panel.canvas.global_position + panel.canvas.image_rect().get_center())
	_expect(requests.back().is_equal_approx(Vector2(3000, 1500)), "切图立即使用新世界尺寸")
	_tab()
	_expect(not panel.visible and panel._refresh_timer.is_stopped(), "Tab 关闭并停止坐标轮询")
	var input := LineEdit.new()
	root.add_child(input)
	input.grab_focus()
	_tab()
	_expect(not panel.visible, "文字输入时 Tab 不误开地图")
	input.release_focus()
	input.free()
	root.size = Vector2i(960, 540)
	await process_frame
	_tab()
	_expect(Rect2(Vector2.ZERO, Vector2(960, 540)).encloses(panel.get_rect()), "最低支持分辨率完整容纳面板")
	panel.request_close()
	_expect(not panel.visible, "关闭按钮复用窗口关闭行为")
	hud.free()
	probe.free()
	for failure in failures:
		push_error(failure)
	print("MAP_NAVIGATION_UI checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 注入完整鼠标按下和松开事件，保留真实 GUI 消费顺序。
## [param position] 视口坐标。
## [param button] 鼠标按钮。
func _click(position: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = button
		event.pressed = pressed
		root.push_input(event, true)


## 注入 Tab 按下；重复标记用于验证长按不会闪烁开关。
## [param echo] 是否为长按重复事件。
func _tab(echo := false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_TAB
	event.pressed = true
	event.echo = echo
	root.push_input(event, true)


## 汇总断言，失败时保留完整场景清理和错误列表。
## [param condition] 预期条件。
## [param message] 失败诊断。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
