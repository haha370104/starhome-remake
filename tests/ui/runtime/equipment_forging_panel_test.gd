extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0


## 延迟创建真实面板组合。
func _initialize() -> void:
	call_deferred("_run")


## 验证菜单、返还预览、风险确认、实际锻造和重复确认保护。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "initialize")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.inventory = Inventory.new(40, 0, 1000000)
	player.inventory.add_reward(items.create("beginner_engine", {"instance_id": "source", "processing": {"increments": {"drive": 3}}}).value)
	player.inventory.add_reward(items.create("equipment_forging_drive", {"instance_id": "chip", "quantity": 3}).value)
	var cost: Dictionary = items.forging_rules.channels[2].requirements[0]
	player.inventory.add_reward(items.create(cost.definition_id, {"instance_id": "alloy", "quantity": 100}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "session")
	_manager.toggle("inventory")
	await process_frame
	_manager._open_workshop("equipment_forging")
	var panel: EquipmentForgingPanel = _manager.navigation_windows.equipment_forging
	_check(panel.visible and panel.execute_button.disabled, "empty selection")
	var menu := _manager.inventory_panel.context_menu
	menu.open_for(_manager.panel_session.current_player.inventory.find("source"), player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_forging"), "right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_forging"))
	panel.focus_item("chip", true)
	_check(not panel.execute_button.disabled and panel.details.text.contains("95%"), "original probability")
	_check(panel.stone_quantity.max_value == 3, "three chips maximum")
	_check(panel.material_list.item_count == 1 and panel.material_list.get_item_icon(0) != null, "original chip icon")
	_check(panel.shop.item_count == 10 and panel.purchase_quantity_limit == 999, "complete supplies")
	_check(panel.details.text.contains("推进+3"), "explicit processing loss")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_forging_panel.png")
	panel._ask()
	_check(panel._pending.confirm_processing_loss and panel.confirmation.dialog_text.contains("清除全部普通加工"), "explicit destruction confirmation")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(_fixture._state).value.inventory.find("source").processing.bonus("drive") == 0, "actual removal")
	_check(_fixture._state.currency == 900000, "actual cost")
	var revision := _fixture._state.inventory_revision
	panel._confirm()
	_check(_fixture._state.inventory_revision == revision and panel.execute_button.disabled, "duplicate confirmation safe")
	_manager.queue_free()
	await process_frame
	print("Equipment forging UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 用正式事务服务结算并同步统一玩家会话。
## [param command] 界面意图。
## 返回最新快照。
func _dispatch(command: Dictionary) -> DomainResult:
	if _commerce.handles(String(command.get("type", ""))):
		var result := _commerce.execute(_fixture._state, command)
		if not result.is_ok: return result
		if result.value.changed:
			_fixture._state = result.value.candidate
			_fixture._state.revision += 1
		var bundle := _commerce.build_bundle(_fixture._state, result.value.operation)
		_manager.panel_session.apply_bundle(bundle)
		return DomainResult.ok(bundle)
	var result := _fixture.execute(command)
	if result.is_ok: _manager.panel_session.apply_bundle(result.value)
	return result


## 累计界面断言。
## [param condition] 期望值。
## [param message] 故障标签。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
