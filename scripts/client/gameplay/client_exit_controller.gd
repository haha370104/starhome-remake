class_name ClientExitController
extends Node

var dialog: ExitProgressDialog
var _presenter: HallMultiplayerPresenter
var _panels: PlayerPanelSession
var _combat: CombatInteractionController
var _quit: Callable
var _request_id := ""
var _waiting := false
var _completed := false
var _elapsed := 0.0
var _previous_auto_quit := true


## 将菜单与系统关闭绑定到同一保存流程，测试可以注入退出回调而不结束测试进程。
## [param presenter] 实际传输会话。[param panels] 当前角色投影与回包入口。
## [param combat] 世界输入锁定入口。[param menu] 原图系统菜单。[param quit_callback] 测试可替换的最终退出动作。
func configure(presenter: HallMultiplayerPresenter, panels: PlayerPanelSession, combat: CombatInteractionController,
		menu: SystemMenuPanel, quit_callback: Callable = Callable()) -> void:
	_presenter = presenter
	_panels = panels
	_combat = combat
	_quit = quit_callback if quit_callback.is_valid() else get_tree().quit
	_previous_auto_quit = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(request_exit)
	menu.exit_requested.connect(request_exit)
	panels.bundle_received.connect(_bundle_received)
	dialog = ExitProgressDialog.new()
	add_child(dialog)
	dialog.retry_requested.connect(request_exit)
	dialog.return_requested.connect(_return_to_game)


## 停止新世界操作并请求保存；未进入任何角色的启动页无需虚构一次存档。
func request_exit() -> void:
	if _completed: return
	if _panels.snapshot_bundle().is_empty():
		_completed = true
		call_deferred("_finish")
		return
	if _request_id.is_empty(): _request_id = Crypto.new().generate_random_bytes(16).hex_encode()
	_waiting = true
	_elapsed = 0
	_combat.application_exiting = true
	_combat.map_travel.stop_moving("正在保存并退出")
	dialog.waiting()
	var sent := _presenter.request_player_panel_command({"type": "prepare_exit", "request_id": _request_id})
	if sent.is_empty():
		dialog.show_problem("尚未连接到存档服务。请恢复连接后重试，当前不会退出。", false)


## 超时只开放重试，不推断服务端是否已经提交。
## [param delta] 本地经过时间，仅用于等待提示。
func _process(delta: float) -> void:
	if not _waiting: return
	_elapsed += delta
	if _elapsed >= 10.0:
		_waiting = false
		dialog.show_problem("尚未收到保存确认。可以重试获取回执，确认完成后才会退出。", false)


## 只接受本次请求的成功回执或明确拒绝，其他角色投影和迟到回包均不触发退出。
## [param bundle] 经共享会话收到的服务端消息。
func _bundle_received(bundle: Dictionary) -> void:
	if _request_id.is_empty() or _completed: return
	var receipt: Variant = bundle.get("exit_receipt")
	if receipt is Dictionary and receipt.get("request_id") == _request_id \
		and _valid_saved_revision(receipt.get("saved_revision")):
		_waiting = false
		_completed = true
		dialog.waiting("存档已完成，正在退出……")
		call_deferred("_finish")
		return
	var failure: Variant = bundle.get("exit_failure")
	if failure is Dictionary and failure.get("request_id") == _request_id:
		_waiting = false
		var message := PlayerErrorMessages.describe(StringName(failure.get("code", "")), String(failure.get("message", "")))
		dialog.show_problem("存档未完成：%s\n可以重试，或返回游戏。" % message, true)


## 仅在服务器明确拒绝后恢复输入，随后另一次退出采用新的请求身份。
func _return_to_game() -> void:
	if _completed: return
	_waiting = false
	_request_id = ""
	_combat.application_exiting = false


## 延迟执行最终退出，避免在同步网络回调中销毁仍在发布信号的节点。
func _finish() -> void:
	if _quit.is_valid(): _quit.call()


## 校验跨传输回执中的存档版本，兼容JSON整数而不接受布尔值、负值或小数。
## [param value] 尚未信任的服务端回执字段。
## 返回是否为可表示的非负整数。
func _valid_saved_revision(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) \
		and value >= 0 and value <= 9007199254740991 and value == floor(value)


## 释放场景时还原原有系统关闭偏好，避免测试或重新进入大厅遗留全局状态。
func _exit_tree() -> void:
	get_tree().auto_accept_quit = _previous_auto_quit
