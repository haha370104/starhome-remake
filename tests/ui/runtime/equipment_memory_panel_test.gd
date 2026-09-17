extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0


## 等待场景树构建后进行完整界面测试。
func _initialize() -> void:
	call_deferred("_run")


## 验证右键定位、模式、稳压剂概率、冻结确认和实际成长去向。
func _run() -> void:
	root.size = Vector2i(1200, 840)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "初始化")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.inventory.add_reward(items.create("beginner_engine", {"instance_id": "source", "strengthening": {"level": 3}}).value)
	player.inventory.add_reward(items.create("equipment_memory_strengthening", {"instance_id": "module"}).value)
	player.inventory.add_reward(items.create("equipment_memory_stabilizer", {"instance_id": "stabilizer", "quantity": 2}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "会话")
	_manager.toggle("inventory")
	await process_frame
	_manager._open_workshop("equipment_memory")
	var panel: EquipmentMemoryPanel = _manager.navigation_windows.equipment_memory
	_check(panel.visible and panel.shop.item_count == 7, "获取入口和七种商品")
	var menu := _manager.inventory_panel.context_menu
	for id: String in ["source", "module"]:
		menu.open_for(_manager.panel_session.current_player.inventory.find(id), player.inventory.revision, Vector2(200, 200))
		_check(menu._actions.has("equipment_memory"), "右键入口")
		menu.menu.hide()
		menu._select_action(menu._actions.find("equipment_memory"))
	_check(not panel.execute_button.disabled and panel.details.text.contains("80%") and panel.details.text.contains("3星"), "普通提取预览")
	panel.stabilizer.button_pressed = true
	_check(panel.details.text.contains("100%") and panel.details.text.contains("原装备保留"), "稳压剂权威概率")
	_check(panel.material_list.get_item_icon(0) != null, "模块原图")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/equipment_memory_panel.png")
	panel._ask()
	panel.stabilizer.button_pressed = false
	_check(panel._pending.use_stabilizer and panel._pending.confirm_transfer and panel._pending.mode == "extract", "确认后不改变所选费用")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(_fixture._state).value.inventory.find("source").strengthening.level == 0, "提取真实清除原成长")
	_check(panel.material_list.get_item_text(0).contains("已载入"), "模块状态可见")
	panel.mode_selector.select(1)
	panel._select_mode(1)
	panel.focus_item("inventory.spare_engine", false)
	panel.stabilizer.button_pressed = true
	_check(panel.details.text.contains("模块成长写入目标") and not panel.execute_button.disabled, "转移目标预览")
	panel._ask()
	panel.confirmation.hide()
	panel._confirm()
	var restored: Player = mapper.to_domain(_fixture._state).value
	_check(restored.inventory.find("module") == null and restored.inventory.find("inventory.spare_engine").strengthening.level == 3, "转移和销毁模块")
	var revision := _fixture._state.inventory_revision
	panel._confirm()
	_check(_fixture._state.inventory_revision == revision, "不重复提交")
	for index in panel._offers.size():
		if panel._offers[index].definition_id == "equipment_memory_strengthening":
			panel.shop.select(index)
			panel._select_offer(index)
	_check(panel.quantity.max_value == 1, "唯一模块限购一个")
	panel._ask_purchase()
	panel.confirmation.hide()
	panel._confirm()
	_check(_fixture._state.currency == 980, "购买原价模块")
	panel._ask_purchase()
	panel.hide()
	_check(panel._pending.is_empty(), "关闭清理确认")
	_manager.queue_free()
	await process_frame
	print("Equipment memory UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 通过正式服务分派界面意图，同步共享会话。
## [param command] 界面提交的选择。
## 返回权威快照。
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


## 记录完整交互的断言。
## [param condition] 期望结果。
## [param message] 诊断。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
