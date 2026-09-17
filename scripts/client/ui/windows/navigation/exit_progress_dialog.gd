class_name ExitProgressDialog
extends ConfirmationDialog

signal retry_requested
signal return_requested
var _can_return := false


## 创建使用统一字体的退出状态窗，等待保存期间不把关闭窗口视作成功。
func _ready() -> void:
	theme = Theme.new()
	theme.default_font = preload("res://assets/ui/fonts/legacy_panel_font.tres")
	theme.default_font_size = 16
	title = "保存并退出"
	ok_button_text = "重试保存"
	cancel_button_text = "返回游戏"
	dialog_hide_on_ok = false
	dialog_close_on_escape = false
	exclusive = true
	get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmed.connect(retry_requested.emit)
	canceled.connect(_return_or_wait)
	close_requested.connect(_return_or_wait)


## 呈现保存等待，不允许把尚未确认的结果当作失败或成功。
## [param message] 当前等待说明。
func waiting(message := "正在保存角色、装备与生产进度，请稍候……") -> void:
	_can_return = false
	dialog_text = message
	get_ok_button().disabled = true
	get_cancel_button().disabled = true
	if not visible: popup_centered(Vector2i(560, 180))


## 呈现明确失败或确认超时；只有服务器明确拒绝时才允许返回游戏。
## [param message] 可读失败或等待说明。[param known_failure] 是否收到匹配的服务器拒绝。
func show_problem(message: String, known_failure: bool) -> void:
	_can_return = known_failure
	dialog_text = message
	get_ok_button().disabled = false
	get_cancel_button().disabled = not known_failure
	if not visible: popup_centered(Vector2i(560, 180))


## 处理用户返回游戏意图；结果未知时保持等待界面，不能取消已经保存的服务端退出。
func _return_or_wait() -> void:
	if _can_return:
		hide()
		return_requested.emit()
	else:
		call_deferred("_reopen_if_needed")


## 等待结果时恢复被系统隐藏的窗口，合并连续关闭通知，避免重复建立独占弹窗。
func _reopen_if_needed() -> void:
	if not visible and not _can_return: popup_centered(Vector2i(560, 180))
