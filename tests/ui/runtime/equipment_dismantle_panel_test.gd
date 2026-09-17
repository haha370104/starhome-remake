extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0


## 延迟创建真实面板组合。
func _initialize() -> void:
	call_deferred("_run")


## 验证菜单、返还预览、风险确认、实际拆解和重复确认保护。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "initialize")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.inventory.add_reward(items.create("glory_equipment_tank7_6dce9d1c52", {"instance_id": "source", "equipment_quality": {"version": 1, "grade": 1}}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "session")
	_manager.toggle("inventory")
	await process_frame
	_manager._open_workshop("equipment_dismantle")
	var panel: EquipmentDismantlePanel = _manager.navigation_windows.equipment_dismantle
	_check(panel.visible and panel.execute_button.disabled, "empty selection")
	var menu := _manager.inventory_panel.context_menu
	menu.open_for(_manager.panel_session.current_player.inventory.find("source"), player.inventory.revision, Vector2(200, 200))
	_check(menu._actions.has("equipment_dismantle"), "right click")
	menu.menu.hide()
	menu._select_action(menu._actions.find("equipment_dismantle"))
	_check(not panel.execute_button.disabled and panel.details.text.contains("20%：无材料返还"), "all probability branches")
	_check(panel.material_list.item_count == 3 and panel.material_list.mouse_filter == Control.MOUSE_FILTER_IGNORE, "outcomes are readonly")
	_check(panel.material_list.get_item_icon(0) != null, "original material image")
	_check(panel.equipment_list.get_item_text(0).contains("绿色"), "visible equipment quality")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_dismantle_panel.png")
	panel._ask()
	_check(panel._pending.confirm_destruction and panel.confirmation.dialog_text.contains("晶石永久消失"), "explicit destruction confirmation")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(_fixture._state).value.inventory.find("source") == null, "actual removal")
	_check(_fixture._state.currency == 800, "actual cost")
	var revision := _fixture._state.inventory_revision
	panel._confirm()
	_check(_fixture._state.inventory_revision == revision and panel.execute_button.disabled, "duplicate confirmation safe")
	_manager.queue_free()
	await process_frame
	print("Equipment dismantle UI: %d checks, %d failures" % [_checks, _failures])
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
