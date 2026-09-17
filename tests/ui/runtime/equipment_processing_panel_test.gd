extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0
var _executions := 0


## 等待 UI 树创建后运行隔离服务与窗口交互。
func _initialize() -> void:
	call_deferred("_run")


## 从背包右键进入加工，验证预览、材料图像、确认和实际属性变化。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "services")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.skills = SkillBook.new({"processing": 1000})
	var engine: VehicleEquipment = player.inventory.find("inventory.spare_engine")
	for cost: Dictionary in items.processing_rules.profile(engine.definition_id).attributes.drive.materials:
		player.inventory.add_reward(items.create(cost.definition_id, {"instance_id": cost.definition_id, "quantity": cost.quantity * 2}).value)
	player.inventory.add_reward(items.create("item:material:02212ea88168", {"instance_id": "magnet", "quantity": 2}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "manager")
	_manager.toggle("inventory")
	await process_frame
	var menu := _manager.inventory_panel.context_menu
	menu.open_for(_manager.panel_session.current_player.inventory.find(engine.instance_id), player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_processing"), "right click processing")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_processing"))
	var panel: EquipmentProcessingPanel = _manager.navigation_windows.equipment_processing
	_check(panel.visible and _manager.inventory_panel.visible, "independent panel")
	_check(panel.details.text.contains("推进力：20 / 28"), "current and cap")
	var index := -1
	for candidate: int in panel._materials.size():
		if panel._materials[candidate].instance_id == "magnet": index = candidate
	_check(index >= 0, "material present")
	panel.material_list.item_selected.emit(index)
	_check(not panel.execute_button.disabled and panel.details.text.contains("20 → 22"), "authoritative preview")
	_check(panel.details.text.contains("复合胶板") and panel.details.text.contains("100%"), "cost and chance visible")
	_check(panel.material_list.get_item_icon(index) != null, "material icon")
	await process_frame
	_check(panel.details.get_rect().end.x < panel.size.x and panel.details.get_rect().end.y < panel.size.y, "details contained")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_processing_panel.png")
	panel._ask()
	_check(panel.confirmation.visible and panel._pending.inventory_revision == _fixture._state.inventory_revision, "confirmation")
	_fixture._state.revision += 8
	panel.confirmation.hide()
	panel._confirm()
	panel._confirm()
	_check(_executions == 1, "exactly once submission")
	_check(panel.details.text.contains("推进力：22 / 28"), "processed value displayed")
	_check((mapper.to_domain(_fixture._state).value.inventory.find(engine.instance_id) as VehicleEngine).drive == 22, "saved engine changed")
	panel._ask()
	panel.hide()
	_check(panel._pending.is_empty() and not panel.confirmation.visible, "close cancels pending")
	_manager.queue_free()
	await process_frame
	print("Equipment processing UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 仅替换存档载体，窗口仍通过共享会话调用正式服务。
## [param command] 界面意图。
## 返回服务器组合快照或错误。
func _dispatch(command: Dictionary) -> DomainResult:
	if _commerce.handles(String(command.get("type", ""))):
		if command.type == "process_equipment_attribute": _executions += 1
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


## 记录界面与交互断言。
## [param condition] 实际结果。
## [param message] 诊断。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
