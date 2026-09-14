extends SceneTree

var checks := 0
var failures: Array[String] = []
var commands: Array[Dictionary] = []


## 延迟验证真实底栏按钮、成就浏览器与会话刷新。
func _initialize() -> void:
	call_deferred("_run")


## 通过真实按钮打开面板，验证筛选、自动称号、重复打开和屏幕边界。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var fixture := PlayerPanelServiceFixture.new()
	_expect(fixture.initialize().is_ok, "夹具初始化")
	var player: Player = fixture._service.restore_player(fixture._state).value
	player.record_achievement(AchievementEvent.new(AchievementEvent.Kind.MONSTER_KILLED, "toxic_gel", 100, "preview.kills"))
	player.record_achievement(AchievementEvent.new(AchievementEvent.Kind.MINERAL_COLLECTED, "iron_ore", 100, "preview.mining"))
	var items := ItemCatalog.new()
	items.initialize()
	var bundle := PlayerPanelProjector.new(items).build_bundle(player)
	var manager := GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(func(command: Dictionary) -> void: commands.append(command)))
	manager.panel_session.apply_bundle(bundle)
	var manifest: Dictionary = JsonConfigLoader.load_dictionary("res://data/ui/free_hud_assets.json").value
	var bar := FreeBottomMainBar.new()
	bar.configure(manifest.bottom_main, manifest.general_shortcut, HudState.new())
	root.add_child(bar)
	bar.action_requested.connect(manager.toggle)
	await process_frame
	var achievement_button := bar.design_surface.get_node("Achievements") as LegacyStateButton
	var shop_button := bar.design_surface.get_node("PremiumShop") as LegacyStateButton
	_expect(achievement_button.position.x == 785 and shop_button.position.x == 824, "成就占原商城位置，商城移右一格并保留素材锚点")
	_expect(achievement_button.hit_button.tooltip_text == "成就系统", "成就按钮悬停说明")
	achievement_button.hit_button.pressed.emit()
	var panel := manager.navigation_windows["achievements"] as AchievementsPanel
	_expect(panel.visible and commands.back().type == "query", "真实按钮触发成就窗口及权威只读查询")
	_expect(panel.summary.text.contains("40") and panel.listing.item_count > 0, "显示同事务积分和目标列表")
	panel.search.text = "毒胶"
	panel.search.text_changed.emit(panel.search.text)
	_expect(panel.listing.item_count >= 3, "支持按怪物名字搜索")
	for index in panel.listing.item_count:
		_expect(panel.listing.get_item_text(index).contains("毒胶"), "搜索排除其他名称")
	panel.listing.select(1)
	panel.listing.item_selected.emit(1)
	var selected_id: String = panel.listing.get_item_metadata(1).id
	manager.panel_session.apply_bundle(bundle)
	_expect(panel.listing.get_item_metadata(panel.listing.get_selected_items()[0]).id == selected_id, "推送后保留选中的成就")
	panel.search.text = ""
	panel._tabs[3].pressed.emit()
	_expect(panel.listing.item_count == 6, "称号页显示全部阶梯")
	panel.listing.select(1)
	panel.listing.item_selected.emit(1)
	_expect(panel.details.text.contains("当前生效") and panel.details.text.contains("能量炮射程 +5"), "称号页显示生效状态和真实加值")
	panel.position = Vector2(250, 65)
	if "--capture-achievements" in OS.get_cmdline_user_args():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/achievements_titles.png")
		panel._tabs[0].pressed.emit()
		panel.search.text = "毒胶"
		panel.search.text_changed.emit(panel.search.text)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/achievements_progress.png")
	root.size = Vector2i(960, 540)
	await process_frame
	panel.clamp_to_viewport(Vector2(960, 540))
	_expect(Rect2(Vector2.ZERO, Vector2(960, 540)).encloses(panel.get_rect()), "最低窗口尺寸下完整容纳成就面板")
	var count := commands.size()
	manager._refresh_navigation()
	_expect(commands.size() == count + 1, "打开成就窗口时刷新只读快照")
	panel.request_close()
	count = commands.size()
	manager._refresh_navigation()
	_expect(not panel.visible and commands.size() == count, "关闭后停止成就轮询")
	achievement_button.hit_button.pressed.emit()
	_expect(panel.visible and panel.summary.text.contains("40"), "重复打开复用同一窗口及当前积分")
	shop_button.hit_button.pressed.emit()
	_expect(manager.navigation_windows["premium_shop"].visible, "商城换位后仍打开商城")
	manager.free()
	bar.free()
	for failure in failures:
		push_error(failure)
	print("ACHIEVEMENTS_UI checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


## 累计窗口行为断言。
## [param condition] 预期成立的交互条件。
## [param message] 失败时说明。
func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
