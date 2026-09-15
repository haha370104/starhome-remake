class_name DailyActivitiesPanel
extends NavigationWindow

signal command_requested(command: Dictionary)

var mode := "mercenary"
var summary: Label
var available: ItemList
var active: ItemList
var details: RichTextLabel
var accept_button: Button
var complete_button: Button
var abandon_button: Button
var _snapshot: Dictionary = {}
var _inventory_revision := -1
var _rows: Array = []
var _active_rows: Array = []
const GRADES := ["F", "E", "D", "C", "B", "A", "S", "SS"]
const COLORS := [Color("e2eaf0"), Color("80d695"), Color("75bfff"), Color("d1a0ff")]


## 创建共用任务窗口；佣兵双栏和历练单栏共用状态及命令适配。
func _ready() -> void:
	build_window(Vector2(820, 550), null, "佣兵任务" if mode == "mercenary" else "人物历练")
	theme.default_font_size = 16
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101f2b")
	style.border_color = Color("43849a")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	move_child(panel, 0)
	summary = make_label("正在读取任务…", Rect2(24, 54, 780, 28))
	make_button("刷新", Rect2(694, 92, 100, 32), open_board)
	make_label("可接委托" if mode == "mercenary" else "每日固定目标 · 北京时间 0 点刷新", Rect2(24, 96, 620, 24))
	available = _list(Rect2(24, 132, 376 if mode == "mercenary" else 770, 270))
	available.item_selected.connect(_show_available)
	active = _list(Rect2(420, 132, 374, 270))
	active.visible = mode == "mercenary"
	active.item_selected.connect(_show_active)
	if mode == "mercenary":
		make_label("已接委托 · 跨日保留", Rect2(420, 96, 265, 24))
	details = RichTextLabel.new()
	details.position = Vector2(24, 412)
	details.size = Vector2(770, 76)
	content_root.add_child(details)
	accept_button = make_button("领取委托" if mode == "mercenary" else "领取奖励", Rect2(24, 502, 150, 32), _accept)
	complete_button = make_button("交付并领奖", Rect2(420, 502, 170, 32), _complete)
	abandon_button = make_button("放弃任务", Rect2(624, 502, 170, 32), _abandon)
	complete_button.visible = mode == "mercenary"
	abandon_button.visible = mode == "mercenary"
	_update_buttons()


## 创建任务列表，滚动和选择由原生控件负责。
## [param rect] 窗口内布局。
## 返回已挂接列表。
func _list(rect: Rect2) -> ItemList:
	var result := ItemList.new()
	result.position = rect.position
	result.size = rect.size
	result.add_theme_constant_override("v_separation", 10)
	content_root.add_child(result)
	return result


## 打开或刷新时请求服务器换日后的最新任务栏。
func open_board() -> void:
	command_requested.emit({"type": "query_daily_activities"})


## 接收同一事务的活动状态和背包版本，保持仍存在的选择。
## [param bundle] 已提交的玩家面板响应。
func apply_activity_bundle(bundle: Dictionary) -> void:
	if bundle.get("inventory") is Dictionary:
		_inventory_revision = int(bundle.inventory.get("revision", -1))
	if not bundle.get("daily_activities") is Dictionary or available == null:
		return
	var selected := _selected_id(available, _rows, "id")
	var selected_active := _selected_id(active, _active_rows, "ticket")
	_snapshot = bundle.daily_activities.duplicate(true)
	_rows = _snapshot.offers if mode == "mercenary" else _snapshot.experience
	if mode == "experience":
		_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.enabled) > int(b.enabled) if a.enabled != b.enabled else int(a.id) < int(b.id)
		)
	_active_rows = _snapshot.active
	summary.text = "%s  ·  紫晶 %d  ·  今日领取 %d/%d  ·  完成 %d/%d" % [_snapshot.day,
		_snapshot.amethyst, _snapshot.accepted_today, _snapshot.daily_limit, _snapshot.completed_today, _snapshot.completion_limit]
	summary.tooltip_text = "放弃任务不退还领取次数，也不占完成次数。北京时间0点重置，已接任务跨日保留。"
	available.clear()
	active.clear()
	for row: Dictionary in _rows:
		var text := "[%s] %s ×%d · %d 紫晶" % [GRADES[int(row.get("grade", 1)) - 1], row.title, int(row.get("quantity", 1)), row.reward]
		if mode != "mercenary":
			var title := String(row.title)
			if String(row.id) in ["8", "10"]:
				title = "完成 %d 次佣兵任务" % (10 if String(row.id) == "8" else 20)
			text = "%s  %d/%d  ·  %d 紫晶/次%s" % [title, row.progress, row.limit, row.reward,
				"（暂未开放）" if not row.enabled else ""]
		available.add_item(text)
		available.set_item_tooltip(available.item_count - 1, text + "\n" + String(row.description))
		available.set_item_custom_fg_color(available.item_count - 1, COLORS[clampi(int(row.get("quality", 1)) - 1, 0, 3)])
		if String(row.id) == selected:
			available.select(available.item_count - 1)
	for row: Dictionary in _active_rows:
		active.add_item("[%s] %s  %d/%d" % [GRADES[int(row.grade) - 1], row.title, row.progress, row.quantity])
		if String(row.ticket) == selected_active:
			active.select(active.item_count - 1)
	if not active.get_selected_items().is_empty():
		_show_active(active.get_selected_items()[0])
	elif not available.get_selected_items().is_empty():
		_show_available(available.get_selected_items()[0])
	else:
		details.text = "选择一项任务查看条件与奖励。"
		_update_buttons()


