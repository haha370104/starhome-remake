extends SceneTree

var fixture := PlayerPanelServiceFixture.new()
var manager: GameWindowManager
var commands: Array[Dictionary] = []
var failures: Array[String] = []
var checks := 0
var reject_once := false


## 延迟创建真实窗口组合与权威领域事务夹具。
func _initialize() -> void:
	call_deferred("_run")


## 通过按钮、确认和同一玩家会话验证方案保存、换装、失败恢复及可读布局。
func _run() -> void:
	root.size = Vector2i(1120, 760)
	root.gui_embed_subwindows = true
	_check(fixture.initialize().is_ok, "实际面板服务")
	manager = GameWindowManager.new()
	root.add_child(manager)
	_check(manager.configure(PlayerPanelSession.new(_dispatch)), "组合真实共享窗口")
	manager.navigation_windows.smart_assistant.presets_requested.emit()
	var panel: VehicleLoadoutPresetsPanel = manager.navigation_windows.vehicle_presets
	_check(panel.visible and panel.choices.size() == 4 and panel.apply_button.disabled, "智脑入口查询四套空方案")
	panel.title_edit.text = ""
	var count := commands.size()
	panel.capture_button.pressed.emit()
	_check(commands.size() == count, "空名称不发送请求")
	panel.title_edit.text = "常用火力"
	panel.capture_button.pressed.emit()
	_check(fixture._state.vehicle_presets.at(0).name == "常用火力" \
		and panel.details.text.contains("主武器") and panel.details.text.contains("推进器"), "保存实际装配并展示完整槽位")
	_check(commands[-1].type == "capture_vehicle_preset" and not commands[-1].has("slots"), "客户端不发送装备副本")
	panel.title_edit.text = "尚未保存的草稿"
	panel._process(2.1)
	_check(panel.title_edit.text == "尚未保存的草稿", "轮询不覆盖正在编辑名称")
	panel.capture_button.pressed.emit()
	_check(panel.confirmation.visible and fixture._state.vehicle_presets.at(0).name == "常用火力", "覆盖前确认且未提交")
	panel.confirmation.canceled.emit()
	panel.confirmation.hide()
	panel._confirm_capture()
	_check(fixture._state.vehicle_presets.at(0).name == "常用火力", "取消确认不覆盖")
	panel.title_edit.text = "主战方案"
	panel.capture_button.pressed.emit()
	# 自动保存推进聚合版本，方案与装配未变化，所以原确认仍有效。
	fixture._state.revision += 1
	panel.confirmation.hide()
	panel.confirmation.confirmed.emit()
	_check(fixture._state.vehicle_presets.at(0).name == "主战方案", "无关玩家版本变化不会误伤覆盖确认")
	count = commands.size()
	panel._confirm_capture()
	_check(commands.size() == count, "已消费的确认不会重复发送")
	_dispatch({"type": "equip_vehicle_item", "instance_id": "inventory.spare_engine", "location": 3,
		"inventory_revision": fixture._state.inventory_revision, "loadout_revision": fixture._state.vehicle_loadout_revision})
	panel.choices[1].pressed.emit()
	_check(panel.title_edit.text == "方案2" and panel.apply_button.disabled, "选择另一套不沿用前套名称或启用状态")
	panel.title_edit.text = "备用推进器"
	panel.capture_button.pressed.emit()
	_check(fixture._state.vehicle_presets.at(1).name == "备用推进器", "保存第二套真实装配")
	panel.choices[0].pressed.emit()
	_check(panel.title_edit.text == "主战方案" and not panel.apply_button.disabled, "切回实际方案")
	reject_once = true
	panel.apply_button.pressed.emit()
	_check(panel.apply_button.disabled and manager.panel_session.current_player.vehicle.loadout.at(3).instance_id == "inventory.spare_engine", "等待期间不预测换装")
	panel._process(2.1)
	_check(not panel.apply_button.disabled, "拒绝无回包时查询恢复动作")
	panel.apply_button.pressed.emit()
	_check(manager.panel_session.current_player.vehicle.loadout.at(3).instance_id == "equipment.engine", "按钮真实调用整套换装")
	_check(panel.apply_button.disabled and panel.status.text.contains("冷却"), "成功后显示权威冷却")
	panel.choices[1].pressed.emit()
	_check(panel.apply_button.disabled, "方案之间共享切换冷却")
	panel._remaining = 0
	panel._refresh_actions()
	panel.apply_button.pressed.emit()
	_check(manager.panel_session.current_player.vehicle.loadout.at(3).instance_id == "equipment.engine", "本地倒计时篡改不能绕过服务端冷却")
	panel._process(2.1)
	_check(panel.status.text.contains("冷却") and panel.apply_button.disabled, "重新查询纠正倒计时")
	panel.choices[0].pressed.emit()
	panel.capture_button.pressed.emit()
	var pending := panel._pending_capture.duplicate(true)
	fixture._state.vehicle_presets.revision += 1
	panel.confirmation.hide()
	panel.confirmation.confirmed.emit()
	_check(commands[-1].preset_revision == pending.preset_revision and panel._awaiting, "确认绑定原方案版本，不偷偷改成新版本")
	panel._process(2.1)
	_check(not panel._awaiting and panel.title_edit.text == "主战方案", "旧确认失败后可恢复操作")
	var mapper := fixture._service._mapper
	var player: Player = mapper.to_domain(fixture._state).value
	player.unequip_vehicle_item(3, player.inventory.revision, player.vehicle.loadout.revision)
	player.inventory.remove_for_transfer("equipment.engine")
	fixture._state = mapper.to_record(player).value
	panel._process(2.1)
	_check(panel.details.text.contains("不在背包或战车中"), "装备售出或转移后明确提示缺失")
	_check(not panel.details.bbcode_enabled and panel.title_edit.max_length == 24, "统一可读文本且标题长度受限")
	await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/vehicle_loadout_presets.png")
	panel.capture_button.pressed.emit()
	panel.hide()
	_check(panel._pending_capture.is_empty() and not panel.confirmation.visible, "关窗清除未提交确认")
	count = commands.size()
	panel._process(4)
	_check(commands.size() == count, "隐藏窗口无轮询")
	manager.queue_free()
	await process_frame
	for failure in failures: push_error(failure)
	print("VEHICLE_PRESETS_UI_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 将窗口意图交给正式面板服务，失败不应用任何预测候选。
## [param command] 最小客户端命令。
func _dispatch(command: Dictionary) -> void:
	commands.append(command.duplicate(true))
	if reject_once and command.type == "apply_vehicle_preset":
		reject_once = false
		return
	var result := fixture.execute(command)
	if result.is_ok: manager.panel_session.apply_bundle(result.value)


## 记录所有独立交互检查结果。
## [param condition] 预期条件。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
