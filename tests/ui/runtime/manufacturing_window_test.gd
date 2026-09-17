extends SceneTree

var checks := 0
var failures: Array[String] = []
var server := AuthoritativeServer.new()
var config := DedicatedServerConfig.new()
var manager: GameWindowManager
var panel: ManufacturingWindow
var entity_id := ""
var commands: Array[Dictionary] = []
var reject_once := false
var iron: ManufacturingRecipe


## 延迟创建真实服务器、窗口管理器和隔离存档。
func _initialize() -> void:
	call_deferred("_run")


## 从实际按钮验证订单而非检查控件存在，包含时钟入账和过期确认。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	config.network_enabled = false
	config.map_config_path = "res://content/glory/map_definitions/glory_nft_bl_factory1.json"
	config.default_spawn = Vector2(1104, 420)
	config.player_state_store_path = "res://.godot/production-ui-%d.json" % Time.get_ticks_usec()
	_check(server.initialize(config).ok, "权威服务器初始化")
	_check(server.open_session(71, {"protocol_version": config.protocol_version, "content_version": config.content_version}).ok, "隔离账号")
	entity_id = server.sessions.session_for_peer(71).entity_id
	for recipe: ManufacturingRecipe in server.manufacturing_service._recipe_book.recipes_for_station("refining"):
		if server.manufacturing_service._item_catalog.display_name(recipe.product_definition_id) == "铁": iron = recipe
	_check(iron != null, "实际配方")
	var player: Player = server.manufacturing_service._mapper.to_domain(_state()).value
	player.inventory = Inventory.new()
	player.skills = SkillBook.new({"refining": 100})
	player.inventory.add_reward(server.manufacturing_service._item_catalog.create(iron.materials[0].definition_id, {"instance_id": "ui.ore", "quantity": 90}).value)
	server.autosave_service.commit_player_state(entity_id, server.manufacturing_service._mapper.to_record(player).value)
	manager = GameWindowManager.new()
	root.add_child(manager)
	_check(manager.configure(PlayerPanelSession.new(_dispatch)), "实际会话")
	server.server_message_generated.connect(_receive)
	manager.open_manufacturing("refining")
	panel = manager.manufacturing_window
	_check(panel.visible and panel._snapshot.available and panel.station_id() == "refining", "设施打开完整生产状态")
	_check(panel.start_button.disabled, "未选配方不可开始")
	_select_iron()
	panel.speed.value = 10
	_check(panel.start_button.disabled, "材料不足一轮不能开始")
	panel.speed.value = 2
	panel.cycles.value = 4
	_check(panel.details.text.contains("90 / 20 / 80") and panel.details.text.contains("总计最多：8"), "单轮和整单预览")
	_check(panel.details.text.contains("速度不增加经验"), "经验规则明确")
	panel.cycles.get_line_edit().text = "4"
	panel.speed.get_line_edit().text = "2"
	panel.start_button.pressed.emit()
	_check(_state().production.order != null and _state().production.order.cycles == 4 and _state().production.order.speed == 2, "手工输入被正式提交")
	_check(panel.start_button.disabled and not panel.pause_button.disabled and _quantity() == 0, "开始只等待不产出")
	server.advance_simulation(1.0)
	panel._query()
	_check(panel.progress.value == 50 and _quantity() == 0, "服务端剩余一半时显示一半")
	server.advance_simulation(1.0)
	_check(panel._snapshot.production.order.completed == 1 and _quantity() == 2, "服务端推送真实首轮")
	_check(manager.panel_session.current_player.inventory.count_definition(iron.product_definition_id) == 2, "背包同一事务更新")
	_check(panel.cycles.value == 4 and panel.speed.value == 2, "推送保留用户输入")
	panel.pause_button.pressed.emit()
	_check(_state().production.order.paused and panel.pause_button.text == "继续生产", "按钮实际暂停")
	server.advance_simulation(3.0)
	_check(_quantity() == 2, "暂停不生产")
	panel.pause_button.pressed.emit()
	_check(not _state().production.order.paused, "按钮实际继续")
	panel.cancel_button.pressed.emit()
	_check(panel.confirmation.visible and panel.confirmation.dialog_text.contains("剩余3轮"), "取消明确剩余轮次")
	panel.confirmation.canceled.emit()
	panel.confirmation.hide()
	panel._confirm_cancel()
	_check(_state().production.order != null, "放弃取消不删订单")
	panel.cancel_button.pressed.emit()
	server.advance_simulation(2.0)
	panel.confirmation.hide()
	panel.confirmation.confirmed.emit()
	_check(_state().production.order.completed == 2 and not panel.cancel_button.disabled, "确认期间进度变更拒绝旧意图并刷新")
	var command_count := commands.size()
	panel._confirm_cancel()
	_check(commands.size() == command_count, "确认不重发")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/manufacturing_window.png")
	panel.cancel_button.pressed.emit()
	panel.confirmation.hide()
	panel.confirmation.confirmed.emit()
	_check(_state().production.order == null and _quantity() == 4 and not panel.start_button.disabled, "取消保留已完成产物")
	panel.cycles.value = 1
	panel.speed.value = 1
	await process_frame
	reject_once = true
	panel.start_button.pressed.emit()
	_check(_state().production.order == null and not panel.start_button.disabled, "失败后查询恢复操作且没有预测成果")
	panel.start_button.pressed.emit()
	_check(_state().production.order != null and _state().production.order.cycles == 1 and _state().production.order.speed == 1, "恢复后可按新输入重新开始")
	panel.hide()
	server.advance_simulation(2.0)
	_check(_quantity() == 5 and _state().production.order == null, "关闭窗口后订单仍完成")
	_check(not server.manufacturing_service.handles("craft_recipe"), "公开即时生产入口已关闭")
	_check(not server.handle_peer_player_panel_command(71, {"type": "craft_recipe", "station_id": "refining", "recipe_id": iron.recipe_id,
		"inventory_revision": _state().inventory_revision}).ok, "旧协议不能绕过等待")
	_check(commands.all(func(command: Dictionary) -> bool: return command.type != "craft_recipe"), "所有窗口操作均为订单意图")
	manager.free()
	server.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(config.player_state_store_path))
	for failure in failures: push_error(failure)
	print("Manufacturing UI: %d checks, %d failures" % [checks, failures.size()])
	quit(1 if not failures.is_empty() else 0)