## 保留刷新前选择的稳定任务身份。
## [param list] 当前列表。
## [param rows] 列表行数据。
## [param key] 定义或实例身份字段。
## 返回选中身份；没有选择时为空。
func _selected_id(list: ItemList, rows: Array, key: String) -> String:
	var selected := list.get_selected_items()
	return String(rows[selected[0]].get(key, "")) if not selected.is_empty() and selected[0] < rows.size() else ""


## 显示任务条件与奖励，暂未开放的历练给出原因。
## [param index] 可接或历练列表索引。
func _show_available(index: int) -> void:
	var row: Dictionary = _rows[index]
	details.text = String(row.description)
	if mode == "mercenary" and not row.locations.is_empty():
		details.text += "\n分布：" + ", ".join(row.locations.slice(0, 4)).replace("glory_nft_", "").to_upper()
	elif mode != "mercenary":
		details.text += "\n已领奖 %d 次。%s" % [row.claimed, row.unavailable_reason]
	_update_buttons()


## 显示已接委托的交付条件。
## [param index] 当前已接列表索引。
func _show_active(index: int) -> void:
	var row: Dictionary = _active_rows[index]
	details.text = "%s\n奖励 %d 紫晶%s" % [row.description, row.reward,
		"；交付会扣除星际币。" if bool(row.get("currency_donation", false)) else ("；交付会消耗对应材料。" if int(row.kind) == 2 else "。")]
	if not row.locations.is_empty():
		details.text += "\n分布：" + ", ".join(row.locations.slice(0, 4)).replace("glory_nft_", "").to_upper()
	_update_buttons()


## 根据选择和服务端进度禁用无效操作。
func _update_buttons() -> void:
	accept_button.disabled = available.get_selected_items().is_empty()
	accept_button.tooltip_text = ""
	complete_button.tooltip_text = ""
	if mode == "mercenary" and not _snapshot.is_empty():
		if int(_snapshot.accepted_today) >= int(_snapshot.daily_limit):
			accept_button.disabled = true
			accept_button.tooltip_text = "今日领取次数已达上限"
		elif _active_rows.size() >= int(_snapshot.active_limit):
			accept_button.disabled = true
			accept_button.tooltip_text = "同时持有任务数已达上限"
	if not accept_button.disabled and mode != "mercenary":
		var row: Dictionary = _rows[available.get_selected_items()[0]]
		accept_button.disabled = not bool(row.enabled) or int(row.progress) <= int(row.claimed)
	abandon_button.disabled = active.get_selected_items().is_empty()
	complete_button.disabled = abandon_button.disabled
	if not complete_button.disabled:
		complete_button.disabled = not bool(_active_rows[active.get_selected_items()[0]].ready)
	if mode == "mercenary" and not _snapshot.is_empty() and int(_snapshot.completed_today) >= int(_snapshot.completion_limit):
		complete_button.disabled = true
		complete_button.tooltip_text = "今日完成次数已达上限，已接任务可明天交付"


## 发布接取委托或历练领奖意图。
func _accept() -> void:
	_send("accept_mercenary" if mode == "mercenary" else "claim_experience", {"task_id": _selected_id(available, _rows, "id")})


## 发布所选已接任务的交付意图。
func _complete() -> void:
	_send("complete_mercenary", {"ticket": _selected_id(active, _active_rows, "ticket")})


## 发布放弃意图，次数是否退还由领域规则决定。
func _abandon() -> void:
	_send("abandon_mercenary", {"ticket": _selected_id(active, _active_rows, "ticket")})


## 为任务意图附加最后看到的版本，不包含奖励或目标进度。
## [param action] 服务器命令类型。
## [param fields] 所选任务身份。
func _send(action: String, fields: Dictionary) -> void:
	fields.merge({"type": action, "daily_revision": int(_snapshot.get("revision", -1)), "inventory_revision": _inventory_revision})
	command_requested.emit(fields)
