extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _commands: Array[Dictionary] = []
var _checks := 0
var _failures := 0


## 等待窗口树就绪再运行真实 UI 与权威服务交互。
func _initialize() -> void:
	call_deferred("_run")


## 验证右键入口、材料选择、预览、确认、后台存档兼容和摘取。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "services")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	var engine: VehicleEquipment = player.inventory.find("inventory.spare_engine")
	engine.sockets.settle_open(0, true, "none")
	for definition: String in ["bright_health_crystal", "vehicle_density_solvent_i", "vehicle_precise_hammer", "vehicle_armed_chip"]:
		player.inventory.add_reward(items.create(definition, {"instance_id": definition, "quantity": 5}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "manager configured")
	_manager.toggle("inventory")
	await process_frame
	var menu := _manager.inventory_panel.context_menu
	menu.open_for(_manager.panel_session.current_player.inventory.find(engine.instance_id), player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("vehicle_sockets"), "right click workshop action")
	menu.menu.hide()
	menu._select_action(menu._actions.find("vehicle_sockets"))
	var panel: VehicleSocketPanel = _manager.navigation_windows.vehicle_sockets
	_check(panel.visible and _manager.inventory_panel.visible, "independent workshop leaves bag open")
	_check(panel._slot_buttons[0].text == "1 空孔" and panel._slot_buttons[8].disabled, "socket states")
	var crystal_row := -1
	for index: int in panel._materials.size():
		if panel._materials[index].instance_id == "bright_health_crystal":
			crystal_row = index
	_check(crystal_row >= 0, "material listed")
	panel.material_list.item_selected.emit(crystal_row)
	_check(not panel._action_buttons[1].disabled and panel.details.text.contains("生命 +50"), "authoritative inlay preview")
	await process_frame
	for listing: ItemList in [panel.equipment_list, panel.material_list]:
		_check(listing.get_rect().end.x < panel.size.x and listing.get_rect().end.y < panel.size.y, "list contained")
	for index: int in panel._materials.size():
		_check(panel.material_list.get_item_icon(index) != null, "material icon " + str(index))
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/vehicle_socket_panel.png")
	panel._ask("inlay_vehicle_crystal")
	var captured_revision := int(panel._pending.inventory_revision)
	_check(panel.confirmation.visible and captured_revision == _fixture._state.inventory_revision, "confirmation captures item revision")
	_fixture._state.revision += 10
	panel.confirmation.hide()
	panel._confirm()
	_check(_commands.back().type == "inlay_vehicle_crystal", "submit once")
	_check(panel._slot_buttons[0].text == "1 晶石" and panel._preview.can_extract, "successful inlay visible")
	var after: Player = mapper.to_domain(_fixture._state).value
	_check((after.inventory.find(engine.instance_id) as VehicleEquipment).sockets.slot_at(0).crystal_id == "bright_health_crystal", "autosave revision does not invalidate inlay")
	panel._ask("extract_vehicle_crystal")
	panel.confirmation.hide()
	panel._confirm()
	_check(panel._slot_buttons[0].text == "1 空孔", "extract visible")
	panel._ask_purchase()
	_check(panel._pending.type == "buy_vehicle_workshop_material" and panel.confirmation.dialog_text.contains("星际币"), "purchase preview")
	panel.hide()
	_check(panel._pending.is_empty() and not panel.confirmation.visible, "closing clears confirmation")
	_manager.queue_free()
	await process_frame
	print("Vehicle socket UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 将真实会话命令发送到正式服务，测试只替换存档仓储。
## [param command] 窗口发出的意图。
## 返回同版本玩家面板组合。
func _dispatch(command: Dictionary) -> DomainResult:
	_commands.append(command.duplicate(true))
	if _commerce.handles(String(command.get("type", ""))):
		var result := _commerce.execute(_fixture._state, command)
		if not result.is_ok:
			push_error(result.error_message)
			return result
		if result.value.changed:
			_fixture._state = result.value.candidate
			_fixture._state.revision += 1
		var bundle := _commerce.build_bundle(_fixture._state, result.value.operation)
		_manager.panel_session.apply_bundle(bundle)
		return DomainResult.ok(bundle)
	var result := _fixture.execute(command)
	if result.is_ok:
		_manager.panel_session.apply_bundle(result.value)
	return result


## 记录行为和可见状态检查。
## [param condition] 实际结果。
## [param message] 诊断消息。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
