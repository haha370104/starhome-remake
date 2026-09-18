extends SceneTree

var fixture := PlayerPanelServiceFixture.new()
var commerce := AuthoritativeCommerceService.new()
var manager: GameWindowManager
var checks := 0
var failures := PackedStringArray()


## 延迟构建正式窗口。
func _initialize() -> void:
	call_deferred("_run")


## 通过正式窗口验证图标、模块消费、核心进化和圣焱装配，不把规则复制到UI。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(fixture.initialize().is_ok and commerce.initialize().is_ok, "initialize")
	var catalog := ItemCatalog.new()
	catalog.initialize()
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	for id: String in CentralRules.CHIP_IDS:
		if id == "gun": continue
		player.central.use_module(catalog.central_rules.modules["central_%s_module_1" % id])
		player.central.use_module(catalog.central_rules.modules["central_%s_module_3" % id])
	for id: String in ["central_gun_module_1", "central_gun_module_3", "central_evolution_crystal", "central_flamefire", "central_syancrystal"]:
		player.inventory.add_reward(catalog.create(id, {"instance_id":id}).value)
	fixture._state = mapper.to_record(player).value
	manager = GameWindowManager.new()
	root.add_child(manager)
	_check(manager.configure(PlayerPanelSession.new(_dispatch, catalog)), "manager")
	manager.toggle("inventory")
	await process_frame
	_check(manager.toggle("central_controller"), "original HUD action resolves to window")
	var panel: CentralPanel = manager.navigation_windows.central_controller
	_check(panel.visible and panel.shop.item_count == 31 and panel.material_list.item_count == 6, "supply and all chips")
	for index in 6: _check(panel.material_list.get_item_icon(index) != null, "original chip artwork")
	panel._select_material(2)
	_check(panel.details.text.contains("致命一击") and panel.execute_button.disabled, "chip reading cannot spend item")
	var menu := manager.inventory_panel.context_menu
	menu.open_for(manager.panel_session.current_player.inventory.find("central_gun_module_1"), fixture._state.inventory_revision, Vector2(200,200))
	_check(menu._actions.has("central_controller"), "module right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("central_controller"))
	_check(panel._id == "central_gun_module_1" and not panel.execute_button.disabled, "right click locates real module")
	panel._ask()
	_check(panel._pending.confirmed and panel.confirmation.dialog_text.contains("未激活 → 1级"), "captured activation cost")
	panel.confirmation.hide()
	panel._confirm()
	_check(fixture._state.central.grade("gun") == 1, "module consumes through authority")
	var revision := fixture._state.inventory_revision
	panel._confirm()
	_check(fixture._state.inventory_revision == revision, "confirmation sends once")
	for id: String in ["central_gun_module_3", "central_evolution_crystal"]:
		panel.focus_item(id)
		panel._ask()
		panel.confirmation.hide()
		panel._confirm()
	_check(fixture._state.central.evolved and panel._summary.text.contains("圣焱型"), "core evolves via UI")
	panel.focus_item("central_flamefire")
	_check(panel.details.text.contains("圣焱核晶 ×1") and not panel.equip_button.disabled, "growth and independent slot action")
	panel._ask()
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.find("central_flamefire").central_growth.grade == 1, "accessory upgrade")
	panel._install()
	_check(mapper.to_domain(fixture._state).value.vehicle.loadout.at(45) != null and not panel.unequip_button.disabled and panel.equip_button.disabled, "actual equip and current buttons")
	panel._uninstall()
	_check(mapper.to_domain(fixture._state).value.inventory.find("central_flamefire") != null and not panel.equip_button.disabled, "actual unequip")
	panel._select_material(2)
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/central_panel.png")
	root.size = Vector2i(960,540)
	await process_frame
	panel.clamp_to_viewport(Vector2(960,540))
	_check(panel.position.x >= 0 and panel.position.y >= 0 and panel.position.x + panel.size.x * panel.scale.x <= 961 and panel.position.y + panel.size.y * panel.scale.y <= 541, "small viewport")
	manager.queue_free()
	await process_frame
	print("Central UI: %d checks, %d failures" % [checks, failures.size()])
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
