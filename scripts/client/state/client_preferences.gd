class_name ClientPreferences
extends RefCounted

signal changed
const SCALES := [1.0, 1.15, 1.3, 1.5]
const PALETTES := ["default", "high_contrast", "warm"]
const AUDIO_CHANNELS := ["master", "music", "effects"]
var window_scale := 1.0
var palette := "default"
var muted := false
var volumes := {"master": 0.8, "music": 0.65, "effects": 0.8}
var hotkeys := ClientHotkeys.new()


## 应用受控的窗口与字体同比例缩放。
## [param value] 支持的比例。
## 返回是否接受改变。
func set_window_scale(value: float) -> bool:
	if not value in SCALES: return false
	window_scale = value
	changed.emit()
	return true


## 应用通用文字配色，不处理物品品质等语义颜色。
## [param value] 已知配色身份。
## 返回是否接受改变。
func set_palette(value: String) -> bool:
	if not value in PALETTES: return false
	palette = value
	changed.emit()
	return true


## 调整独立音频通道的线性音量。
## [param channel] 总音量、音乐或音效。[param volume] 零至一音量。
## 返回是否接受改变。
func set_volume(channel: String, volume: float) -> bool:
	if not channel in AUDIO_CHANNELS or not is_finite(volume) or volume < 0 or volume > 1: return false
	volumes[channel] = volume
	changed.emit()
	return true


## 改变总静音偏好，同时保留各通道的原音量。
## [param value] 是否静音。
func set_muted(value: bool) -> void:
	muted = value
	changed.emit()


## 校验并更新快捷键，失败不改变现有输入行为。
## [param action] 已支持动作。[param chord] 逻辑键与修饰键。
## 返回明确的校验结果。
func bind_key(action: String, chord: int) -> DomainResult:
	var result := hotkeys.bind_key(action, chord)
	if result.is_ok: changed.emit()
	return result


## 恢复本地体验默认值，不接触玩家存档或智脑方案。
func reset() -> void:
	window_scale = 1.0
	palette = "default"
	muted = false
	volumes = {"master": 0.8, "music": 0.65, "effects": 0.8}
	hotkeys.restore(ClientHotkeys.DEFAULTS)
	hotkeys.capturing = false
	changed.emit()


## 保存独立的客户端偏好，不往角色权威状态写入显示选项。
## [param path] 本地偏好文件位置。
## 返回配置写入结果。
func save_file(path := "user://client-settings.cfg") -> Error:
	var config := ConfigFile.new()
	config.set_value("display", "scale", window_scale)
	config.set_value("display", "palette", palette)
	config.set_value("audio", "muted", muted)
	for channel: String in AUDIO_CHANNELS: config.set_value("audio", channel, volumes[channel])
	for action: String in ClientHotkeys.DEFAULTS: config.set_value("keys", action, hotkeys.snapshot()[action])
	return config.save(path)


## 从本地偏好恢复有效字段，损坏或非法字段使用默认值。
## [param path] 本地偏好文件位置。
## 返回文件读取结果；缺失文件仍保持可用默认值。
func load_file(path := "user://client-settings.cfg") -> Error:
	reset()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK: return error
	var scale_value: Variant = config.get_value("display", "scale", 1.0)
	if (scale_value is float or scale_value is int) and scale_value in SCALES: window_scale = float(scale_value)
	var palette_value: Variant = config.get_value("display", "palette", "default")
	if palette_value is String and palette_value in PALETTES: palette = palette_value
	var mute_value: Variant = config.get_value("audio", "muted", false)
	if mute_value is bool: muted = mute_value
	for channel: String in AUDIO_CHANNELS:
		var value: Variant = config.get_value("audio", channel, volumes[channel])
		if (value is float or value is int) and is_finite(float(value)) and value >= 0 and value <= 1:
			volumes[channel] = float(value)
	var keys: Dictionary = {}
	for action: String in ClientHotkeys.DEFAULTS: keys[action] = config.get_value("keys", action, ClientHotkeys.DEFAULTS[action])
	hotkeys.restore(keys)
	changed.emit()
	return OK
