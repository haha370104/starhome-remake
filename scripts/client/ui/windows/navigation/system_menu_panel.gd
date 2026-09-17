class_name SystemMenuPanel
extends NavigationWindow

signal exit_requested

## 还原免费版九行系统菜单图片，退出连接保存流程，其他入口由后续设置功能接管。
func _ready() -> void:
	var background := preload("res://assets/ui/windows/navigation/system_menu.png")
	build_window(background.get_size(), background, "")
	get_node("CloseButton").hide()
	_header_height = 0
	for index in range(9):
		var feature: String = ["字体设置", "颜色设置", "热键设置", "查看留言", "音乐音效", "帮助精灵", "网速测试", "查看信件", "退出"][index]
		var callback := exit_requested.emit if index == 8 else unavailable.bind(feature)
		var button := make_button("", Rect2(7, 4 + index * 18, 53, 18), callback)
		button.tooltip_text = feature
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(1, 1, 1, 0.18)
		button.add_theme_stylebox_override("hover", hover)
		button.add_theme_stylebox_override("pressed", hover)