## 在清单中以配方稳定身份选择实际铁矿提炼。
func _select_iron() -> void:
	for index in range(panel._snapshot.recipes.size()):
		if panel._snapshot.recipes[index].id == iron.recipe_id:
			panel.recipe_list.select(index)
			panel.recipe_list.item_selected.emit(index)
			return


## 将窗口意图送入实际服务器，在拒绝时不应用任何候选。
## [param command] 客户端语义命令。
func _dispatch(command: Dictionary) -> void:
	commands.append(command.duplicate(true))
	if reject_once and command.type == "start_production":
		reject_once = false
		return
	var result := server.handle_peer_player_panel_command(71, command)
	if result.ok: manager.panel_session.apply_bundle(result.value)


## 接收真实服务器生产推送，经同一玩家会话更新全部面板。
## [param _peer] 已绑定测试连接。[param message] 可靠消息。
func _receive(_peer: int, message: Dictionary) -> void:
	if message.get("type") == "player_panels" and bool(message.get("result", {}).get("ok", false)):
		manager.panel_session.apply_bundle(message.result.value)


## 获取已提交状态副本。
## 返回隔离角色的权威记录。
func _state() -> PlayerStateRecord:
	return server.autosave_service.state_for(entity_id)


## 统计已经写入真实仓储的铁数量。
## 返回产物数量。
func _quantity() -> int:
	var result := 0
	for stack: InventoryStackRecord in _state().inventory_stacks:
		if stack.item_definition_id == iron.product_definition_id: result += stack.quantity
	return result


## 累计交互断言并保留所有失败信息。
## [param condition] 预期行为。[param label] 错误说明。
func _check(condition: bool, label: String) -> void:
	checks += 1
	if not condition: failures.append(label)
