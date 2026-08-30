extends SceneTree

const DialogScript := preload("res://scripts/ui/vehicle_destroyed_dialog.gd")

var failures: Array[String] = []
var assertions := 0


## 验证荣耀版击毁文案、两项选择与仅表现倒计时。
func _initialize() -> void:
	var dialog: VehicleDestroyedDialog = DialogScript.new()
	root.add_child(dialog)
	dialog.configure()
	dialog.show_destroyed()
	_expect(dialog.visible, "战车首次击毁时应显示中央选择窗")
	_expect(dialog.message_label.text == "你已经被击毁，你可以选择",
		"击毁窗应使用已恢复的荣耀版原文")
	_expect(dialog.wait_button.text == "原地等待其他玩家营救",
		"等待选项应与荣耀版语义一致")
	_expect(dialog.or_label.text == "或", "两项选择之间应保留荣耀版的连接文字")
	_expect(dialog.return_button.text == "返回基地中心",
		"回基地选项应与荣耀版语义一致")
	var observed := {"return_requested": false}
	dialog.return_to_base_requested.connect(
		func() -> void: observed["return_requested"] = true
	)
	dialog.return_button.pressed.emit()
	_expect(bool(observed["return_requested"]) and dialog.return_button.disabled,
		"回基地后应锁定重复提交并等待服务器确认")
	dialog.show_recovery_scheduled(3.0)
	_expect(dialog.countdown_label.text == "基地救援将在 3 秒后抵达",
		"服务器确认后应显示三秒倒计时")
	dialog.call("_process", 1.1)
	_expect(dialog.countdown_label.text == "基地救援将在 2 秒后抵达",
		"倒计时只负责客户端表现并按秒向上取整")
	dialog.show_destroyed()
	dialog.wait_button.pressed.emit()
	_expect(not dialog.visible, "原地等待应关闭选择窗但不伪造复活")
	if failures.is_empty():
		print("VEHICLE_DESTROYED_DIALOG_OK (%d assertions)" % assertions)
		quit(0)
		return
	for failure: String in failures:
		push_error(failure)
	quit(1)


## 累积断言，统一报告失败。
## [param condition] 调用方传入的 `condition` 参数。
## [param message] 调用方传入的 `message` 参数。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
