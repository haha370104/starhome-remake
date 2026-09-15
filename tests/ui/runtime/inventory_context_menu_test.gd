extends SceneTree

var failures: Array[String] = []
var commands: Array[Dictionary] = []
var fixture := PlayerPanelServiceFixture.new()
var manager: GameWindowManager


## 延迟运行真实鼠标与弹出菜单交互。
func _initialize() -> void:
	call_deferred("_run")


## 通过窗口管理器、正式服务和玩家投影验证装备、使用、拆分、合并。
func _run() -> void:
	root.size = Vector2i(1100, 740)
	root.gui_embed_subwindows = true
	fixture.initialize()
	fixture.grant_loot({"loot_id": "cheese", "item_definition_id": "item:material:04081d3010ba", "quantity": 10})
	manager = GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(_dispatch))
	manager.toggle("inventory")
	var panel := manager.inventory_panel
	panel.position = Vector2(80, 50)
	await process_frame
	var menu := panel.context_menu
	await _right_click_item("inventory.spare_engine")
	_expect(panel.visible and menu.menu.visible and _labels(menu.menu).has("装备"), "真实右键装备打开菜单并保留背包")
	_expect(not _labels(menu.menu).has("使用"), "装备不会显示使用")
	menu.menu.hide()
	menu.menu.id_pressed.emit(0)
	_expect(commands.back().type == "equip_vehicle_item" and commands.back().has("loadout_revision"), "装备接入既有权威版本命令")
	await process_frame
	await _right_click_item("cheese")
	_expect(_labels(menu.menu).has("使用") and _labels(menu.menu).has("拆分") and _labels(menu.menu).has("合并"), "食品菜单按能力提供三项")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/inventory-context-menu.png")
	menu.menu.hide()
	menu.menu.id_pressed.emit(1)
	_expect(menu.split_dialog.visible, "拆分打开数量框")
	menu.amount.value = 4
	menu.split_dialog.hide()
	menu.split_dialog.confirmed.emit()
	await process_frame
	var player := manager.panel_session.current_player
	_expect(player.inventory.find("cheese").quantity == 6, "数量确认后应用实际拆分回包")
	await _right_click_item("cheese")
	menu.menu.hide()
	menu.menu.id_pressed.emit(2)
	await process_frame
	_expect(player.inventory.find("cheese").quantity == 10, "合并菜单应用真实回包")
	await _right_click_item("cheese")
	menu.menu.hide()
	menu.menu.id_pressed.emit(0)
	await process_frame
	_expect(player.inventory.find("cheese").quantity == 9 and player.food_status.bonus(17) == 5, "使用菜单扣一份并显示食品状态")
	_expect(panel._food_label.text.contains("食品效果：1"), "背包显示活跃效果数量")
	await _right_click_item("cheese")
	menu.menu.hide()
	var before := commands.size()
	menu.menu.id_pressed.emit(0)
	_expect(menu.replace_dialog.visible and commands.size() == before, "已有同类效果先提示替换")
	menu.dismiss()
	await _right_click(panel.global_position + Vector2(35, 390))
	_expect(not panel.visible and not menu.menu.visible, "空白右键保留关闭习惯并收起菜单")
	manager.free()
	for failure: String in failures:
		push_error(failure)
	print("INVENTORY_CONTEXT_MENU failures=%d" % failures.size())
	quit(0 if failures.is_empty() else 1)


## 让菜单意图经过实际服务并应用同事务回包。
## [param command] 纯操作意图。
func _dispatch(command: Dictionary) -> void:
	commands.append(command)
	var result := fixture.execute(command)
	_expect(result.is_ok, "菜单命令应成功：%s %s" % [command.type, result.error_message])
	if result.is_ok:
		manager.panel_session.apply_bundle(result.value)


## 按当前视图定位物品，验证完整输入分发而非直接调用面板回调。
## [param id] 物品实例标识。
func _right_click_item(id: String) -> void:
	for child: Node in manager.inventory_panel._item_canvas.get_children():
		if child is InventoryItemView and child.item.instance_id == id:
			await _right_click(child.get_global_rect().get_center())
			return
	_expect(false, "物品视图缺失：" + id)


## 向真实根视口注入一次右键按下和松开。
## [param point] 根视口位置。
func _right_click(point: Vector2) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_RIGHT
		event.pressed = pressed
		event.position = point
		event.global_position = point
		Input.parse_input_event(event)
		await process_frame


## 读取用户可见菜单文案。
## [param popup] 已打开的菜单。
## 返回菜单项文本。
func _labels(popup: PopupMenu) -> Array[String]:
	var labels: Array[String] = []
	for index in range(popup.item_count):
		labels.append(popup.get_item_text(index))
	return labels


## 汇总真实交互断言。
## [param condition] 必须成立的条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
