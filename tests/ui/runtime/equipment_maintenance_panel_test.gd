extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0


## 等待窗口树构建。
func _initialize() -> void:
	call_deferred("_run")


## 验证维护与速修模式、工具购买、右键入口和独立确认状态。
func _run() -> void:
	root.size = Vector2i(1200, 840)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "services")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.map_id = "yian_harbor_hall_floor_1"
	player.inventory.currency = 100000
	var engine := player.inventory.find("inventory.spare_engine") as Equipment
	engine.durability = 100
	player.vehicle.loadout.at(1).durability = 100
	for id: String in ["maintenance_quickrepairbox1", "maintenance_ionrepairbox1"]:
		player.inventory.add_reward(items.create(id, {"instance_id": id, "quantity": 2}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "manager")
	_manager.toggle("inventory")
	await process_frame
	var menu := _manager.inventory_panel.context_menu
	menu.open_for(_manager.panel_session.current_player.inventory.find(engine.instance_id), player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_maintenance"), "equipment right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_maintenance"))
	var panel: EquipmentMaintenancePanel = _manager.navigation_windows.equipment_maintenance
	_check(panel.visible and not panel.execute_button.disabled, "maintenance visible and available")
	_check(panel.details.text.contains("900 → 891") and panel.details.text.contains("永久降低"), "maximum loss explicit")
	_check(panel.shop.item_count == 6, "six repair tool offers")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_maintenance_panel.png")
	panel._ask()
	_check(panel.confirmation.dialog_text.contains("891"), "confirmation captures consequence")
	panel.confirmation.hide()
	panel._confirm()
	_check(panel.details.text.contains("891 / 891") and panel.execute_button.disabled, "maintenance applied, full state blocked")
	var tool := _manager.panel_session.current_player.inventory.find("maintenance_quickrepairbox1")
	menu.open_for(tool, _fixture._state.inventory_revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_maintenance"), "tool semantic right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_maintenance"))
	_check(panel.mode == "quick" and panel.mode_selector.selected == 1, "tool switches to quick mode")
	var index := -1
	for candidate: int in panel._equipment.size():
		if panel._equipment[candidate].instance_id == player.vehicle.loadout.at(1).instance_id: index = candidate
	panel.equipment_list.item_selected.emit(index)
	_check(not panel.execute_button.disabled and panel.details.text.contains("上限保持不变"), "quick preview")
	panel._ask()
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(_fixture._state).value.vehicle.loadout.at(1).durability == 900, "installed repair")
	panel.quantity.value = 2
	panel._ask_purchase()
	_check(panel._pending.type == "buy_maintenance_tool" and panel.confirmation.dialog_text.contains("合计"), "purchase preview")
	panel.confirmation.hide()
	panel._confirm()
	_check(_fixture._state.currency < 100000, "purchase settled")
	panel._ask_purchase()
	panel.hide()
	_check(panel._pending.is_empty(), "close clears pending")
	_manager.queue_free()
	await process_frame
	print("Equipment maintenance UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 经正式服务结算并将组合消息送回共享会话，仅隔离仓储。
## [param command] 窗口意图。
## 返回权威响应。
func _dispatch(command: Dictionary) -> DomainResult:
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
	if result.is_ok: _manager.panel_session.apply_bundle(result.value)
	return result


## 记录交互断言。
## [param condition] 实际结果。
## [param message] 诊断。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
