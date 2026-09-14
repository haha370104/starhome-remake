class_name AchievementsPanel
extends ModernNavigationWindow

const CATEGORIES := ["kill", "mine", "quest", "titles"]
const CATEGORY_NAMES := ["击杀成就", "采矿成就", "任务成就", "称号阶梯"]
const ACTION_NAMES := {"kill": "击杀", "mine": "采集", "quest": "完成"}
const BONUS_NAMES := {"energy_cannon_attack": "能量炮攻击", "energy_cannon_range": "能量炮射程",
	"rocket_attack": "火箭炮攻击", "missile_attack": "导弹攻击", "max_health": "战车生命上限", "self_repair": "每次自维修"}

var listing: ItemList
var details: RichTextLabel
var search: LineEdit
var summary: Label
var _category := "kill"
var _snapshot: Dictionary = {}
var _tabs: Array[Button] = []


## 构建成就浏览器，只消费权威投影，不提供积分或称号写入口。
func _ready() -> void:
	build_modern_window(Vector2(740, 520), "成就系统")
	summary = make_label("正在读取成就…", Rect2(20, 54, 700, 32))
	summary.add_theme_font_size_override("font_size", 18)
	summary.add_theme_color_override("font_color", Color("71c6d5"))
	var hint := make_label("达标自动获得成就点 · 自动晋升 · 仅最高称号生效", Rect2(20, 91, 700, 24))
	hint.add_theme_font_size_override("font_size", 14)
	for index in CATEGORIES.size():
		var button := make_button(CATEGORY_NAMES[index], Rect2(20 + index * 99, 128, 94, 34), _select_category.bind(CATEGORIES[index]))
		_style_button(button)
		button.toggle_mode = true
		_tabs.append(button)
	search = LineEdit.new()
	search.position = Vector2(430, 128)
	search.size = Vector2(290, 34)
	search.placeholder_text = "搜索目标或称号"
	search.text_changed.connect(func(_text: String) -> void: _rebuild_list())
	content_root.add_child(search)
	listing = ItemList.new()
	listing.position = Vector2(20, 176)
	listing.size = Vector2(320, 282)
	listing.add_theme_stylebox_override("panel", _surface_style("0c1520", "273b4b"))
	listing.add_theme_stylebox_override("selected", _surface_style("224457", "3b7187"))
	listing.add_theme_stylebox_override("selected_focus", _surface_style("224457", "63c5d6"))
	listing.add_theme_constant_override("line_separation", 8)
	listing.item_selected.connect(_show_detail)
	content_root.add_child(listing)
	details = RichTextLabel.new()
	details.position = Vector2(356, 176)
	details.size = Vector2(364, 282)
	details.add_theme_stylebox_override("normal", _surface_style("152330", "273b4b"))
	details.add_theme_constant_override("line_separation", 5)
	content_root.add_child(details)
	_style_button(make_button("关闭", Rect2(320, 472, 100, 34), request_close))
	_select_category(_category)


## 应用同一玩家版本的成就投影，并保留分类、搜索和当前选中项。
## [param snapshot] 服务器成就进度、积分和称号展示数据。
func apply_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	summary.text = "成就点  %d    ·    %s" % [int(snapshot.get("points", 0)), String(snapshot.get("title_name", "未获得称号"))]
	_rebuild_list()


## 切换成就类别或称号阶梯。
## [param category] 已登记的类别标识。
func _select_category(category: String) -> void:
	_category = category
	for index in _tabs.size():
		_tabs[index].set_pressed_no_signal(CATEGORIES[index] == category)
	_rebuild_list()


## 根据分类和搜索词重建展示列表，保留已选条目与滚动位置。
func _rebuild_list() -> void:
	if listing == null:
		return
	var selected_id := ""
	if not listing.get_selected_items().is_empty():
		selected_id = String(listing.get_item_metadata(listing.get_selected_items()[0]).get("id", ""))
	var scroll := listing.get_v_scroll_bar().value
	listing.clear()
	var selected := 0
	var rows: Array = _snapshot.get("titles" if _category == "titles" else "entries", [])
	for row: Dictionary in rows:
		if _category != "titles" and row.get("category") != _category:
			continue
		var name_text := String(row.get("name", row.get("target_name", "")))
		if not search.text.is_empty() and not name_text.contains(search.text.strip_edges()):
			continue
		var text := "%s · %d点%s" % [name_text, int(row.get("required_points", 0)), " · 生效中" if row.get("active", false) else ""] \
			if _category == "titles" else "%s · %d / %d%s" % [name_text, int(row.get("progress", 0)), int(row.get("required", 0)), " ✓" if row.get("completed", false) else ""]
		var index := listing.add_item(text)
		listing.set_item_metadata(index, row)
		listing.set_item_tooltip(index, text)
		if String(row.get("id", "")) == selected_id:
			selected = index
	details.text = "没有匹配的成就。" if not _snapshot.is_empty() else "正在读取成就…"
	if listing.item_count > 0:
		listing.select(selected)
		_show_detail(selected)
	listing.get_v_scroll_bar().set_deferred("value", scroll)


## 展示目标、进度和积分奖励，或称号门槛与完整增益。
## [param index] 已选中的列表行。
func _show_detail(index: int) -> void:
	var row: Dictionary = listing.get_item_metadata(index)
	if _category == "titles":
		var lines := PackedStringArray([String(row["name"]), "需要成就点：%d" % int(row["required_points"]),
			"当前生效" if row.get("active", false) else "已解锁（更高称号已生效）" if row.get("unlocked", false) else "尚未解锁", ""])
		for key: String in BONUS_NAMES:
			var bonus := int(row.get("bonuses", {}).get(key, 0))
			if bonus > 0:
				lines.append("%s +%d" % [BONUS_NAMES[key], bonus])
		if lines.size() == 4:
			lines.append("暂无战斗增益")
		details.text = "\n".join(lines)
	else:
		details.text = "%s\n\n%s目标：%s\n累计进度：%d / %d\n成就奖励：%d 点\n\n%s\n\n进度以服务器确认的结算为准。" % [
			String(row["target_name"]), ACTION_NAMES[_category], String(row["target_name"]),
			int(row["progress"]), int(row["required"]), int(row["points"]),
			"已达成，成就点已自动计入。" if row.get("completed", false) else "达标后自动获得成就点。"]
