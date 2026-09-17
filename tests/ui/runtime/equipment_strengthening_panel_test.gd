extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0


## 等待窗口树构建。
func _initialize() -> void:
	call_deferred("_run")


## 验证独立强化原图、投入数量、费用预览、加工及购买的完整窗口链。
func _run() -> void:
	root.size = Vector2i(1200, 840)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "services")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	var engine := player.inventory.find("inventory.spare_engine") as Equipment
	var stone_id: String = engine.strengthening_profile.ordinary_material
	for cost: Dictionary in [{"definition_id": engine.strengthening_profile.alloy_id, "quantity": 600}, {"definition_id": stone_id, "quantity": 8}]:
		var remaining := int(cost.quantity)
		var serial := 0
		while remaining > 0:
			var item: GameItem = items.create(cost.definition_id, {"instance_id": cost.definition_id + str(serial)}).value
			item.quantity = mini(item.max_stack, remaining)
			remaining -= item.quantity
			serial += 1
			_check(player.inventory.add_reward(item).is_ok, "give")
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "manager")
	_manager.toggle("inventory")
	await process_frame
	var menu := _manager.inventory_panel.context_menu
	menu.open_for(_manager.panel_session.current_player.inventory.find(engine.instance_id), player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_strengthening"), "eligible equipment right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_strengthening"))
	var panel: EquipmentStrengtheningPanel = _manager.navigation_windows.equipment_strengthening
	_check(panel.visible and panel.execute_button.disabled, "target selected, still requires material")
	var material := _manager.panel_session.current_player.inventory.find(stone_id + "0")
	menu.open_for(material, player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_strengthening"), "material semantic right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_strengthening"))
	_check(not panel.execute_button.disabled and panel.details.text.contains("100000"), "affordable preview")
	_check(panel.details.text.contains("100%") and panel.details.text.contains("推进力加成：+0 → +2"), "actual increase and probability")
	_check(panel.shop.item_count == 9 and panel.material_list.get_item_icon(0) != null, "original images and all offers")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_strengthening_panel.png")
	panel.stone_quantity.value = 1
	_check(panel.details.text.contains("30%"), "selected quantity refreshes authority probability")
	panel.stone_quantity.value = 4
	panel._ask()
	panel.stone_quantity.value = 1
	_check(panel._pending.material_quantity == 4, "confirmation keeps captured quantity")
	_check(panel._pending.type == "strengthen_equipment" and panel.confirmation.dialog_text.contains("失败"), "consequences confirmed")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(_fixture._state).value.inventory.find(engine.instance_id).strengthening.level == 1, "actual growth")
	_check(panel.details.text.contains("星级：1 → 2"), "refreshed preview")
	var revision := _fixture._state.inventory_revision
	panel._confirm()
	_check(_fixture._state.inventory_revision == revision, "duplicate confirm ignored")
	for index: int in panel._offers.size():
		if panel._offers[index].definition_id == stone_id: panel.shop.select(index)
	panel.quantity.value = 2
	panel._ask_purchase()
	_check(panel._pending.type == "buy_equipment_strengthening_material" and panel.confirmation.dialog_text.contains("40000"), "purchase quote")
	panel.confirmation.hide()
	panel._confirm()
	_check(_fixture._state.currency == 860000, "purchase settled")
	panel._ask()
	panel.hide()
	_check(panel._pending.is_empty(), "close clears confirmation")
	_manager.queue_free()
	await process_frame
	print("Equipment strengthening UI: %d checks, %d failures" % [_checks, _failures])
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
