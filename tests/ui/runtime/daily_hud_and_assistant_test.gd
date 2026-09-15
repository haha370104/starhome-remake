extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var service := AuthoritativeCommerceService.new()
var state: PlayerStateRecord
var manager: GameWindowManager
var failures: Array[String] = []
var checks := 0


## 延迟到场景树可用时运行真实 UI、服务响应和智脑策略验证。
func _initialize() -> void:
	call_deferred("_run")


## 验证精简 HUD、任务接取交付、历练展示及增强功能的决策边界。
func _run() -> void:
	root.size = Vector2i(1440, 860)
	var fixture := Fixture.new()
	fixture.initialize()
	state = fixture._state.duplicate_record()
	service.initialize()
	manager = GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(_dispatch))
	var top := FreeTopMenu.new()
	root.add_child(top)
	var manifest := JsonConfigLoader.load_dictionary("res://data/ui/free_hud_assets.json")
	top.configure(manifest.value.top_menu, HudState.new())
	var actions: Array[String] = []
	top.action_requested.connect(func(action: String) -> void:
		actions.append(action)
		manager.toggle(action)
	)
	var expected := ["party", "return_base", "self_repair", "summon_guard", "smart_assistant", "central_controller", "mercenary", "experience"]
	_expect(top.action_buttons.keys() == expected, "仅保留用户指定八个功能且顺序一致")
	for i in range(8):
		var button: Button = top.action_buttons[expected[i]]
		_expect(button.size == Vector2(73, 34) and top.get_rect().size == Vector2(326, 82), "按钮拥有独立足够点击区域")
		if i >= 4:
			_expect(button.position.y > top.action_buttons[expected[i - 4]].position.y, "两行四列无叠压")
	top.action_buttons.mercenary.pressed.emit()
	var mercenary: DailyActivitiesPanel = manager.navigation_windows.mercenary
	mercenary.position = Vector2(25, 110)
	_expect(mercenary.visible and mercenary.available.item_count == 5, "真实 HUD 打开已生成五条委托的窗口")
	_expect(mercenary.summary.text.contains("领取 0/200") and mercenary.summary.text.contains("完成 0/100"), "面板展示两项每日额度")
	mercenary.available.select(0)
	mercenary._show_available(0)
	mercenary.accept_button.pressed.emit()
	_expect(mercenary.active.item_count == 1 and state.daily_activities.accepted_today == 1, "点击接取经过服务并刷新已接列表")
	mercenary.active.select(0)
	mercenary._show_active(0)
	mercenary.abandon_button.pressed.emit()
	_expect(mercenary.active.item_count == 0 and state.daily_activities.accepted_today == 1, "放弃回包保留已用次数")
	# 控制夹具中的任务栏，验证实际材料扣除后钱包显示更新。
	state.daily_activities.offers = ["2"]
	_dispatch({"type": "query_daily_activities"})
	mercenary.available.select(0)
	mercenary._show_available(0)
	mercenary.accept_button.pressed.emit()
	var items := ItemCatalog.new()
	items.initialize()
	var mapper := PlayerStateMapper.new(items)
	var player: Player = mapper.to_domain(state).value
	var definition: MercenaryDefinition = service.daily.catalog.tasks["2"]
	player.receive_loot(items.create(definition.target_id, {"instance_id": "ui.daily", "quantity": definition.quantity}).value)
	state = mapper.to_record(player).value
	state.daily_activities.completed_today = 99
	_dispatch({"type": "query_daily_activities"})
	mercenary.active.select(0)
	mercenary._show_active(0)
	mercenary.complete_button.pressed.emit()
	_expect(state.amethyst == 15 and mercenary.summary.text.contains("15"), "真实交付回包显示15紫晶")
	_expect(mercenary.summary.text.contains("完成 100/100"), "第100次完成后显示额度耗尽")
	var saved := state.duplicate_record()
	state.daily_activities.active = {"capped": {"id": "2", "progress": 0}}
	player = mapper.to_domain(state).value
	player.receive_loot(items.create(definition.target_id, {"instance_id": "ui.daily.capped", "quantity": definition.quantity}).value)
	state = mapper.to_record(player).value
	_dispatch({"type": "query_daily_activities"})
	mercenary.active.select(0)
	mercenary._show_active(0)
	mercenary.available.select(0)
	mercenary._show_available(0)
	_expect(mercenary.complete_button.disabled and not mercenary.abandon_button.disabled and not mercenary.accept_button.disabled,
		"完成额度耗尽时禁止交付达标任务，仍可领取或取消")
	state.daily_activities.accepted_today = 200
	_dispatch({"type": "query_daily_activities"})
	_expect(mercenary.accept_button.disabled and mercenary.summary.text.contains("领取 200/200"), "领取额度耗尽时禁用领取按钮")
	state = saved
	_dispatch({"type": "query_daily_activities"})
	top.action_buttons.experience.pressed.emit()
	var experience: DailyActivitiesPanel = manager.navigation_windows.experience
	experience.position = Vector2(590, 250)
	_expect(experience.available.item_count == 10, "历练显示全部十条固定目标")
	experience.available.select(8)
	experience._show_available(8)
	_expect(experience.accept_button.disabled, "未实现活动不能点击领奖")
	var brain: SmartAssistantPanel = manager.navigation_windows.smart_assistant
	var policy := SmartAssistantPolicy.new()
	brain.settings_changed.connect(policy.apply)
	brain.toggles.auto_repair.button_pressed = true
	brain.toggles.enabled.button_pressed = true
	_expect(policy.needs_repair({"health": 30, "max_health": 100}), "智脑面板开关真正改变决策")
	_expect(not policy.needs_repair({"health": 0, "max_health": 100}), "死亡不触发维修")
	_expect(not policy.needs_repair({"health": 30, "max_health": 100, "self_repair_active": true}), "维修进行中不重复开关")
	var selected := policy.nearest([{"position": [50, 0], "health": 0}, {"position": [100, 0], "health": 10},
		{"position": [800, 0], "health": 10}], Vector2.ZERO, 200, true)
	_expect(selected.position == [100, 0], "只选择范围内活怪")
	brain.toggles.enabled.button_pressed = false
	_expect(not policy.needs_repair({"health": 10, "max_health": 100}), "关闭智脑立即停止决策")
	experience.hide()
	brain.show()
	brain.position = Vector2(875, 110)
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/daily-hud-and-assistant.png")
		brain.hide()
		mercenary.hide()
		experience.position = Vector2(250, 110)
		experience.show()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/daily-experience.png")
	manager.queue_free()
	top.queue_free()
	await process_frame
	for failure: String in failures:
		push_error(failure)
	print("DAILY_HUD_ASSISTANT checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 使用真实权威事务响应窗口意图；只有成功候选覆盖夹具存档。
## [param command] 面板提交的意图。
func _dispatch(command: Dictionary) -> void:
	var result := service.execute(state, command)
	if not result.is_ok:
		failures.append(result.error_message)
		return
	if result.value.changed:
		state = result.value.candidate
	manager.panel_session.apply_bundle(result.value.panel_bundle)


## 汇总 UI 和策略行为断言。
## [param condition] 待验证条件。
## [param message] 失败说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
