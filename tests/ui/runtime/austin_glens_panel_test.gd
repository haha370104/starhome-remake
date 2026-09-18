extends SceneTree

var fixture := PlayerPanelServiceFixture.new()
var commerce := AuthoritativeCommerceService.new()
var manager: GameWindowManager
var checks := 0
var failures := PackedStringArray()


## 延迟创建正式工坊窗口与隔离玩家。
func _initialize() -> void:
	call_deferred("_run")


## 由菜单入口操作成长、左右开孔和永久镶嵌，并核对购买和视口边界。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(fixture.initialize().is_ok and commerce.initialize().is_ok, "initialize")
	var catalog := ItemCatalog.new()
	catalog.initialize()
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	for id: String in catalog.austin_rules.offers:
		player.inventory.add_reward(catalog.create(id, {"instance_id": id, "quantity": 1 if catalog.austin_rules.profiles.has(id) else 99}).value)
	fixture._state = mapper.to_record(player).value
	manager = GameWindowManager.new()
	root.add_child(manager)
	_check(manager.configure(PlayerPanelSession.new(_dispatch, catalog)), "manager")
	manager.toggle("inventory")
	await process_frame
	manager._open_workshop("austin_glens")
	var panel: AustinGlensPanel = manager.navigation_windows.austin_glens
	_check(panel.visible and panel.shop.item_count == 19, "workshop and supply")
	var id := "glory_equipment_austinglens_gh_4c25a84000"
	var menu := manager.inventory_panel.context_menu
	menu.open_for(manager.panel_session.current_player.inventory.find(id), fixture._state.inventory_revision, Vector2(200, 200))
	_check(menu._actions.has("austin_glens"), "equipment right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("austin_glens"))
	_check(panel._id == id and not panel.execute_button.disabled and panel.details.text.contains("100%"), "color preview")
	panel._ask()
	_check(panel._pending.confirmed and panel._pending.type == "change_austin_glens" and panel.confirmation.dialog_text.contains("光魔精华"), "captured actual cost")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.find(id).austin_glens.color == 1, "color upgrade reached authority")
	var revision := fixture._state.inventory_revision
	panel._confirm()
	_check(fixture._state.inventory_revision == revision, "confirmation once")
	for index in [1, 2, 3, 4]:
		panel._select_mode(index)
		_check(not panel.slot_picker.visible and not panel.execute_button.disabled, "independent growth mode")
	panel._select_mode(5)
	panel._select_slot(1)
	_check(panel.slot_picker.visible and panel.details.text.contains("消魔之石 ×4"), "open right cost")
	panel._ask()
	panel.confirmation.hide()
	panel._confirm()
	var item := mapper.to_domain(fixture._state).value.inventory.find(id) as VehicleEquipment
	_check(item.austin_glens.slots[1].opened and not item.austin_glens.slots[0].opened, "only right opened")
	panel._select_mode(6)
	panel.focus_item("austin_totem_rune", true)
	_check(panel.execute_button.disabled, "wrong side rune disabled")
	panel.focus_item("austin_fury_rune", true)
	_check(not panel.execute_button.disabled and panel.material_list.get_item_icon(0) != null, "correct original rune")
	panel._ask()
	_check(panel.confirmation.dialog_text.contains("不能摘取"), "permanent inlay explicit")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(fixture._state).value.inventory.find(id).austin_glens.slots[1].rune_id == "austin_fury_rune", "UI permanent inlay")
	panel._select_mode(3)
	panel.focus_item("glory_equipment_austinglens_ry_a5bd31d824", false)
	_check(panel.execute_button.disabled and panel.details.text.contains("其他玩家"), "PvP-only growth clearly unavailable")
	var body_index := -1
	for index in panel._offers.size():
		if panel._offers[index].definition_id == id: body_index = index
	panel.shop.select(body_index)
	panel._select_offer(body_index)
	_check(panel.quantity.max_value == 1, "unique body purchase")
	var currency := fixture._state.currency
	panel._ask_purchase()
	panel.confirmation.hide()
	panel._confirm()
	_check(fixture._state.currency == currency - 10000, "visible supply purchase")
	panel.focus_item(id, false)
	panel._select_mode(5)
	panel._select_slot(0)
	await process_frame
	_check(panel.details.position.x + panel.details.size.x <= panel.size.x and panel.quantity.position.y + panel.quantity.size.y <= panel.size.y, "layout within panel")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/austin_glens_panel.png")
	root.size = Vector2i(960, 540)
	await process_frame
	panel.clamp_to_viewport(Vector2(960, 540))
	_check(panel.position.x >= 0 and panel.position.y >= 0 and panel.position.x + panel.size.x * panel.scale.x <= 961 and panel.position.y + panel.size.y * panel.scale.y <= 541, "small viewport")
	manager.queue_free()
	await process_frame
	print("Austin UI: %d checks, %d failures" % [checks, failures.size()])
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 通过正式事务提交候选再刷新窗口，避免测试直接写控件结果。
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


## 汇总界面交互断言。
## [param condition] 验证结果。[param message] 场景。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
