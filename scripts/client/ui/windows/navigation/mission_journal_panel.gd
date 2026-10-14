class_name MissionJournalPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var listing: ItemList
var details: RichTextLabel
var abandon_action: Button
var _entries: Array = []
var _category := 0
var _category_buttons: Array[Button] = []


## 创建免费版四分类任务日志，当前已登记任务归入新兵任务。
func _ready() -> void:
	build_modern_window(Vector2(380, 520), "任务日志")
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
	abandon_action = make_button("放弃任务", Rect2(70, 470, 110, 34), _abandon_selected)
	_style_button(abandon_action)
	_style_button(make_button("关闭", Rect2(200, 470, 100, 34), request_close))
	_select_category(_category)


## 接收同一人物与背包版本的权威任务投影。
## [param entries] 已接取或存在完成记录的任务列表。
func apply_entries(entries: Array) -> void:
	_entries = entries.duplicate(true)
	_select_category(_category)


## 切换日志分类，不伪造尚未导入的任务。
## [param category] 免费版四页中的分类序号。
func _select_category(category: int) -> void:
	var selected_id := ""
	var same_category := category == _category
	var selected := listing.get_selected_items()
	if same_category and not selected.is_empty():
		selected_id = String(listing.get_item_metadata(selected[0]).get("task_id", ""))
	var scroll := listing.get_v_scroll_bar().value if same_category else 0.0
	_category = category
	for index in range(_category_buttons.size()):
		_category_buttons[index].set_pressed_no_signal(index == category)
	listing.clear()
	var selected_index := 0
	for entry: Dictionary in _entries:
		if int(entry.get("category", 0)) != category:
			continue
		var status := "可交付" if entry.get("ready_to_turn_in", false) else "进行中" if entry.get("accepted", false) else "已完成"
		var index := listing.add_item("%s · %s" % [entry["title"], status])
		listing.set_item_metadata(index, entry)
		if String(entry.get("task_id", "")) == selected_id:
			selected_index = index
	details.text = "此分类暂无已领取任务。"
	abandon_action.disabled = true
	if listing.item_count > 0:
		listing.select(selected_index)
		_show_detail(selected_index)
	listing.get_v_scroll_bar().set_deferred("value", scroll)


## 展示任务交付条件、背包材料进度、完成次数和奖励，不在日志里远程交任务。
## [param index] 当前分类内的任务行号。
func _show_detail(index: int) -> void:
	var entry: Dictionary = listing.get_item_metadata(index)
	abandon_action.disabled = not bool(entry.get("accepted", false))
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


## 发布放弃选中任务的意图；客户端不修改额度或累计奖励状态。
func _abandon_selected() -> void:
	var selected := listing.get_selected_items()
	if selected.is_empty():
		return
	var entry: Dictionary = listing.get_item_metadata(selected[0])
	if not bool(entry.get("accepted", false)):
		return
	command_requested.emit({"type": "abandon_weapon_merchant_task",
		"merchant_id": String(entry.get("provider_id", "")),
		"task_id": String(entry.get("task_id", ""))})
