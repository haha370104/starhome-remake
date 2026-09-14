class_name MissionJournalPanel
extends NavigationWindow

var listing: ItemList
var details: RichTextLabel
var _entries: Array = []
var _category := 0
var _category_buttons: Array[Button] = []


## 创建免费版四分类任务日志，当前已登记任务归入新兵任务。
func _ready() -> void:
	build_window(Vector2(380, 520), null, "")
	theme.default_font_size = 16
	theme.set_color("font_color", "Label", Color("e4edf4"))
	theme.set_color("default_color", "RichTextLabel", Color("c3d0dc"))
	get_node("Background").hide()
	get_node("CloseButton").hide()
	var surface := Panel.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var surface_style := _surface_style("111d29", "3c7286")
	surface_style.shadow_color = Color(0, 0, 0, 0.35)
	surface_style.shadow_size = 8
	surface.add_theme_stylebox_override("panel", surface_style)
	add_child(surface)
	move_child(surface, 0)
	var title := make_label("任务日志", Rect2(20, 16, 280, 28))
	title.add_theme_font_size_override("font_size", 20)
	_style_button(make_button("×", Rect2(330, 14, 30, 30), request_close))
	for index in range(4):
		var button := make_button(["新兵任务", "中级任务", "高级任务", "家园活动"][index], Rect2(20 + index * 86, 60, 82, 34), _select_category.bind(index))
		_style_button(button)
		button.toggle_mode = true
		_category_buttons.append(button)
	listing = ItemList.new()
	listing.position = Vector2(20, 108)
	listing.size = Vector2(340, 96)
	listing.add_theme_stylebox_override("panel", _surface_style("0c1520", "273b4b"))
	listing.add_theme_stylebox_override("selected", _surface_style("224457", "3b7187"))
	listing.add_theme_stylebox_override("selected_focus", _surface_style("224457", "63c5d6"))
	listing.add_theme_color_override("font_color", Color("c3d0dc"))
	listing.add_theme_color_override("font_selected_color", Color("e9fbff"))
	listing.add_theme_constant_override("line_separation", 8)
	listing.item_selected.connect(_show_detail)
	content_root.add_child(listing)
	var detail_heading := make_label("任务详情", Rect2(20, 216, 340, 24))
	detail_heading.add_theme_color_override("font_color", Color("71c6d5"))
	details = RichTextLabel.new()
	details.position = Vector2(20, 246)
	details.size = Vector2(340, 208)
	details.add_theme_stylebox_override("normal", _surface_style("152330", "273b4b"))
	details.add_theme_constant_override("line_separation", 4)
	content_root.add_child(details)
	_style_button(make_button("关闭", Rect2(140, 470, 100, 34), request_close))
	_select_category(_category)


## 创建日志内统一的圆角底板，保留文字与边框之间的留白。
## [param fill] 底色的十六进制字符串。
## [param border] 边框颜色的十六进制字符串。
## 返回供背景、列表和按钮复用的样式。
func _surface_style(fill: String, border: String) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(fill)
	style.border_color = Color(border)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


## 配置日志按钮的悬停、选中与键盘焦点状态。
## [param button] 已挂接到日志窗口的按钮。
func _style_button(button: Button) -> void:
	button.add_theme_stylebox_override("normal", _surface_style("192c3b", "304b5e"))
	button.add_theme_stylebox_override("hover", _surface_style("27485a", "63c5d6"))
	button.add_theme_stylebox_override("pressed", _surface_style("28566a", "63c5d6"))
	button.add_theme_stylebox_override("hover_pressed", _surface_style("306578", "8edee8"))
	var focus := _surface_style("192c3b", "8edee8")
	focus.draw_center = false
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_color_override("font_color", Color("b9cbd8"))
	button.add_theme_color_override("font_pressed_color", Color("edfcff"))
	button.add_theme_color_override("font_hover_color", Color("ffffff"))
	button.add_theme_color_override("font_hover_pressed_color", Color("ffffff"))


## 接收同一人物与背包版本的权威任务投影。
## [param entries] 已接取或存在完成记录的任务列表。
func apply_entries(entries: Array) -> void:
	_entries = entries.duplicate(true)
	_select_category(_category)


## 切换日志分类，不伪造尚未导入的任务。
## [param category] 免费版四页中的分类序号。
func _select_category(category: int) -> void:
	_category = category
	for index in range(_category_buttons.size()):
		_category_buttons[index].set_pressed_no_signal(index == category)
	listing.clear()
	for entry: Dictionary in _entries:
		if int(entry.get("category", 0)) != category:
			continue
		var status := "可交付" if entry.get("ready_to_turn_in", false) else "进行中" if entry.get("accepted", false) else "已完成"
		var index := listing.add_item("%s · %s" % [entry["title"], status])
		listing.set_item_metadata(index, entry)
	details.text = "此分类暂无已领取任务。"
	if listing.item_count > 0:
		listing.select(0)
		_show_detail(0)


## 展示任务交付条件、背包材料进度、完成次数和奖励，不在日志里远程交任务。
## [param index] 当前分类内的任务行号。
func _show_detail(index: int) -> void:
	var entry: Dictionary = listing.get_item_metadata(index)
	var lines := PackedStringArray([String(entry["title"])])
	var training := String(entry.get("kind", "")) == "kill_training"
	lines.append("今日接取：%d / %d" % [entry.get("daily_accepted", 0), entry.get("daily_accept_limit", 0)] if training \
		else "完成次数：%d / %d" % [entry["completions"], entry["maximum_completions"]])
	for requirement: Dictionary in entry.get("requirements", []):
		lines.append("%s：%d / %d" % [requirement["display_name"], requirement["owned"], requirement["required"]])
	lines.append("奖励：%s等级 +1" % String(entry["title"]).trim_suffix("训练") if training \
		else "报酬：%d 金币" % int(entry.get("currency_reward", 0)))
	lines.append("请返回任务发布者处交付或领取下一轮。")
	details.text = "\n".join(lines)
