extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var failures: Array[String] = []
var assertions := 0


## 延迟验证共享会话、独立控件和 HUD 提示的生命周期。
func _initialize() -> void:
	call_deferred("_run")


## 销毁并重建窗口、同时嵌入两个背包，验证状态与输入不会串联。
func _run() -> void:
	root.size = Vector2i(1600, 900)
	var fixture := Fixture.new()
	_expect(fixture.initialize().is_ok, "内存权威夹具初始化")
	var commands: Array[Dictionary] = []
	var session := PlayerPanelSession.new(func(command: Dictionary) -> void: commands.append(command))
	var queried := fixture.execute({"type": "query"})
	_expect(queried.is_ok, "夹具返回同事务玩家快照")
	if not queried.is_ok:
		quit(1)
		return
	session.apply_bundle(queried.value)
	var original_player := session.current_player
	var first := GameWindowManager.new()
	root.add_child(first)
	first.configure(session)
	_expect(first.inventory_panel._item_canvas.get_child_count() == 2, "晚创建的窗口读取既有玩家快照")
	first.free()
	var second := GameWindowManager.new()
	root.add_child(second)
	second.configure(session)
	_expect(session.current_player == original_player, "窗口销毁不替换或释放当前玩家")
	var intent := {"type": "equip_vehicle_item", "requires_loadout_revision": true, "requires_state_revision": true}
	session.dispatch(intent)
	_expect(intent.has("requires_state_revision") and not intent.has("state_revision"), "版本补齐不修改调用方意图")
	_expect(commands.back().state_revision == original_player.revision, "重建窗口仍使用同一人物版本")
	_expect(commands.back().loadout_revision == session.snapshot_bundle().vehicle.revision, "战车版本来自同事务投影")
	var canvas_a := InventoryCanvas.new()
	var canvas_b := InventoryCanvas.new()
	root.add_child(canvas_a)
	root.add_child(canvas_b)
	canvas_a.apply_inventory(original_player.inventory)
	canvas_b.apply_inventory(original_player.inventory)
	var moves_a: Array[String] = []
	var moves_b: Array[String] = []
	canvas_a.move_requested.connect(func(id: String, _position: Vector2i) -> void: moves_a.append(id))
	canvas_b.move_requested.connect(func(id: String, _position: Vector2i) -> void: moves_b.append(id))
	var item_a := canvas_a.get_child(0) as InventoryItemView
	var previous_position := item_a.item.position_px
	item_a.move_requested.emit(item_a.item.instance_id, Vector2i(30, 20))
	_expect(moves_a.size() == 1 and moves_b.is_empty(), "两个背包组件独立发出意图")
	_expect(item_a.item.position_px == previous_position, "展示控件不修改共享领域物品位置")
	canvas_a.apply_inventory(null)
	_expect(canvas_a.get_child_count() == 0 and canvas_b.get_child_count() == 2, "清空一个组件不影响其他组件")
	canvas_a.free()
	canvas_b.free()
	var failed_layer := EquipmentLayerView.new()
	_expect(not failed_layer.configure({}, Vector2.ZERO), "缺失表现资源可由任意宿主明确处理")
	failed_layer.free()
	var clothing_result := fixture.execute({
		"type": "equip_character_item", "instance_id": "inventory.training_shirt",
		"character_slot": "upper_body", "inventory_revision": 0, "state_revision": 0,
	})
	_expect(clothing_result.is_ok, "服装换装仍由权威夹具执行")
	if clothing_result.is_ok:
		session.apply_bundle(clothing_result.value)
	await process_frame
	_expect(second.character_panel._equipment_layers.get_child(0) is EquipmentLayerView, "人物使用共享装备图层")
	_expect(second.vehicle_panel._slot_root.get_child(0) is EquipmentLayerView, "战车使用相同组件")
	await _test_status_lifetime()
	if "--capture-components" in OS.get_cmdline_user_args():
		second.character_panel.position = Vector2(20, 40)
		second.vehicle_panel.position = Vector2(400, 40)
		second.inventory_panel.position = Vector2(1030, 40)
		second.character_panel.show()
		second.vehicle_panel.show()
		second.inventory_panel.show()
		await process_frame
		await RenderingServer.frame_post_draw
		var capture := root.get_texture().get_image()
		_expect(capture.save_png("res://.godot/refactor-player-panels.png") == OK, "保存真实窗口渲染截图")
	second.free()
	await process_frame
	for failure in failures:
		push_error(failure)
	print("REUSABLE_PLAYER_UI_OK assertions=%d failures=%d" % [assertions, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 验证网络临时提示不会在超时后覆盖更新的业务提示。
func _test_status_lifetime() -> void:
	var hud := HallHud.new()
	var texture := ImageTexture.create_from_image(Image.create(1, 1, false, Image.FORMAT_RGBA8))
	hud.configure(Vector2(100, 100), texture, "组件测试")
	root.add_child(hud)
	hud.show_status("原提示")
	hud.show_network_notice("临时网络提示", 0.1)
	hud.show_status("新操作提示")
	await create_timer(0.15).timeout
	_expect(hud.status_text() == "新操作提示", "临时提示超时不覆盖新操作")
	hud.show_network_notice("连接恢复", 0.1)
	await create_timer(0.15).timeout
	_expect(hud.status_text() == "新操作提示", "无新操作时恢复先前提示")
	hud.free()


## 累计行为断言，失败时让测试进程返回非零退出码。
## [param condition] 需要满足的行为条件。
## [param message] 失败时显示的中文原因。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
