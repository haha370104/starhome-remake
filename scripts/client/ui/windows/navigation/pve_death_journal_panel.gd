class_name PveDeathJournalPanel
extends ModernNavigationWindow

signal clear_requested
var listing: RichTextLabel
var confirmation: ConfirmationDialog


## 组合可滚动击毁记录和明确的清除确认，沿用公共窗口堆叠和字体。
func _ready() -> void:
	build_modern_window(Vector2(700, 520), "PVE击毁记录")
	make_label("最近100条 · 本角色本地保存 · 最新记录在前", Rect2(24, 60, 652, 28))
	listing = RichTextLabel.new()
	listing.position = Vector2(24, 104)
	listing.size = Vector2(652, 348)
	listing.text = "暂无记录"
	listing.selection_enabled = true
	content_root.add_child(listing)
	_style_button(make_button("清除记录", Rect2(514, 472, 162, 32), _ask_clear))
	confirmation = ConfirmationDialog.new()
	confirmation.title = "清除本地击毁记录"
	confirmation.dialog_text = "清除当前角色的全部本地击毁记录？这不会修改角色存档、装备或奖励。"
	confirmation.ok_button_text = "清除"
	confirmation.cancel_button_text = "保留"
	confirmation.confirmed.connect(func() -> void: clear_requested.emit())
	add_child(confirmation)
	visibility_changed.connect(func() -> void:
		if not visible: confirmation.hide()
	)


## 格式化权威来源的日志，不启用可注入格式的BBCode。
## [param entries] 最新在前的本地记录副本。
func apply_entries(entries: Array[Dictionary]) -> void:
	var lines := PackedStringArray()
	for entry in entries:
		var stamp := Time.get_datetime_string_from_unix_time(int(entry.time)).replace("T", " ")
		lines.append("%s UTC  ·  %s\n%s · %s · 伤害%d\n坐标（%.0f，%.0f）\n" % [stamp, entry.map,
			entry.source, entry.cause, entry.damage, float(entry.position[0]), float(entry.position[1])])
	listing.text = "\n".join(lines) if not lines.is_empty() else "暂无记录"


## 请求清除前让用户确认当前角色日志范围。
func _ask_clear() -> void:
	confirmation.popup_centered(Vector2i(530, 156))
