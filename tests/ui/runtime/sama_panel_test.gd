extends SceneTree

var fixture := PlayerPanelServiceFixture.new()
var commerce := AuthoritativeCommerceService.new()
var manager: GameWindowManager
var checks := 0
var failures := PackedStringArray()


## 延迟构建正式窗口。
func _initialize() -> void:
	call_deferred("_run")


## 通过原图列表操作阶段、品质和来源销毁，核对确认与小视口。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(fixture.initialize().is_ok and commerce.initialize().is_ok, "initialize")
	var catalog := ItemCatalog.new()
	catalog.initialize()
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	player.amethyst = AmethystWallet.new(1000)
	var target_id := "glory_equipment_samamcq_cdd4a0d041"
	var donor_id := "glory_equipment_samajnq_1011d2a44c"
	player.inventory.add_reward(catalog.create(target_id, {"instance_id":"target", "sama":{"version":1,"color":3,"growth":0,"quality":0}}).value)
	player.inventory.add_reward(catalog.create(donor_id, {"instance_id":"donor"}).value)
	for id: String in catalog.sama_rules.materials.values():
		player.inventory.add_reward(catalog.create(id, {"instance_id":id, "quantity":99}).value)
	fixture._state = mapper.to_record(player).value
	manager = GameWindowManager.new()
	root.add_child(manager)
	_check(manager.configure(PlayerPanelSession.new(_dispatch, catalog)), "manager")
	manager.toggle("inventory")
	await process_frame
	manager._open_workshop("sama")
	var panel: SamaPanel = manager.navigation_windows.sama
	_check(panel.visible and panel.shop.item_count == 19, "all supply colors")
	var menu := manager.inventory_panel.context_menu
	menu.open_for(manager.panel_session.current_player.inventory.find("donor"), fixture._state.inventory_revision, Vector2(200,200))
	_check(menu._actions.has("sama"), "right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("sama"))
	_check(panel._id == "donor" and not panel.execute_button.disabled and panel.details.text.contains("动力核心 ×5"), "growth preview")
	panel._ask()
	_check(panel._pending.confirmed and panel.confirmation.dialog_text.contains("100%"), "captured actual costs")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.find("donor").sama.growth == 1, "growth reached authority")
	var revision := fixture._state.inventory_revision
	panel._confirm()
	_check(fixture._state.inventory_revision == revision, "confirmation once")
	panel._select_mode(1)
	_check(panel.details.text.contains("智能核心 ×6"), "quality original cost")
	panel._ask()
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.find("donor").bound, "bound quality")
	panel._select_mode(2)
	panel.focus_item("target", false)
	panel.focus_item("donor", true)
	_check(not panel.execute_button.disabled and panel.material_list.get_item_icon(0) != null, "original source image and valid transfer")
	panel._ask()
	_check(panel.confirmation.dialog_text.contains("消失") and panel.confirmation.dialog_text.contains("1000") and panel.confirmation.dialog_text.contains("覆盖"), "destruction and overwrite stated")
	panel.confirmation.hide()
	panel._confirm()
	player = mapper.to_domain(fixture._state).value
	_check(player.inventory.find("donor") == null and player.inventory.find("target").sama.quality == 1 and player.amethyst.balance() == 0, "transfer through UI")
	panel.focus_item("target", false)
	panel._select_mode(0)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/sama_panel.png")
	root.size = Vector2i(960,540)
	await process_frame
	panel.clamp_to_viewport(Vector2(960,540))
	_check(panel.position.x >= 0 and panel.position.y >= 0 and panel.position.x + panel.size.x * panel.scale.x <= 961 and panel.position.y + panel.size.y * panel.scale.y <= 541, "small viewport")
	manager.queue_free()
	await process_frame
	print("Sama UI: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 由正式服务提交候选并刷新窗口。
## [param command] UI意图。
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


## 汇总界面交互结果。
## [param condition] 结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
