extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
var failures: Array[String] = []
var assertions := 0
var commands: Array[Dictionary] = []

class StateOwner extends RefCounted:
	var states: Dictionary = {}
	## 按实体标识提供隔离的测试状态。
	## [param entity_id] 测试实体标识。
	## 返回对应持久化记录；不存在时返回 null。
	func state_for(entity_id: String) -> PlayerStateRecord:
		return states.get(entity_id)


## 延迟执行导航窗及权威数据边界回归。
func _initialize() -> void:
	call_deferred("_run")


## 验证会话过滤、任务领域投影、导航入口和游戏内窗口交互。
func _run() -> void:
	root.size = Vector2i(1280, 720)
	var fixture := Fixture.new()
	_expect(fixture.initialize().is_ok, "夹具初始化")
	var sessions := SessionRegistry.new()
	var owner := StateOwner.new()
	for index in range(3):
		var entity := "user%d" % index
		sessions.create(index + 1, entity, 0)
		sessions.session_for_peer(index + 1).map_instance_id = "hall" if index < 2 else "field"
		owner.states[entity] = fixture._state
	var roster := ScenePlayerListProjector.build("hall", sessions, owner)
	_expect(roster.players.size() == 2, "名单排除其他地图")
	_expect(not roster.players[0].has("account_id") and not roster.players[0].has("inventory"), "名单不暴露私有状态")
	_expect(roster.players[0].battle_result == null, "未实现的战果不伪造零值")
	sessions.mark_disconnected(2, 1)
	_expect(ScenePlayerListProjector.build("hall", sessions, owner).players.size() == 1, "断线宽限会话不视为在线")
	var server := AuthoritativeServer.new()
	server.sessions = sessions
	server.autosave_service = AuthoritativeAutosaveService.new()
	server.autosave_service._states = owner.states
	server.player_panel_service = fixture._service
	server.commerce_service = RefCounted.new()
	server.manufacturing_service = RefCounted.new()
	var response := server.handle_peer_player_panel_command(1, {"type": "query_scene_players", "map_instance_id": "field"})
	_expect(response.ok and response.value.scene_players.map_instance_id == "hall", "服务器忽略伪造地图参数")
	_expect(response.value.scene_players.players.size() == 1, "真实处理器返回命名名单协议")
	_expect(not server.handle_peer_player_panel_command(99, {"type": "query_scene_players"}).ok, "无会话不能查询名单")
	sessions.session_for_peer(1).map_instance_id = "field"
	response = server.handle_peer_player_panel_command(1, {"type": "query_scene_players"})
	_expect(response.value.scene_players.players.size() == 2, "切换地图后查询新区域")
	_expect(server.autosave_service.save_count == 0 and fixture._state.revision == 0, "名单查询不产生存档或版本写入")
	server.free()
	var bundle: Dictionary = fixture.execute({"type": "query"}).value
	_expect(bundle.mission_journal.is_empty(), "未接取任务不伪造日志")
	fixture._state.quest_states["arms_npc_supply"] = {"accepted": true, "completions": 2}
	bundle = fixture.execute({"type": "query"}).value
	_expect(bundle.mission_journal.size() == 1, "日志读取持久化任务")
	_expect(bundle.mission_journal[0].completions == 2, "保留完成次数")
	_expect(bundle.mission_journal[0].requirements[0].owned == 0, "材料来自同一背包聚合")
	var manager := GameWindowManager.new()
	root.add_child(manager)
	manager.configure(PlayerPanelSession.new(_record_command))
	manager.panel_session.apply_bundle(bundle)
	var order: Array[String] = []
	for action: String in FreeBottomMainBar.MENU_BUTTONS:
		order.append(action)
	_expect(order == ["character", "inventory", "vehicle_equipment", "friends", "scene_players", "missions", "system", "premium_shop"], "底栏只保留八项并按要求排序")
	_expect(not manager.toggle("star_map"), "删除星图入口")
	_expect(manager.toggle("scene_players"), "打开当前区域玩家列表")
	_expect(commands.back().type == "query_scene_players", "用户列表走统一权威命令")
	manager.panel_session.apply_bundle({"scene_players": roster})
	var players: ScenePlayersPanel = manager.navigation_windows.scene_players
	_expect(players.listing.get_root().get_child_count() == 2, "列表渲染服务器行数")
	players._sort_by_column(0, MOUSE_BUTTON_LEFT)
	_expect(players.listing.get_root().get_child_count() == 2, "列排序保留所有玩家")
	manager.toggle("missions")
	var journal: MissionJournalPanel = manager.navigation_windows.missions
	_expect(journal.listing.item_count == 1, "任务窗显示已接取任务")
	journal._select_category(1)
	_expect(journal.listing.item_count == 0, "未导入分类为空")
	journal._select_category(0)
	manager.toggle("system")
	var system: SystemMenuPanel = manager.navigation_windows.system
	var notices: Array[String] = []
	manager.notice_requested.connect(func(message: String) -> void: notices.append(message))
	system.unavailable("音乐音效")
	_expect(notices.back() == "音乐音效暂未实现", "设置保留未实现提示")
	manager.toggle("premium_shop")
	var shop: PremiumShopPanel = manager.navigation_windows.premium_shop
	_expect(shop.confirmation.visible and not shop.subcategories.visible, "进入商城先确认")
	shop._confirm_entry()
	_expect(not shop.confirmation.visible and shop.subcategories.visible, "确认展示商城")
	shop._select_category(2)
	_expect(shop.subcategories.item_count == 8, "商城按免费版分类")
	shop._search("战车")
	_expect(shop.empty_label.text.contains("没有匹配商品"), "未定义商品时搜索为空")
	manager.toggle("premium_shop")
	manager.toggle("premium_shop")
	_expect(shop.confirmation.visible, "再次进入重新确认")
	shop._confirm_entry()
	var before := commands.size()
	manager._refresh_navigation()
	_expect(commands.size() == before + 2, "仅可见名单与日志轮询只读命令")
	for window: Control in manager.navigation_windows.values():
		window.hide()
	before = commands.size()
	manager._refresh_navigation()
	_expect(commands.size() == before, "关闭窗口停止查询")
	if "--capture-navigation" in OS.get_cmdline_user_args():
		players.show()
		players.position = Vector2(5, 5)
		journal.show()
		journal.position = Vector2(335, 5)
		system.show()
		system.position = Vector2(600, 5)
		shop.show()
		shop.position = Vector2(550, 210)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/navigation_windows.png")
	manager.queue_free()
	await process_frame
	print("NAVIGATION_WINDOWS assertions=%d failures=%d" % [assertions, failures.size()])
	for failure in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 记录窗口命令，不启动真实用户会话。
## [param command] 窗口发送的查询意图。
func _record_command(command: Dictionary) -> void:
	commands.append(command.duplicate(true))


## 累计断言并保存失败信息。
## [param condition] 需要成立的行为。
## [param message] 失败时的中文描述。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
