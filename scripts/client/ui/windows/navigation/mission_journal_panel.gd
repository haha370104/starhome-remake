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
	build_modern_window(Vector2(380, 466), "任务日志")
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
	abandon_action = Button.new()
	abandon_action.text = "放弃"
	abandon_action.flat = true
	abandon_action.focus_mode = Control.FOCUS_NONE
	abandon_action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	abandon_action.add_theme_color_override("font_color", Color("71c6d5"))
	abandon_action.add_theme_color_override("font_hover_color", Color("e9fbff"))
	for state in ["hover", "pressed"]:
		abandon_action.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	abandon_action.pressed.connect(_abandon_hovered)
	abandon_action.visible = false
	listing.add_child(abandon_action)
	var detail_heading := make_label("任务详情", Rect2(20, 216, 340, 24))
	detail_heading.add_theme_color_override("font_color", Color("71c6d5"))
	details = RichTextLabel.new()
	details.position = Vector2(20, 246)
	details.size = Vector2(340, 196)
	details.add_theme_stylebox_override("normal", _surface_style("152330", "273b4b"))
	details.add_theme_constant_override("line_separation", 4)
	content_root.add_child(details)
	visibility_changed.connect(func() -> void:
		if visible: _select_category(_category))
	_select_category(_category)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		abandon_action.visible = false
		return
	var pointer := listing.get_local_mouse_position()
	if not Rect2(Vector2.ZERO, listing.size).has_point(pointer):
		abandon_action.visible = false
		return
	var index := listing.get_item_at_position(pointer, true)
	if index < 0 or not bool(listing.get_item_metadata(index).get("accepted", false)):
		abandon_action.visible = false
		return
	var item_rect := listing.get_item_rect(index)
	abandon_action.position = Vector2(listing.size.x - 52, item_rect.position.y)
	abandon_action.size = Vector2(52, item_rect.size.y)
	abandon_action.set_meta("entry", listing.get_item_metadata(index))
	abandon_action.visible = true


## 接收同一人物与背包版本的权威任务投影。
## [param entries] 已接取或存在完成记录的任务列表。
func apply_entries(entries: Array) -> void:
	_entries = entries.duplicate(true)
	if is_visible_in_tree(): _select_category(_category)


## 切换日志分类，不伪造尚未导入的任务。
## [param category] 免费版四页中的分类序号。
func _select_category(category: int) -> void:
	var selected_id := ""
	var selected_items := listing.get_selected_items()
	if not selected_items.is_empty():
		selected_id = String(listing.get_item_metadata(selected_items[0]).get("task_id", ""))
	var scroll := listing.get_v_scroll_bar().value if category == _category else 0.0
	_category = category
	for index in range(_category_buttons.size()):
		_category_buttons[index].set_pressed_no_signal(index == category)
	listing.clear()
	abandon_action.visible = false
	var selected_index := 0
	for entry: Dictionary in _entries:
		if int(entry.get("category", 0)) != category:
			continue
		var status := "可交付" if entry.get("ready_to_turn_in", false) else "进行中" if entry.get("accepted", false) else "已完成"
		var index := listing.add_item("%s · %s" % [entry["title"], status])
		listing.set_item_metadata(index, entry)
		listing.set_item_tooltip_enabled(index, false)
		if String(entry.get("task_id", "")) == selected_id:
			selected_index = index
	details.text = "此分类暂无已领取任务。"
	if listing.item_count > 0:
		listing.select(selected_index)
		_show_detail(selected_index)
	listing.get_v_scroll_bar().set_deferred("value", scroll)


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


func _abandon_hovered() -> void:
	if not abandon_action.has_meta("entry"):
		return
	var entry: Dictionary = abandon_action.get_meta("entry")
	if not bool(entry.get("accepted", false)):
		return
	command_requested.emit({
		"type": "abandon_weapon_merchant_task",
		"merchant_id": String(entry.get("provider_id", "")),
		"task_id": String(entry.get("task_id", "")),
	})
