class_name ScenePlayersPanel
extends NavigationWindow

var listing: Tree
var heading: Label
var _sort_column := 0
var _ascending := true
var _players: Array = []


## 还原用户列表标题、四列、列头排序及用户行交互。
func _ready() -> void:
	build_window(Vector2(320, 450), preload("res://assets/ui/windows/navigation/scene_players.png"), "用户列表")
	heading = make_label("当前区域在线用户列表", Rect2(25, 49, 270, 24))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	listing = Tree.new()
	listing.position = Vector2(18, 88)
	listing.size = Vector2(284, 314)
	listing.columns = 4
	listing.hide_root = true
	listing.column_titles_visible = true
	for column in range(4):
		listing.set_column_title(column, ["用户名", "性别", "战果", "战斗积分"][column])
		listing.set_column_custom_minimum_width(column, [110, 40, 48, 64][column])
		listing.set_column_expand(column, column == 0)
	listing.column_title_clicked.connect(_sort_by_column)
	listing.item_activated.connect(_activate_user)
	content_root.add_child(listing)
	make_button("关闭", Rect2(125, 411, 70, 23), request_close)


## 应用服务端仅含本区域在线会话的公开列表。
## [param snapshot] 不含背包、账号信息的区域玩家列表协议。
func apply_snapshot(snapshot: Dictionary) -> void:
	_players = (snapshot.get("players", []) as Array).duplicate(true)
	heading.text = "当前区域在线用户列表（%d）" % _players.size()
	_render_rows()


## 切换指定列的升降序。
## [param column] 用户点击的列编号。
## [param _mouse_button] 引擎派发的鼠标键编号。
func _sort_by_column(column: int, _mouse_button: int) -> void:
	_ascending = not _ascending if column == _sort_column else true
	_sort_column = column
	_render_rows()


## 根据当前排序稳定生成列表，未实现的战果数值显示破折号而非假零值。
func _render_rows() -> void:
	var key: String = ["display_name", "sex", "battle_result", "combat_score"][_sort_column]
	_players.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: Variant = a.get(key)
		var right: Variant = b.get(key)
		if left == right:
			return String(a["entity_id"]) < String(b["entity_id"])
		if left == null or right == null:
			return right == null
		return left < right if _ascending else left > right
	)
	listing.clear()
	var root := listing.create_item()
	for row: Dictionary in _players:
		var item := listing.create_item(root)
		item.set_text(0, String(row["display_name"]))
		item.set_text(1, "男" if row.get("sex") == "male" else "女" if row.get("sex") == "female" else "—")
		for column in [2, 3]:
			var value: Variant = row.get(["battle_result", "combat_score"][column - 2])
			item.set_text(column, "—" if value == null else str(value))
		item.set_metadata(0, row["entity_id"])


## 响应用户行双击，未实现的社交操作不假装发送私聊或好友请求。
func _activate_user() -> void:
	if listing.get_selected() != null:
		unavailable("与 %s 的社交操作" % listing.get_selected().get_text(0))
