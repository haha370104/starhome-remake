class_name ClientSettingsController
extends Node

var preferences := ClientPreferences.new()
var panel: ClientSettingsPanel
var _windows: Array[DraggableGameWindow] = []
var _original_themes: Dictionary = {}
var _hud: HallHud
var _path := "user://client-settings.cfg"


## 将独立客户端偏好接入窗口、已有输入与音频总线，不持有人物存档。
## [param manager] 已创建的窗口集合。[param hud] 地图与系统提示。
## [param interactions] 世界输入路由。[param path] 测试可替换的本地偏好路径。
func configure(manager: GameWindowManager, hud: HallHud, interactions: WorldInteractionController,
		path := "user://client-settings.cfg") -> void:
	_hud = hud
	_path = path
	preferences.load_file(path)
	interactions.hotkeys = preferences.hotkeys
	hud.map_navigation_panel.hotkeys = preferences.hotkeys
	panel = ClientSettingsPanel.new()
	panel.position = Vector2(260, 100)
	manager.navigation_windows["settings"] = panel
	manager._add_window(panel)
	panel.bind_preferences(preferences)
	manager.navigation_windows["system"].settings_requested.connect(_open_section)
	for child in manager.get_children():
		if child is DraggableGameWindow: _register_window(child)
	_register_window(hud.map_navigation_panel)
	get_viewport().size_changed.connect(_apply)
	preferences.changed.connect(_changed)
	_apply()


## 记录原有主题供恢复默认使用，不修改共享主题资源。
## [param window] 已就绪的独立游戏窗口。
func _register_window(window: DraggableGameWindow) -> void:
	_windows.append(window)
	_original_themes[window] = window.theme


## 从原图系统菜单打开对应设置页。
## [param section] 已知设置类别。
func _open_section(section: String) -> void:
	panel.open_section(section)
	panel.show()
	panel.move_to_front()
	panel.clamp_to_viewport(get_viewport().get_visible_rect().size)


## 立即应用并持久化用户修改，磁盘故障不撤销当前可用设置。
func _changed() -> void:
	_apply()
	var error := preferences.save_file(_path)
	panel.status.text = "设置已保存，立即生效。" if error == OK else "本次设置已生效，但保存失败；下次启动可能恢复旧设置。"


## 同步窗口比例、通用文字和音量；世界镜头与语义颜色不受影响。
func _apply() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	for window in _windows:
		window.requested_ui_scale = preferences.window_scale
		window.clamp_to_viewport(viewport_size)
		var original: Theme = _original_themes[window]
		if preferences.palette == "default":
			window.theme = original
		else:
			var selected := original.duplicate() as Theme if original != null else Theme.new()
			var text_color := Color.WHITE if preferences.palette == "high_contrast" else Color("ffe9c7")
			selected.set_color("font_color", "Label", text_color)
			selected.set_color("default_color", "RichTextLabel", text_color)
			selected.set_color("font_color", "Button", text_color)
			window.theme = selected
	_hud.system_message_feed.set_text_color(Color("fff36b") if preferences.palette == "default" \
		else (Color.WHITE if preferences.palette == "high_contrast" else Color("ffe9c7")))
	_hud.map_navigation_panel.refresh_hotkey_hint()
	for channel: String in ClientPreferences.AUDIO_CHANNELS:
		var bus_name: String = {"master": "Master", "music": "Music", "effects": "Effects"}[channel]
		var index := AudioServer.get_bus_index(bus_name)
		if index < 0:
			AudioServer.add_bus()
			index = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Master")
		var volume: float = preferences.volumes[channel]
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume, 0.001)))
		AudioServer.set_bus_mute(index, volume <= 0 or (channel == "master" and preferences.muted))
