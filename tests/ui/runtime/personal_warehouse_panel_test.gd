extends SceneTree

var _fixture := PlayerPanelServiceFixture.new()
var _service := PersonalWarehouseService.new()
var _manager: GameWindowManager
var _checks := 0
var _failures := 0
var _commands: Array[Dictionary] = []
var _reject_once := false


## 延迟建立真实窗口组合和隔离的权威事务夹具。
func _initialize() -> void:
	call_deferred("_run")


## 验证背包入口、实际存取、数量、切柜、确认及刷新，不只检查控件存在。
func _run() -> void:
	root.size = Vector2i(1200, 800)
	root.gui_embed_subwindows = true
	_check(_fixture.initialize().is_ok and _service.initialize().is_ok, "初始化")
	var catalog := ItemCatalog.new()
	catalog.initialize()
	var mapper := PlayerStateMapper.new(catalog)
	var player: Player = mapper.to_domain(_fixture._state).value
	player.amethyst = AmethystWallet.new(5000)
	player.inventory.add_reward(catalog.create("bright_firepower_crystal", {"instance_id": "crystal", "quantity": 7, "bound": true, "crystal_cracks": 2}).value)
	player.inventory.add_reward(catalog.create("beginner_engine", {"instance_id": "locked", "locked": true}).value)
	_fixture._state = mapper.to_record(player).value
	_manager = GameWindowManager.new()
	root.add_child(_manager)
	_check(_manager.configure(PlayerPanelSession.new(_dispatch)), "会话")
	_manager.toggle("inventory")
	await process_frame
	var entry: Button = _manager.inventory_panel.content_root.get_node("WarehouseButton")
	entry.pressed.emit()
	var panel: PersonalWarehousePanel = _manager.navigation_windows.personal_warehouse
	_check(panel.visible and panel._snapshot.available, "背包入口拉取权威仓库")
	_check(panel.warehouse_list.item_count == 0 and panel._cabinet_buttons[1].disabled, "初始一柜")
	_check(panel.deposit_button.disabled and panel.withdraw_button.disabled, "未选择不可转移")
	_select(panel, true, "locked")
	_check(panel.deposit_button.disabled, "锁定不可存入")
	_select(panel, true, "crystal")
	_check(panel.deposit_quantity.max_value == 7 and not panel.deposit_button.disabled, "堆叠上限")
	panel.deposit_quantity.get_line_edit().text = "3"
	panel.deposit_button.pressed.emit()
	_check(panel._snapshot.carried.filter(func(row: PersonalWarehouseSnapshot.ItemRow) -> bool: return row.id == "crystal")[0].quantity == 4, "原堆剩四")
	_check(panel._snapshot.stored.size() == 1 and panel._snapshot.stored[0].quantity == 3, "实际入库三")
	var stored_id := panel._snapshot.stored[0].id
	_check(stored_id != "crystal" and panel._snapshot.stored[0].bound, "部分存入身份及绑定")
	_check(panel.warehouse_list.get_item_icon(0) != null and panel.warehouse_list.get_item_tooltip(0).contains("裂纹：2"), "原物品图及实例说明")
	_select(panel, false, stored_id)
	panel.withdraw_quantity.get_line_edit().text = "2"
	panel.withdraw_button.pressed.emit()
	_check(panel._snapshot.stored[0].quantity == 1 and panel.withdraw_quantity.max_value == 1, "取出后数量上限更新")
	_check(_manager.panel_session.current_player.inventory.find("crystal").quantity == 6, "实际回包合并")
	panel.expand_button.pressed.emit()
	_check(panel.confirmation.dialog_text.contains("1888") and panel.confirmation.visible, "扩容明确收费")
	panel.confirmation.canceled.emit()
	panel.confirmation.hide()
	panel._confirm_expansion()
	_check(panel._snapshot.cabinet_count == 1, "取消不收费")
	panel.expand_button.pressed.emit()
	panel.confirmation.hide()
	panel.confirmation.confirmed.emit()
	_check(panel._snapshot.cabinet_count == 2 and panel._snapshot.amethyst == 3112 and panel._snapshot.cabinet == 2, "实际扩容并进入新柜")
	var count := _commands.size()
	panel._confirm_expansion()
	_check(_commands.size() == count, "确认只发一次")
	_check(panel.warehouse_list.item_count == 0 and panel.withdraw_button.disabled, "新柜不沿用旧柜选择")
	panel._cabinet_buttons[0].pressed.emit()
	_check(panel.warehouse_list.item_count == 1 and panel._snapshot.cabinet == 1, "切回第一柜")
	_select(panel, true, "inventory.spare_engine")
	_reject_once = true
	panel.deposit_button.pressed.emit()
	_check(not panel.deposit_button.disabled and _manager.panel_session.current_player.inventory.find("inventory.spare_engine") != null, "失败后查询恢复操作且不预测扣物品")
	panel.deposit_button.pressed.emit()
	_check(panel._snapshot.stored.size() == 2 and _manager.panel_session.current_player.inventory.find("inventory.spare_engine") == null, "整件存入原身份")
	var engine_index := _index(panel._snapshot.stored, "inventory.spare_engine")
	_check(panel.warehouse_list.get_item_icon(engine_index) != null, "装备背包模式贴图")
	_select(panel, false, "inventory.spare_engine")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/personal_warehouse_panel.png")
	panel.withdraw_button.pressed.emit()
	_check(_manager.panel_session.current_player.inventory.find("inventory.spare_engine") != null, "整件取出")
	_fixture.execute({"type": "arrange_inventory", "inventory_revision": _fixture._state.inventory_revision})
	_manager.panel_session.apply_bundle(_fixture._service.build_bundle(_fixture._state))
	_check(panel._snapshot.inventory_revision == _fixture._state.inventory_revision, "其他库存事务主动刷新版本")
	panel.expand_button.pressed.emit()
	panel.hide()
	_check(panel._pending.is_empty() and not panel.confirmation.visible, "关窗清除收费确认")
	_fixture._state.map_id = "outside"
	entry.pressed.emit()
	_select(panel, true, "crystal")
	_check(not panel._snapshot.available and panel.deposit_button.disabled and panel.expand_button.disabled and panel.warehouse_list.item_count == 0, "野外入口只显示地点限制")
	_manager.queue_free()
	await process_frame
	print("Personal warehouse UI: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)


## 通过真实列表选择信号驱动界面，不直接伪造面板库存。
## [param panel] 当前仓库窗口。
## [param deposit] 是否选择背包侧。
## [param id] 待选择的真实实例。
func _select(panel: PersonalWarehousePanel, deposit: bool, id: String) -> void:
	var index := _index(panel._snapshot.carried if deposit else panel._snapshot.stored, id)
	_check(index >= 0, "待选实例存在：" + id)
	if index < 0: return
	var listing := panel.backpack_list if deposit else panel.warehouse_list
	listing.select(index)
	listing.item_selected.emit(index)


## 定位实例在当前投影中的行号。
## [param rows] 当前柜或背包行。
## [param id] 实例身份。
## 返回行号；不存在返回负一。
func _index(rows: Array[PersonalWarehouseSnapshot.ItemRow], id: String) -> int:
	for index in range(rows.size()):
		if rows[index].id == id: return index
	return -1


## 以正式仓库服务结算UI意图并回送统一会话，普通命令沿用玩家服务。
## [param command] 实际发送的窗口意图。
## 返回权威结果。
func _dispatch(command: Dictionary) -> DomainResult:
	_commands.append(command.duplicate(true))
	if _reject_once:
		_reject_once = false
		return DomainResult.failure(&"test.failure", "模拟写入失败")
	if command.get("type") in PersonalWarehouseService.COMMANDS:
		var result := _service.execute(_fixture._state, command)
		_check(result.is_ok, "权威命令：" + String(command.type))
		if not result.is_ok: return result
		if result.value.changed:
			_fixture._state = result.value.candidate
			_fixture._state.revision += 1
		var bundle := _service.build_bundle(_fixture._state, result.value.operation)
		_manager.panel_session.apply_bundle(bundle)
		return DomainResult.ok(bundle)
	var result := _fixture.execute(command)
	if result.is_ok: _manager.panel_session.apply_bundle(result.value)
	return result


## 累计真实UI与事务断言。
## [param condition] 预期条件。
## [param message] 故障标签。
func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error(message)
