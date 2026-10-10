extends SceneTree

const Fixture := preload("res://tests/fixtures/player_panel_service_fixture.gd")
const PartyPanelScript := preload("res://scripts/client/ui/windows/navigation/party_panel.gd")
const TradePanelScript := preload("res://scripts/client/ui/windows/navigation/trade_panel.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	root.size = Vector2i(1000, 700)
	var fixture := Fixture.new()
	var initialized: DomainResult = fixture.initialize()
	_expect(initialized.is_ok, "玩家面板夹具初始化")
	if not initialized.is_ok:
		_finish()
		return
	var player_result: DomainResult = fixture.current_player()
	_expect(player_result.is_ok, "构造交易窗口玩家")
	if not player_result.is_ok:
		_finish()
		return
	var player: Player = player_result.value
	await _test_trade_selection(player)
	await _test_party_selection(player)
	await _test_chat_history(player)
	_finish()


func _test_trade_selection(player: Player) -> void:
	var panel: TradePanel = TradePanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.position = Vector2(20, 20)
	panel.apply_player(player)
	var item := player.inventory.find("inventory.spare_engine") as GameItem
	panel.apply_event({
		"type": "trade_state",
		"result": {"ok": true, "value": {"trade": {
			"trade_id": "trade.selection.test",
			"members": [player.entity_id, "player.other"],
			"offers": {
				player.entity_id: {"items": [], "currency": 0, "locked": false},
				"player.other": {"items": [], "currency": 0, "locked": false},
			},
		}}},
	})
	var commands: Array[Dictionary] = []
	panel.command_requested.connect(func(command: Dictionary) -> void: commands.append(command))
	var inventory_row := panel.inventory_listing.get_root().get_first_child()
	inventory_row.select(0)
	_expect(panel._selected_inventory_id == item.instance_id, "选中背包物品更新交易目标")
	panel._add_item()
	_expect(not commands.is_empty() and commands.back().get("type") == "trade_add_item"
		and commands.back().get("instance_id") == item.instance_id, "选中物品可加入报价")
	panel.apply_event({
		"type": "trade_state",
		"result": {"ok": true, "value": {"trade": {
			"trade_id": "trade.selection.test",
			"members": [player.entity_id, "player.other"],
			"offers": {
				player.entity_id: {"items": [{
					"instance_id": item.instance_id,
					"definition_id": item.definition_id,
					"display_name": item.display_name,
					"quantity": 1,
				}], "currency": 0, "locked": false},
				"player.other": {"items": [], "currency": 0, "locked": false},
			},
		}}},
	})
	var offer_row := panel.offer_listing.get_root().get_first_child()
	offer_row.select(0)
	_expect(panel._selected_offer_id == item.instance_id, "选中本人报价物品更新移除目标")
	panel._remove_item()
	_expect(commands.back().get("type") == "trade_remove_item"
		and commands.back().get("instance_id") == item.instance_id, "选中报价物品可移除")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/social-trade-window.png")
	panel.queue_free()
	await process_frame


func _test_party_selection(player: Player) -> void:
	var panel: PartyPanel = PartyPanelScript.new()
	root.add_child(panel)
	await process_frame
	panel.position = Vector2(20, 20)
	panel.apply_player(player)
	panel.apply_event({
		"type": "party_state",
		"result": {"ok": true, "value": {"party": {
			"party_id": "party.selection.test",
			"leader_id": player.entity_id,
			"members": [
				{"entity_id": player.entity_id, "display_name": player.display_name, "connected": true},
				{"entity_id": "player.other", "display_name": "另一玩家", "connected": true},
			],
			"pending_invites": [],
		}}},
	})
	var commands: Array[Dictionary] = []
	panel.command_requested.connect(func(command: Dictionary) -> void: commands.append(command))
	var member_row := panel.members.get_root().get_first_child().get_next()
	member_row.select(0)
	_expect(panel._selected_member_id == "player.other", "选中队员更新管理目标")
	_expect(not panel.kick_button.disabled and not panel.transfer_button.disabled,
		"队长选中队员后可使用移出和转让操作")
	panel._kick_member()
	panel._transfer_leader()
	_expect(commands.size() == 2 and commands[0].get("type") == "party_kick"
		and commands[0].get("target_entity_id") == "player.other", "移出操作指向选中队员")
	_expect(commands.size() == 2 and commands[1].get("type") == "party_transfer_leader"
		and commands[1].get("target_entity_id") == "player.other", "队长转让指向选中队员")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/social-party-window.png")
	panel.queue_free()
	await process_frame


func _test_chat_history(player: Player) -> void:
	var directory := "user://chat-window-test-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var service := AuthoritativeChatService.new()
	_expect(service.configure(func(actor_id: String) -> Variant: return player if actor_id == player.entity_id else null,
		func(_actor_id: String) -> String: return "city",
		func(actor_id: String) -> String: return "Riko" if actor_id == "llm.riko" else "另一玩家" if actor_id == "other" else player.display_name,
		func(_map_id: String) -> Array[String]: return [],
		func(actor_id: String) -> bool: return actor_id == player.entity_id,
		func(_actor_id: String, _message: Dictionary) -> void: pass, Callable(), directory).is_ok, "私聊界面接入独立存储")
	var event := {"channel": "private", "sender_entity_id": "llm.riko", "target_entity_id": player.entity_id,
		"sender_name": "Riko", "target_name": player.display_name, "message": "历史消息", "sent_at_unix_msec": 1791558000000}
	for index in 51:
		event.message = "历史消息%d" % (index + 1)
		service.history.append(event)
	var panel := ChatPanel.new()
	root.add_child(panel)
	await process_frame
	panel.apply_player(player)
	var commands: Array[Dictionary] = []
	panel.command_requested.connect(func(command: Dictionary) -> void: commands.append(command))
	panel.open_private("llm.riko", "Riko")
	var initial := _chat_response(service, player.entity_id, commands[0])
	event.message = "实时消息"
	var live: Dictionary = service.history.append(event).value
	live["channel"] = "private"
	for repeat in 2: panel.apply_event({"type": "chat_event", "result": {"ok": true, "value": {"event": live}}})
	panel.apply_event(initial)
	panel.apply_event(_chat_response(service, player.entity_id, commands[1]))
	_expect(panel._private_messages.size() == 51 and panel.transcript.text.contains("实时消息"), "历史查询期间实时消息不丢失且重复事件不重复显示")
	panel.earlier_button.pressed.emit()
	panel.apply_event(_chat_response(service, player.entity_id, commands.back()))
	_expect(panel._private_messages.size() == 52 and panel.earlier_button.disabled and panel.transcript.text.contains("历史消息1"), "更早消息分页合并且到头禁用按钮")
	service.history._conversations.values()[0].messages.pop_front()
	panel.refresh_history()
	panel.apply_event(_chat_response(service, player.entity_id, commands.back()))
	_expect(panel._private_messages.size() == 51 and panel._private_messages.values().all(func(row: Dictionary) -> bool: return row.sequence >= 2), "重同步清理服务端已截断的旧缓存，不只按本地条数裁剪")
	panel.open_private("other", "另一玩家")
	var other_reply := _chat_response(service, player.entity_id, commands[commands.size() - 2])
	panel.open_private("llm.riko", "Riko")
	panel.apply_event(_chat_response(service, player.entity_id, commands[commands.size() - 2]))
	var expected_text := panel.transcript.text
	panel.apply_event(other_reply)
	panel.apply_event(initial)
	_expect(panel.transcript.text == expected_text and panel._target_name == "Riko", "切换对象及同对象旧请求的迟到响应都不能覆盖当前会话")
	panel.visible = false
	panel.apply_event(_chat_response(service, player.entity_id, commands.back()))
	_expect(not panel.visible, "历史回放不自动打开聊天窗")
	_expect(service.history.close().is_ok, "正常退出等待聊天记录落盘")
	panel.queue_free()
	await process_frame
	_expect(service.history.configure(directory).is_ok, "重新登录加载同一会话档案")
	panel = ChatPanel.new()
	root.add_child(panel)
	await process_frame
	panel.apply_player(player)
	commands.clear()
	panel.command_requested.connect(func(command: Dictionary) -> void: commands.append(command))
	panel.channel_picker.select(2)
	panel._channel_changed(2)
	panel.apply_event(_chat_response(service, player.entity_id, commands.back()))
	panel.apply_event(_chat_response(service, player.entity_id, commands.back()))
	_expect(panel._target_name == "Riko" and panel._private_messages.size() == 50 and panel.transcript.text.contains("实时消息"), "重登后从会话列表查看离线非好友历史")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/private-chat-history-ui.png")
	panel.queue_free()
	await process_frame
	service.history.close()
	for file_name: String in DirAccess.get_files_at(ProjectSettings.globalize_path(directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(directory).path_join(file_name))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(directory))


func _chat_response(service: AuthoritativeChatService, actor_id: String, command: Dictionary) -> Dictionary:
	var result := service.execute(actor_id, command)
	return {"type": "social_result", "result": {"ok": result.is_ok, "value": result.value}}


func _expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func _finish() -> void:
	for failure: String in failures:
		push_error(failure)
	print("SOCIAL_WINDOW_SELECTION checks=%d failures=%d" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
