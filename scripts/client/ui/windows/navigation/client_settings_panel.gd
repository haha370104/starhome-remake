class_name ClientSettingsPanel
extends ModernNavigationWindow

var preferences: ClientPreferences
var scale_choice: OptionButton
var palette_choice: OptionButton
var mute_button: CheckButton
var status: Label
var key_buttons: Dictionary = {}
var volume_sliders: Dictionary = {}
var _pages: Dictionary = {}
var _tabs: Dictionary = {}
var _capturing_action := ""


## 构造四类本地设置，沿用当前统一字体和窗口组件。
func _ready() -> void:
	build_modern_window(Vector2(650, 510), "系统设置")
	for entry: Array in [["display", "字体与大小"], ["colors", "文字配色"], ["keys", "快捷键"], ["audio", "音乐音效"]]:
		var index := _pages.size()
		var button := make_button(entry[1], Rect2(20 + index * 155, 58, 145, 34), open_section.bind(entry[0]))
		_style_button(button)
		_tabs[entry[0]] = button
		var page := Control.new()
		page.position = Vector2(20, 112)
		page.size = Vector2(610, 310)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content_root.add_child(page)
		_pages[entry[0]] = page
	_build_display()
	_build_colors()
	_build_keys()
	_build_audio()
	status = make_label("设置立即生效，并保存在本机。", Rect2(20, 428, 610, 30))
	_style_button(make_button("恢复默认", Rect2(20, 466, 120, 30), _reset))
	_style_button(make_button("关闭", Rect2(510, 466, 120, 30), request_close))
	visibility_changed.connect(_cancel_capture_when_hidden)
	open_section("display")


## 绑定本地偏好并同步界面，不向玩家面板发业务命令。
## [param settings] 由客户端设置控制器拥有的偏好。
func bind_preferences(settings: ClientPreferences) -> void:
	preferences = settings
	preferences.changed.connect(refresh)
	refresh()


## 切换系统菜单对应的设置页，取消未完成的按键录入。
## [param section] 已知设置页身份。
func open_section(section: String) -> void:
	_cancel_capture()
	for key: String in _pages:
		_pages[key].visible = key == section
		_tabs[key].disabled = key == section


## 根据当前偏好刷新选项，不反向触发新的保存。
func refresh() -> void:
	if preferences == null: return
	scale_choice.select(ClientPreferences.SCALES.find(preferences.window_scale))
	palette_choice.select(ClientPreferences.PALETTES.find(preferences.palette))
	mute_button.set_pressed_no_signal(preferences.muted)
	for action: String in key_buttons:
		key_buttons[action].text = "请按新组合…" if action == _capturing_action else preferences.hotkeys.label(action)
	for channel: String in volume_sliders: volume_sliders[channel].set_value_no_signal(preferences.volumes[channel] * 100)


## 只在当前录入窗口接收键盘，Escape取消而不改变已有配置。
## [param event] 尚未由场景分发的键盘事件。
func _input(event: InputEvent) -> void:
	if _capturing_action.is_empty() or not event is InputEventKey or not event.pressed or event.echo: return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		_cancel_capture()
		status.text = "已取消，原快捷键保持不变。"
		return
	if event.keycode in [KEY_CTRL, KEY_ALT, KEY_SHIFT, KEY_META]: return
	var result := preferences.bind_key(_capturing_action, event.get_keycode_with_modifiers())
	if result.is_ok:
		_cancel_capture()
	else:
		status.text = result.error_message


## 建立显示选项，清楚区分界面比例与世界镜头缩放。
func _build_display() -> void:
	_page_label("display", "窗口与字号比例", Vector2.ZERO)
	scale_choice = OptionButton.new()
	for value in ["100% · 原始大小", "115% · 稍大", "130% · 大", "150% · 更大"]: scale_choice.add_item(value)
	_place("display", scale_choice, Rect2(250, 0, 300, 36))
	scale_choice.item_selected.connect(func(index: int) -> void: preferences.set_window_scale(ClientPreferences.SCALES[index]))
	_page_label("display", "字体：统一无衬线\n文字、图标与面板一起缩放，立即生效。\n窗口超出屏幕时自动缩小到可见范围。\n地图、战车和怪物的大小保持不变。", Vector2(0, 66), 220)


