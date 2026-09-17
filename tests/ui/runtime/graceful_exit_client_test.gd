extends SceneTree

class RejectingRepository extends PlayerStateRepository:
	## 注入明确的保存拒绝，验证真实传输的失败反馈。
	## [param _state] 不写盘的候选。[param _expected_revision] 原版本。
	## 返回存档失败。
	func save_player(_state: PlayerStateRecord, _expected_revision: int) -> DomainResult:
		return DomainResult.failure(&"test.write_failed", "模拟保存失败")

var checks := 0
var failures: Array[String] = []
var quit_count := 0


## 延迟启动完整大厅和隔离的权威存档服务。
func _initialize() -> void:
	call_deferred("_run")


## 验证窗口关闭、失败返回、超时重试以及最终写盘确认后才退出。
func _run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280, 720)
	var hall = load("res://scenes/main_hall.tscn").instantiate()
	hall.multiplayer_connect_automatically = false
	root.add_child(hall)
	await process_frame
	await process_frame
	var exit_flow: ClientExitController = hall.exit_controller
	exit_flow._quit = _quit_probe
	_check(not auto_accept_quit, "窗口关闭不能绕过保存")
	var config := DedicatedServerConfig.new()
	config.network_enabled = false
	config.dynamic_blocking_enabled = false
	config.player_state_store_path = "res://.godot/exit-client-%d.json" % Time.get_ticks_usec()
	var adapter: ClientNetworkAdapter = hall.multiplayer_presenter.session.network_adapter
	hall.map_travel._initial_authoritative_world_ready = false
	_check(adapter.configure_in_process_server(config), "注入隔离的真实服务器")
	_check(hall.multiplayer_presenter.session.connect_to_server("in-process", 0) == OK, "连接真实传输")
	for _frame in 60:
		if hall.map_travel._initial_authoritative_world_ready: break
		await process_frame
	_check(hall.map_travel._initial_authoritative_world_ready, "完整大厅取得当前角色")
	var server: AuthoritativeServer = adapter._transport_endpoint.authoritative_server
	server.set_physics_process(false)
	var session := server.sessions.session_for_peer(2)
	if session == null:
		push_error("未建立测试会话")
		hall.free()
		quit(1)
		return
	var entity := session.entity_id
	var before := server.autosave_service.state_for(entity).to_dictionary()
	var repository := server.autosave_service._repository
	server.autosave_service._repository = RejectingRepository.new()
	var prior_confirmation := ConfirmationDialog.new()
	hall.add_child(prior_confirmation)
	prior_confirmation.exclusive = true
	prior_confirmation.popup_centered(Vector2i(400, 160))
	root.close_requested.emit()
	await _frames(4)
	_check(not prior_confirmation.visible, "原有独占确认窗收起但不提交，退出窗口可正常显示")
	_check(quit_count == 0, "存档失败不能退出")
	_check(exit_flow.dialog.visible and not exit_flow.dialog.get_cancel_button().disabled, "明确失败允许返回游戏")
	_check(exit_flow.dialog.dialog_text.contains("模拟保存失败"), "真实拒绝经过共享传输呈现")
	_check(hall.combat.application_exiting, "失败提示仍持有输入锁直到用户返回")
	_check(server.autosave_service.state_for(entity).to_dictionary() == before, "失败不改服务端正式记录")
	if "--capture" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/graceful_exit_failure.png")
	var failed_id := exit_flow._request_id
	exit_flow.dialog._return_or_wait()
	_check(not hall.combat.application_exiting and not exit_flow.dialog.visible, "返回游戏恢复输入并关闭状态窗")
	_check(exit_flow._request_id.is_empty(), "返回后清除本次失败的身份")
	exit_flow._bundle_received({"exit_receipt": {"request_id": failed_id, "saved_revision": 1}})
	await _frames(2)
	_check(quit_count == 0, "已取消请求的迟到回包不能退出")
	server.autosave_service._repository = repository
	adapter.connection_state = ClientNetworkAdapter.ConnectionState.CONNECTING
	hall.game_window_manager.navigation_windows.system.exit_requested.emit()
	var retry_id := exit_flow._request_id
	_check(not retry_id.is_empty() and retry_id != failed_id, "再次退出生成独立请求身份")
	exit_flow._process(11)
	_check(exit_flow.dialog.visible and exit_flow.dialog.get_cancel_button().disabled, "超时结果未知不能返回游戏")
	_check(not exit_flow.dialog.get_ok_button().disabled and quit_count == 0, "超时只开放重试")
	exit_flow.dialog.hide()
	exit_flow.dialog._return_or_wait()
	exit_flow.dialog._return_or_wait()
	await _frames(2)
	_check(exit_flow.dialog.visible, "未知结果关闭状态窗后重新显示且不重复独占弹窗")
	exit_flow.request_exit()
	_check(exit_flow._request_id == retry_id, "重试复用相同请求编号")
	for revision: Variant in [null, true, -1, 1.5, INF, "1"]:
		exit_flow._bundle_received({"exit_receipt": {"request_id": retry_id, "saved_revision": revision}})
	exit_flow._bundle_received({"exit_receipt": {"request_id": failed_id, "saved_revision": 1}})
	await _frames(2)
	_check(quit_count == 0, "无效版本和不同编号的回执不能退出")
	adapter.connection_state = ClientNetworkAdapter.ConnectionState.CONNECTED
	var saves := server.autosave_service.save_count
	exit_flow.dialog.retry_requested.emit()
	await _frames(5)
	_check(quit_count == 1, "匹配的真实写盘回执触发一次最终退出")
	_check(server.autosave_service.save_count == saves + 1, "退出只保存一次")
	_check(server.sessions.session_for_peer(2) == null, "服务器收尾会话")
	_check(FileAccess.file_exists(config.player_state_store_path), "退出确认之前文件已存在")
	exit_flow._bundle_received({"exit_receipt": {"request_id": retry_id, "saved_revision": 1}})
	exit_flow.request_exit()
	await _frames(2)
	_check(quit_count == 1, "重复回执和关闭通知不会重复退出")
	hall.free()
	_check(auto_accept_quit, "场景释放恢复原有关闭策略")
	await _frames(2)
	var startup = load("res://scenes/main_hall.tscn").instantiate()
	startup.multiplayer_connect_automatically = false
	root.add_child(startup)
	await _frames(2)
	startup.exit_controller._quit = _quit_probe
	startup.exit_controller.request_exit()
	await _frames(2)
	_check(quit_count == 2, "尚未进入角色的启动页可直接退出")
	startup.free()
	for failure in failures: push_error(failure)
	print("GRACEFUL_EXIT_CLIENT_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 捕获最终退出意图，不真的结束测试进程。
func _quit_probe() -> void:
	quit_count += 1


## 等待异步传输与界面布局完成。
## [param count] 等待帧数。
func _frames(count: int) -> void:
	for _frame in count: await process_frame


## 累积完整场景断言。
## [param condition] 预期条件。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
