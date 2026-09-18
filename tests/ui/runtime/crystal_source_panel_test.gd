extends SceneTree

var fixture := PlayerPanelServiceFixture.new()
var commerce := AuthoritativeCommerceService.new()
var manager: GameWindowManager
var checks := 0
var failures := PackedStringArray()


## 延迟创建真实窗口组合，使用隔离玩家与正式商贸服务。
func _initialize() -> void:
	call_deferred("_run")


## 检查菜单、三孔操作、品质/成长、五合一及材料购买的实际交互。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(fixture.initialize().is_ok and commerce.initialize().is_ok, "initialization")
	var catalog := ItemCatalog.new()
	catalog.initialize()
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	player.inventory.add_reward(catalog.create("glory_equipment_newequip_shan_e010f43b10", {"instance_id": "source"}).value)
	player.inventory.add_reward(catalog.create("crystal_source_core_red_1", {"instance_id": "red", "quantity": 10}).value)
	player.inventory.add_reward(catalog.create("crystal_source_core_yellow_2", {"instance_id": "yellow", "quantity": 2}).value)
	player.inventory.add_reward(catalog.create("crystal_source_core_stabilizer", {"instance_id": "stable", "quantity": 4}).value)
	fixture._state = mapper.to_record(player).value
	manager = GameWindowManager.new()
	root.add_child(manager)
	_check(manager.configure(PlayerPanelSession.new(_dispatch, catalog)), "manager")
	manager.toggle("inventory")
	await process_frame
	manager._open_workshop("crystal_source")
	var panel: CrystalSourcePanel = manager.navigation_windows.crystal_source
	_check(panel.visible and panel.shop.item_count == 11, "entry and full supply list")
	var menu := manager.inventory_panel.context_menu
	menu.open_for(manager.panel_session.current_player.inventory.find("source"), fixture._state.inventory_revision, Vector2(200, 200))
	_check(menu._actions.has("crystal_source"), "equipment context menu")
	menu.menu.hide()
	menu._select_action(menu._actions.find("crystal_source"))
	_check(panel._id == "source" and panel.details.text.contains("品质") and panel.execute_button.disabled, "quality quote without materials")
	panel._select_mode(1)
	_check(panel.details.text.contains("成长") and not panel.protection.visible and not panel.slot_picker.visible, "growth mode")
	panel._select_mode(2)
	panel.focus_item("red", true)
	_check(not panel.execute_button.disabled and panel.slot_picker.visible and panel.material_list.get_item_icon(0) != null, "inlay with original core icons")
	panel._select_slot(2)
	panel._ask()
	_check(panel._pending.type == "inlay_crystal_source" and panel._pending.index == 2 and panel._pending.confirmed, "captures correct core slot")
	panel.confirmation.hide()
	panel._confirm()
	player = mapper.to_domain(fixture._state).value
	_check(player.inventory.find("source").crystal_source.slots[2].definition_id == "crystal_source_core_red_1", "actual slot two inlay")
	var revision := fixture._state.inventory_revision
	panel._confirm()
	_check(fixture._state.inventory_revision == revision, "single confirmation")
	panel._select_mode(3)
	_check(panel.details.text.contains("0 → 1") and not panel.execute_button.disabled, "extraction warning")
	panel._ask()
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.find("source").crystal_source.slots[2].definition_id.is_empty(), "extract clears selected slot")
	panel._select_mode(4)
	panel.stabilizer_count.value = 4
	_check(panel.details.text.contains("100%") and panel.stabilizer_count.visible and not panel.protection.visible, "stabilizer preview")
	_check(not panel.execute_button.disabled and panel.details.text.contains("最高合成5级"), "five-to-one cap visible")
	panel._ask()
	_check(panel._pending.stabilizers == 4 and panel.confirmation.dialog_text.contains("失败消耗五枚核心"), "composition confirmation")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.count_definition("crystal_source_core_red_2") == 1, "UI composition reaches authority")
	panel._select_mode(0)
	var body_index := -1
	for index in panel._offers.size():
		if panel._offers[index].definition_id == "glory_equipment_newequip_shan_e010f43b10": body_index = index
	panel.shop.select(body_index)
	panel._select_offer(body_index)
	_check(panel.quantity.max_value == 1, "body purchase only one")
	var currency := fixture._state.currency
	panel._ask_purchase()
	_check(panel.confirmation.dialog_text.contains("50000"), "server supply price displayed")
	panel.confirmation.hide()
	panel._confirm()
	_check(fixture._state.currency == currency - 50000, "body bought at authoritative price")
	panel._select_mode(2)
	panel.focus_item("yellow", true)
	panel._select_slot(0)
	await process_frame
	_check(panel.details.position.x + panel.details.size.x <= panel.size.x and panel.quantity.position.y + panel.quantity.size.y <= panel.size.y, "details and purchasing remain in window")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/crystal_source_panel.png")
	root.size = Vector2i(960, 540)
	await process_frame
	panel.clamp_to_viewport(Vector2(960, 540))
	_check(panel.position.x >= 0 and panel.position.y >= 0 and panel.position.x + panel.size.x * panel.scale.x <= 961 and panel.position.y + panel.size.y * panel.scale.y <= 541, "small viewport whole window")
	manager.queue_free()
	await process_frame
	print("Crystal source UI: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 在同一会话内使用正式权威商贸事务并回传已提交候选的统一快照。
## [param command] 界面意图。
## 返回事务结果。
func _dispatch(command: Dictionary) -> DomainResult:
	if commerce.handles(String(command.get("type", ""))):
		var result := commerce.execute(fixture._state, command)
		if not result.is_ok: return result
		if result.value.changed:
			fixture._state = result.value.candidate
			fixture._state.revision += 1
		var bundle := commerce.build_bundle(fixture._state, result.value.operation)
		manager.panel_session.apply_bundle(bundle)
		return DomainResult.ok(bundle)
	var result := fixture.execute(command)
	if result.is_ok: manager.panel_session.apply_bundle(result.value)
	return result


## 汇总交互断言，保留所有失败位置。
## [param condition] 预期条件。[param label] 故障描述。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
