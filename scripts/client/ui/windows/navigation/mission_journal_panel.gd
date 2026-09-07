class_name MissionJournalPanel
extends NavigationWindow

var listing: ItemList
var details: RichTextLabel
var _entries: Array = []
var _category := 0


## 创建免费版四分类任务日志，当前已登记任务归入新兵任务。
func _ready() -> void:
	build_window(Vector2(250, 350), preload("res://assets/ui/windows/navigation/mission_journal.png"), "任务日志")
	for index in range(4):
		make_button(["新兵任务", "中级任务", "高级任务", "家园活动"][index], Rect2(15 + index * 55, 40, 55, 24), _select_category.bind(index))
	listing = ItemList.new()
	listing.position = Vector2(16, 73)
	listing.size = Vector2(218, 97)
	listing.item_selected.connect(_show_detail)
	content_root.add_child(listing)
	details = RichTextLabel.new()
	details.position = Vector2(19, 177)
	details.size = Vector2(212, 128)
	content_root.add_child(details)
	make_button("关闭", Rect2(90, 312, 70, 23), request_close)


## 接收同一人物与背包版本的权威任务投影。
## [param entries] 已接取或存在完成记录的任务列表。
func apply_entries(entries: Array) -> void:
	_entries = entries.duplicate(true)
	_select_category(_category)


## 切换日志分类，不伪造尚未导入的任务。
## [param category] 免费版四页中的分类序号。
func _select_category(category: int) -> void:
	_category = category
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