## 建立通用文字配色选项，保留物品品质和地图图例的含义。
func _build_colors() -> void:
	_page_label("colors", "通用文字配色", Vector2.ZERO)
	palette_choice = OptionButton.new()
	for label_text in ["默认 · 冷色", "高对比 · 亮白", "暖色 · 米白"]: palette_choice.add_item(label_text)
	_place("colors", palette_choice, Rect2(250, 0, 300, 36))
	palette_choice.item_selected.connect(func(index: int) -> void: preferences.set_palette(ClientPreferences.PALETTES[index]))
	_page_label("colors", "预览：战车装备、背包、任务与系统设置\n\n通用说明文字和中央系统提示使用所选配色。\n物品品质、警告与地图图例保留原有颜色。", Vector2(0, 70), 190)


## 为已有两项游戏操作建立可录入的组合键按钮。
func _build_keys() -> void:
	for action: String in ClientHotkeys.DEFAULTS:
		var y := key_buttons.size() * 62
		_page_label("keys", ClientHotkeys.LABELS[action], Vector2(0, y))
		var button := Button.new()
		_style_button(button)
		_place("keys", button, Rect2(250, y, 300, 36))
		button.pressed.connect(_start_capture.bind(action))
		key_buttons[action] = button
	_page_label("keys", "点击右侧按钮后按下新组合，Esc 取消。\n支持 Ctrl、Alt、Shift，重复绑定会提示冲突。\n输入文字时不触发游戏快捷键。", Vector2(0, 155), 130)


## 建立真实音频总线的音量设置，并明确当前没有可播放音源。
func _build_audio() -> void:
	for entry: Array in [["master", "总音量"], ["music", "音乐"], ["effects", "音效"]]:
		var y := volume_sliders.size() * 52
		_page_label("audio", entry[1], Vector2(0, y))
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		_place("audio", slider, Rect2(210, y, 340, 34))
		slider.value_changed.connect(_volume_changed.bind(entry[0]))
		volume_sliders[entry[0]] = slider
	mute_button = CheckButton.new()
	mute_button.text = "全部静音"
	_place("audio", mute_button, Rect2(0, 174, 300, 36))
	mute_button.toggled.connect(func(value: bool) -> void: preferences.set_muted(value))
	_page_label("audio", "当前暂无可播放音源。\n音量偏好会保存，供后续接入的声音使用。", Vector2(0, 238), 65)


## 将音量滑块的百分数转为线性通道值。
## [param value] 0至100音量。[param channel] 已知通道。
func _volume_changed(value: float, channel: String) -> void:
	preferences.set_volume(channel, value / 100.0)


## 开始录入一个动作，同时禁用原游戏快捷键避免误触。
## [param action] 待改的已有动作。
func _start_capture(action: String) -> void:
	_capturing_action = action
	preferences.hotkeys.capturing = true
	status.text = "按下新组合键；Esc 取消。"
	refresh()


## 清除按键录入状态，恢复快捷键正常分发。
func _cancel_capture() -> void:
	_capturing_action = ""
	if preferences != null: preferences.hotkeys.capturing = false
	refresh()


## 设置窗口隐藏时不能继续截获游戏按键。
func _cancel_capture_when_hidden() -> void:
	if not visible: _cancel_capture()


## 恢复显示、输入与音量默认偏好，不触碰角色资料。
func _reset() -> void:
	_cancel_capture()
	preferences.reset()


## 把页面子控件定位到固定设计坐标，缩放由窗口统一承担。
## [param page] 设置页。[param control] 子控件。[param rectangle] 设计坐标区域。
func _place(page: String, control: Control, rectangle: Rect2) -> void:
	control.position = rectangle.position
	control.size = rectangle.size
	_pages[page].add_child(control)


## 建立多行页面说明，保持字号一致并按段落换行。
## [param page] 设置页。[param text] 说明文字。[param point] 左上角。[param height] 可用高度。
func _page_label(page: String, text: String, point: Vector2, height := 36.0) -> void:
	var label_node := Label.new()
	label_node.text = text
	label_node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label_node.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_place(page, label_node, Rect2(point, Vector2(610 if height > 36 else 200, height)))
