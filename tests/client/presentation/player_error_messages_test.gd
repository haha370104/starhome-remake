extends SceneTree

var assertions := 0
var failures: Array[String] = []


## 验证全部登记错误文案、未知错误回退及界面信号不直接显示英文。
func _initialize() -> void:
	call_deferred("_run")


## 使用真实 presenter 验证中央提示、状态栏与连接失败输出一致中文。
func _run() -> void:
	for code: String in PlayerErrorMessages.MESSAGES:
		_expect(PlayerErrorMessages._is_player_chinese(PlayerErrorMessages.describe(code, "internal English error")), "错误码必须有中文提示：%s" % code)
	_expect(PlayerErrorMessages.describe(&"mining.arm_required").contains("采掘臂"), "采矿拒绝说明需要采掘臂")
	_expect(PlayerErrorMessages.describe(&"quest.daily_limit", "今日已接取3次，请明天再来") == "今日已接取3次，请明天再来", "保留纯中文业务参数")
	_expect(PlayerErrorMessages.describe(&"future.code", "Failed: C:/private/state.sqlite") == "操作暂时无法完成，请稍后重试", "未知错误不泄露英文路径")
	_expect(PlayerErrorMessages.describe(&"future.code", "出错了 InternalException") == "操作暂时无法完成，请稍后重试", "混合英文同样不透传")
	_expect(PlayerErrorMessages.describe(&"inventory.no_space").contains("背包"), "背包空间错误可理解")
	var presenter := HallMultiplayerPresenter.new()
	root.add_child(presenter)
	var label := Label.new()
	presenter.add_child(label)
	presenter.network_notice_requested.connect(func(message: String, _duration: float) -> void: label.text = message)
	var messages: Array[String] = []
	presenter.system_message_requested.connect(func(message: String) -> void: messages.append(message))
	presenter._on_command_rejected(&"commerce.insufficient_currency", "not enough currency")
	_expect(messages.back() == "金币不足，无法购买" and label.text == messages.back(), "中央和状态栏都不显示原始英文")
	presenter._on_map_change_failed(&"test.portal", &"map.missing", "map is not registered")
	_expect(PlayerErrorMessages._is_player_chinese(messages.back()) and label.text == messages.back(), "切图失败统一中文")
	var connections: Array[String] = []
	presenter.connection_failed.connect(func(message: String) -> void: connections.append(message))
	presenter._on_connection_failed("ENet connection failed")
	_expect(connections.back() == "无法连接服务器，请检查连接后重试", "初始加载收到中文连接原因")
	presenter.queue_free()
	await process_frame
	print("PLAYER_ERROR_MESSAGES assertions=%d failures=%d" % [assertions, failures.size()])
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)


## 累计断言，不在第一处失败后掩盖后续结果。
## [param condition] 待验证条件。
## [param message] 中文失败原因。
func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
