extends SceneTree

var checks := 0
var failures: Array[String] = []
var hall: Node
var fixture := PlayerPanelServiceFixture.new()
var commands: Array[Dictionary] = []


## 延迟启动完整游戏窗口，所有偏好与物品数据都使用测试隔离目录。
func _initialize() -> void:
	call_deferred("_run")


## 验证系统菜单、快捷键录入、真实缩放点击、偏好保存与音频总线。
func _run() -> void:
	root.size = Vector2i(1280, 800)
	root.gui_embed_subwindows = true
	hall = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await _frames(3)
	var controller: ClientSettingsController = hall.settings_controller
	controller._path = "res://.godot/settings-panel-%d.cfg" % Time.get_ticks_usec()
	var settings := controller.preferences
	settings.reset()
	var panel := controller.panel
	var manager: GameWindowManager = hall.game_window_manager
	var map: MapNavigationPanel = hall.hud.map_navigation_panel
	var menu: SystemMenuPanel = manager.navigation_windows.system
	for entry: Array in [["字体设置", "display"], ["颜色设置", "colors"], ["热键设置", "keys"], ["音乐音效", "audio"]]:
		for child in menu.content_root.get_children():
			if child is Button and child.tooltip_text == entry[0]: child.pressed.emit()
		_check(panel.visible and panel._pages[entry[1]].visible, "原图菜单进入" + entry[0])
	panel.open_section("keys")
	panel.key_buttons.map.pressed.emit()
	await _key(KEY_Z)
	_check(settings.hotkeys.capturing and panel.status.text.contains("自维修"), "冲突提示且保留录入状态")
	await _key(KEY_ESCAPE)
	_check(not settings.hotkeys.capturing and settings.hotkeys.snapshot().map == KEY_TAB, "取消录入保留原键")
	panel.key_buttons.map.pressed.emit()
	await _key(KEY_M, true)
	_check(settings.hotkeys.snapshot().map == KEY_M | KEY_MASK_CTRL, "新组合经实际输入绑定")
	_check(not map.visible and map.status.text.contains("Ctrl+M"), "录入不打开地图且提示同步")
	panel.hide()
	root.gui_release_focus()
	await _key(KEY_TAB)
	_check(not map.visible, "旧键不再打开地图")
	await _key(KEY_M, true)
	_check(map.visible, "新键打开地图")
	await _key(KEY_M, true)
	_check(not map.visible, "新键关闭地图")
	var editor := LineEdit.new()
	editor.size = Vector2(180, 30)
	hall.hud.root_control.add_child(editor)
	editor.grab_focus()
	await _key(KEY_M, true)
	_check(not map.visible, "文字输入不会打开地图")
	editor.free()
	controller._open_section("display")
	settings.set_window_scale(1.3)
	await _frames(2)
	_check(panel.scale.is_equal_approx(Vector2(1.3, 1.3)), "设置窗口与文字整体放大")
	var initial := panel.position
	var header := panel.get_global_rect().position + Vector2(15, 10)
	await _mouse(header, true)
	await _motion(header + Vector2(39, 26), Vector2(39, 26))
	await _mouse(header + Vector2(39, 26), false)
	_check(panel.position.is_equal_approx(initial + Vector2(39, 26)), "缩放标题拖动与屏幕指针一致")
	settings.set_palette("warm")
	_check(panel.theme.get_color("font_color", "Label") == Color("ffe9c7"), "通用面板配色")
	_check(hall.hud.system_message_feed._text_color == Color("ffe9c7"), "系统消息配色")
	settings.set_volume("music", 0.4)
	_check(is_equal_approx(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))), 0.4), "音乐音量接真实总线")
	settings.set_muted(true)
	_check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Master")), "总静音接真实总线")
	var restored := ClientPreferences.new()
	_check(restored.load_file(controller._path) == OK and restored.window_scale == 1.3 and restored.muted, "界面改动已保存")
	controller._path = "res://.godot/nonexistent-parent/settings.cfg"
	settings.set_palette("high_contrast")
	_check(panel.status.text.contains("保存失败") and panel.theme.get_color("font_color", "Label") == Color.WHITE, "写入失败说明且当前设置可用")
	controller._path = "res://.godot/settings-panel-recovered.cfg"
	settings.set_palette("default")
	_check(panel.theme == controller._original_themes[panel], "恢复配色使用原主题")
	root.size = Vector2i(960, 540)
	await _frames(3)
	for window in controller._windows:
		_check(root.get_visible_rect().encloses(window.get_global_rect()), "窗口完整适配小屏幕：" + window.name)
	root.size = Vector2i(1280, 800)
	await _frames(3)
	settings.set_window_scale(1.3)
	panel.hide()
	root.gui_release_focus()
	await _key(KEY_M, true)
	var map_destinations: Array[Vector2] = []
	map.canvas.destination_requested.connect(func(destination: Vector2) -> void: map_destinations.append(destination))
	var map_point := map.canvas.get_global_transform() * map.canvas.image_rect().get_center()
	await _mouse(map_point, true)
	await _mouse(map_point, false)
	_check(not map_destinations.is_empty() and map_destinations[0].is_equal_approx(map.canvas.world_size / 2), "缩放地图中央点击映射到世界中央")
	map.hide()
	fixture.initialize()
	manager.panel_session._dispatcher = _dispatch
	manager.panel_session.apply_bundle(fixture.execute({"type": "query"}).value)
	manager.inventory_panel.show()
	manager.inventory_panel.position = Vector2(60, 40)
	await _frames(2)
	var item_view: InventoryItemView
	for child in manager.inventory_panel._item_canvas.get_children():
		if child is InventoryItemView and child.item.instance_id == "inventory.spare_engine": item_view = child
	_check(item_view != null, "真实背包物品视图")
	if item_view != null:
		var point := item_view.get_global_rect().get_center()
		ItemHoverHighlight._show_tooltip(item_view, "测试装备\n说明框随装备面板放大")
		var tooltip := ItemHoverHighlight.active_tooltip()
		_check(tooltip.scale.is_equal_approx(manager.inventory_panel.scale), "物品说明随所属窗口同比例放大")
		_check(root.get_visible_rect().encloses(tooltip.get_global_rect()), "物品说明保持在屏幕内")
		ItemHoverHighlight.dismiss_for(item_view)
		await _mouse(point, true, MOUSE_BUTTON_RIGHT)
		await _mouse(point, false, MOUSE_BUTTON_RIGHT)
		_check(manager.inventory_panel.visible and manager.inventory_panel.context_menu.menu.visible, "放大后右键仍命中实际物品")
		manager.inventory_panel.context_menu.dismiss()
		var requested: Array[Vector2i] = []
		item_view.move_requested.connect(func(_id: String, destination: Vector2i) -> void: requested.append(destination))
		var original_position := item_view.position
		await _mouse(point, true)
		await _motion(point + Vector2(39, 26), Vector2(39, 26))
		await _mouse(point + Vector2(39, 26), false)
		_check(not requested.is_empty() and requested[0] == Vector2i(original_position + Vector2(30, 20)), "背包拖放提交逻辑坐标而非放大像素")
	manager.inventory_panel.hide()
	controller._open_section("display")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/client_settings.png")
	panel._reset()
	_check(settings.window_scale == 1 and settings.palette == "default" and not settings.muted, "设置页恢复默认")
	_check(manager.panel_session.current_player.inventory.find("inventory.spare_engine") != null, "恢复偏好不移除背包物品")
	hall.free()
	for failure in failures: push_error(failure)
	print("CLIENT_SETTINGS_PANEL_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 使背包命令通过正式测试服务，记录实际逻辑坐标而不制造客户端物品。
## [param command] 实际界面发出的意图。
func _dispatch(command: Dictionary) -> void:
	commands.append(command)
	var result := fixture.execute(command)
	if result.is_ok: hall.game_window_manager.panel_session.apply_bundle(result.value)


## 注入真实组合键按下和释放。
## [param code] 逻辑按键。[param control] 是否附带Ctrl。
func _key(code: int, control := false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.pressed = pressed
		event.ctrl_pressed = control
		Input.parse_input_event(event)
		await process_frame


## 注入屏幕坐标鼠标按键。
## [param point] 视口位置。[param pressed] 按下状态。[param button] 鼠标键。
func _mouse(point: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.pressed = pressed
	event.button_index = button
	Input.parse_input_event(event)
	await process_frame


## 在实际GUI分发中拖动鼠标。
## [param point] 新位置。[param delta] 屏幕移动量。
func _motion(point: Vector2, delta: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = delta
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await process_frame


## 等待布局与按键分发完成。
## [param count] 所需帧数。
func _frames(count: int) -> void:
	for _frame in count: await process_frame


## 汇总设置界面断言。
## [param condition] 预期条件。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
