extends SceneTree

var fixture := PlayerPanelServiceFixture.new()
var service := PersonalWarehouseService.new()
var player: Player
var manager: GameWindowManager
var failures: Array[String] = []
var commands: Array[Dictionary] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	assert(fixture.initialize().is_ok and service.initialize().is_ok)
	player = fixture.current_player().value
	player.amethyst = AmethystWallet.new(5000)
	player.inventory.add_reward(service._catalog.create("bright_firepower_crystal",
		{"instance_id": "crystal", "quantity": 7, "bound": true, "crystal_cracks": 2}).value)
	manager = GameWindowManager.new()
	root.add_child(manager)
	var session := PlayerPanelSession.new(_dispatch, service._catalog)
	session.begin_sync("warehouse-test")
	manager.configure(session)
	manager.toggle("inventory")
	manager.inventory_panel.content_root.get_node("WarehouseButton").pressed.emit()
	var warehouse: PersonalWarehousePanel = manager.navigation_windows.personal_warehouse
	var backpack := manager.inventory_panel._item_canvas
	await process_frame
	_check(warehouse.visible and manager.inventory_panel.visible, "独立窗口同时打开")
	var data := {"source": backpack, "instance_id": "crystal", "offset": Vector2.ZERO}
	manager.inventory_panel.hide()
	warehouse.item_canvas._drop_data(Vector2(100, 100), data)
	_check(player.inventory.find("crystal") != null, "背包关闭时不能转移")
	manager.inventory_panel.show()
	warehouse.item_canvas._drop_data(Vector2(100, 100), data)
	_check(player.inventory.find("crystal") == null and warehouse._snapshot.inventory.find("crystal").quantity == 7, "拖动整堆存入并应用增量")
	_check(not commands.back().has("quantity"), "存取不携带数量")
	var stored: VehicleCrystal = warehouse._snapshot.inventory.find("crystal")
	_check(stored.cracks == 2 and stored.bound and stored.position_px == Vector2i(100, 100), "保留裂纹、绑定和自由落点")
	warehouse.open_board()
	_check(warehouse._snapshot.inventory.find("crystal") == stored, "重复快照复用未变化物品")
	_dispatch({"type": "arrange_inventory", "inventory_revision": player.inventory.revision})
	await process_frame
	_check(commands.back().type == "arrange_inventory", "整理背包不额外查询仓库")
	backpack._drop_data(Vector2(113, 127), {"source": warehouse.item_canvas, "instance_id": "crystal", "offset": Vector2.ZERO})
	_check(player.inventory.find("crystal").quantity == 7 and player.inventory.find("crystal").position_px == Vector2i(113, 127) \
		and warehouse._snapshot.inventory.find("crystal") == null, "整理后取出仍按指定落点整堆放置")
	warehouse._cabinet_buttons[1].pressed.emit()
	_check(warehouse.confirmation.dialog_text.contains("1888"), "开柜确认费用")
	warehouse.confirmation.hide()
	warehouse.confirmation.confirmed.emit()
	_check(warehouse._snapshot.cabinet == 2 and session.current_player.amethyst.balance() == 3112, "开柜同步钱包")
	warehouse._cabinet_buttons[0].pressed.emit()
	warehouse.item_canvas._drop_data(Vector2(100, 100), data)
	warehouse.handle_context_click(warehouse.item_canvas.get_child(0).get_global_rect().get_center())
	warehouse.context_menu.menu.hide()
	warehouse.context_menu.menu.id_pressed.emit(0)
	warehouse.context_menu.amount.value = 3
	warehouse.context_menu.split_dialog.hide()
	warehouse.context_menu.split_dialog.confirmed.emit()
	_check(player.warehouse.items(1).size() == 2 and player.warehouse.find("crystal").quantity == 4, "复用拆分规则")
	for index in 38:
		player.warehouse._cabinets[0].add_reward(service._catalog.create("beginner_engine", {"instance_id": "fill.%d" % index}).value)
	var split := {"type": "split_warehouse_item", "cabinet": 1, "instance_id": "crystal", "quantity": 1,
		"inventory_revision": player.inventory.revision, "warehouse_revision": player.warehouse.revision}
	_check(not service.execute(player, split).is_ok and player.warehouse.items(1).size() == 40 \
		and player.warehouse.find("crystal").quantity == 4, "满柜拆分失败不超容量、不扣数量")
	split.merge({"type": "move_warehouse_item", "position_px": [true, 2]}, true)
	_check(not service.execute(player, split).is_ok, "拒绝非整数坐标")
	split.position_px = [10, 20]
	var moved := service.execute(player, split)
	_check(moved.is_ok and moved.value.candidate.warehouse._cabinets[1] == player.warehouse._cabinets[1], "未操作的柜复用")
	_check(moved.value.candidate.warehouse.find("crystal") != player.warehouse.find("crystal"), "写入物品隔离")
	player.map_id = "outside"
	warehouse.open_board()
	var count := commands.size()
	backpack._drop_data(Vector2(100, 100), {"source": warehouse.item_canvas, "instance_id": "crystal", "offset": Vector2.ZERO})
	_check(commands.size() == count, "野外不能拖放存取")
	_check(not service.execute(player, {"type": "withdraw_warehouse_item", "instance_id": "crystal"}).is_ok, "服务端拒绝野外绕过")
	manager.free()
	await process_frame
	for failure in failures: push_error(failure)
	print("Warehouse UI failures=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _dispatch(command: Dictionary) -> void:
	commands.append(command)
	var before: Dictionary = fixture._mapper.to_record(player).value.to_dictionary()
	var result := service.execute(player, command) if command.type in PersonalWarehouseService.COMMANDS else fixture._service.execute(player, command)
	_check(result.is_ok, "%s: %s" % [command.type, result.error_message])
	if not result.is_ok: return
	_check(before == fixture._mapper.to_record(player).value.to_dictionary(), "提交前不改原状态")
	var value: Dictionary = result.value
	var bundle: Dictionary = value.panel_bundle
	if value.changed:
		var change: PlayerChange = value.change
		change.sync_id = "warehouse-test"
		change.base_revision = player.revision
		player = value.candidate
		player.revision += 1
		change.revision = player.revision
		if not bundle.has("character"): bundle["player_change"] = change.to_dictionary()
	bundle["sync_id"] = "warehouse-test"
	bundle["transaction_revision"] = player.revision
	manager.panel_session.apply_bundle(bundle)


func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
