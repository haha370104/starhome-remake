extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _commerce := AuthoritativeCommerceService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0


## 等待窗口节点构建后验证交互。
func _initialize() -> void:
	call_deferred("_run")


## 使用真实窗口、菜单和权威服务验证服装改良及批量购买。
func _run() -> void:
	root.size = Vector2i(1200, 840)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _commerce.initialize().is_ok, "初始化")
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.inventory.currency = 1000000
	var fashion := ""
	for id: String in items.clothing_improvement_rules.slots:
		if items.definition(id).required_sex == "male" and items.clothing_improvement_rules.slots[id] == "upper_body":
			fashion = id
			break
	_check(player.inventory.add_reward(items.create(fashion, {"instance_id": "fashion"}).value).is_ok, "时装")
	_check(player.inventory.add_reward(items.create("clothing_fiber_defense", {"instance_id": "fiber", "quantity": 20}).value).is_ok, "纤维")
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "配置会话")
	_manager.toggle("inventory")
	await process_frame
	_manager._open_equipment_processing("inventory.spare_engine", false)
	var basic: EquipmentProcessingPanel = _manager.navigation_windows.equipment_processing
	basic._select_workshop(EquipmentWorkshopNavigation.PROJECTS.keys().find("clothing_improvement"))
	var panel: ClothingImprovementPanel = _manager.navigation_windows.clothing_improvement
	_check(panel.visible and panel.shop.item_count > 20, "无材料也可进入获取链")
	basic.hide()
	var menu := _manager.inventory_panel.context_menu
	for id: String in ["fashion", "fiber"]:
		menu.open_for(_manager.panel_session.current_player.inventory.find(id), player.inventory.revision, Vector2(200, 200))
		_check(menu._actions.has("clothing_improvement"), "专属右键入口")
		menu.menu.hide()
		menu._select_action(menu._actions.find("clothing_improvement"))
	_check(not panel.execute_button.disabled and panel.details.text.contains("100%") and panel.details.text.contains("防御：+0.0 → +1.0"), "成功率和实际收益")
	_check(panel.material_list.get_item_icon(0) != null, "原版纤维图")
	_check(panel.stone_quantity.max_value == 1048576, "允许完整材料阶梯")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/clothing_improvement_panel.png")
	panel.stone_quantity.value = 1
	_check(panel.details.text.contains("50%"), "改变投入查询新概率")
	panel.stone_quantity.value = 2
	panel._ask()
	panel.stone_quantity.value = 1
	_check(panel._pending.material_quantity == 2, "确认固定投入")
	panel.confirmation.hide()
	panel._confirm()
	_check(mapper.to_domain(_fixture._state).value.inventory.find("fashion").improvement.level == 1, "真实改良")
	var current := _manager.panel_session.current_player
	_check(EquipmentTooltipFormatter.format(current.inventory.find("fashion").to_view_dictionary()).contains("时装改良 1级：防御 +1"), "悬浮说明")
	var revision := _fixture._state.inventory_revision
	panel._confirm()
	_check(_fixture._state.inventory_revision == revision, "重复确认无效")
	for index in panel._offers.size():
		if panel._offers[index].definition_id == "clothing_fiber_defense":
			panel.shop.select(index)
			panel._select_offer(index)
	panel.quantity.value = 9999
	panel._ask_purchase()
	_check(panel._pending.quantity == 9999 and panel.confirmation.dialog_text.contains("199980"), "大批量价格预览")
	panel.confirmation.hide()
	panel._confirm()
	_check(_fixture._state.currency == 800020, "按报价实际购买")
	for index in panel._offers.size():
		if panel._offers[index].definition_id == fashion:
			panel.shop.select(index)
			panel._select_offer(index)
	_check(panel.quantity.max_value == 1 and panel.quantity.value == 1, "时装每次一件")
	panel._ask_purchase()
	panel.hide()
	_check(panel._pending.is_empty(), "关闭清理确认")
	_manager.queue_free()
	await process_frame
	print("Clothing improvement UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 使用正式服务结算，测试仅替换存档仓储。
## [param command] 界面意图。
## 返回权威响应并同步共享会话。
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


## 记录完整交互链中的行为断言。
## [param condition] 实际结果。
## [param message] 诊断。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
