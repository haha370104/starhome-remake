extends SceneTree

var checks := 0
var failures: Array[String] = []


## 验证本地设置的校验、恢复和保存，不进入玩家存档。
func _initialize() -> void:
	var settings := ClientPreferences.new()
	_check(settings.window_scale == 1 and settings.hotkeys.label("map") == "Tab", "初始偏好")
	_check(settings.set_window_scale(1.3) and not settings.set_window_scale(INF), "缩放范围")
	_check(settings.set_palette("warm") and not settings.set_palette("unknown"), "配色范围")
	for value in [-1.0, 1.1, NAN, INF]: _check(not settings.set_volume("music", value), "拒绝非法音量")
	_check(not settings.set_volume("invented", 0.5), "拒绝未知通道")
	_check(settings.set_volume("effects", 0.4), "合法音量")
	settings.set_muted(true)
	_check(not settings.bind_key("map", KEY_Z).is_ok, "拒绝动作冲突")
	for key in [KEY_ALT, KEY_ESCAPE, KEY_F4 | KEY_MASK_ALT, KEY_TAB | KEY_MASK_ALT,
		KEY_DELETE | KEY_MASK_CTRL | KEY_MASK_ALT, KEY_A | KEY_MASK_META]:
		_check(not settings.bind_key("map", key).is_ok, "拒绝保留组合")
	_check(settings.bind_key("map", KEY_M | KEY_MASK_CTRL).is_ok, "支持带修饰键的逻辑组合")
	var event := InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	_check(not settings.hotkeys.matches("map", event), "组合需精确匹配")
	event.ctrl_pressed = true
	_check(settings.hotkeys.matches("map", event), "正确触发组合")
	event.echo = true
	_check(not settings.hotkeys.matches("map", event), "忽略连发")
	event.echo = false
	settings.hotkeys.capturing = true
	_check(not settings.hotkeys.matches("map", event), "录入时不触发游戏")
	settings.hotkeys.capturing = false
	var path := "res://.godot/preferences-%d.cfg" % Time.get_ticks_usec()
	_check(settings.save_file(path) == OK, "独立偏好保存")
	var restored := ClientPreferences.new()
	_check(restored.load_file(path) == OK, "重建偏好读取")
	_check(restored.window_scale == 1.3 and restored.palette == "warm" and restored.muted, "显示与静音持久化")
	_check(restored.volumes.effects == 0.4 and restored.hotkeys.matches("map", event), "音量与按键持久化")
	var config := ConfigFile.new()
	config.set_value("display", "scale", true)
	config.set_value("audio", "music", NAN)
	config.set_value("audio", "muted", 1)
	config.set_value("keys", "map", KEY_Z)
	config.save(path)
	restored.load_file(path)
	_check(restored.window_scale == 1 and not restored.muted and restored.volumes.music == 0.65, "非法字段恢复默认")
	_check(restored.hotkeys.snapshot() == ClientHotkeys.DEFAULTS, "冲突配置整体退回默认")
	_check(restored.hotkeys.restore({"map": KEY_Z, "self_repair": KEY_TAB}), "配置允许合法互换")
	settings.reset()
	_check(settings.hotkeys.snapshot() == ClientHotkeys.DEFAULTS and not settings.muted and settings.palette == "default", "恢复默认完整")
	_check(settings.save_file("res://.godot/missing-parent/settings.cfg") != OK, "写入失败有明确结果")
	for failure in failures: push_error(failure)
	print("CLIENT_PREFERENCES_%s (%d checks)" % ["OK" if failures.is_empty() else "FAIL", checks])
	quit(0 if failures.is_empty() else 1)


## 累积偏好边界断言。
## [param condition] 预期条件。[param message] 失败说明。
func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
