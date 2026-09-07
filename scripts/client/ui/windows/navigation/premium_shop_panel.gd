class_name PremiumShopPanel
extends NavigationWindow

const CATEGORIES := ["功能道具", "装饰特效", "充值物资"]
const SUBCATEGORIES := [
	["经验类", "修复类", "升级类", "维护类", "传送类", "通讯类", "生活类", "辅助类"],
	["人物变形", "装备变形", "装备特效", "人物背景", "装备背景", "特效物品", "超炫信纸", "浓情贺卡", "Q版请柬"],
	["镶嵌类", "服装类", "特殊类", "消耗类", "护卫类", "千级装备", "初级物资", "礼包类"],
]
var subcategories: OptionButton
var empty_label: Label
var search_input: LineEdit
var confirmation: Control
var _category := 0


## 按免费版商城创建分类、物品列表、详情区、搜索及进入确认；商品与支付保持关闭。
func _ready() -> void:
	build_window(Vector2(720, 502), preload("res://assets/ui/windows/navigation/premium_shop.png"), "")
	get_node("CloseButton").position = Vector2(690, 58)
	for index in range(CATEGORIES.size()):
		make_button(CATEGORIES[index], Rect2(16 + index * 84, 31, 80, 23), _select_category.bind(index))
	subcategories = OptionButton.new()
	subcategories.position = Vector2(24, 82)
	subcategories.size = Vector2(220, 26)
	subcategories.item_selected.connect(_select_subcategory)
	content_root.add_child(subcategories)
	empty_label = make_label("", Rect2(42, 168, 480, 160))
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	make_label("紫晶数量：待开放", Rect2(520, 40, 145, 20))
	make_label("物品信息", Rect2(594, 130, 100, 20))
	make_label("尚未选中商品", Rect2(567, 277, 115, 90))
	make_button("上一页", Rect2(30, 447, 70, 23), _page_empty)
	make_label("0 / 0", Rect2(240, 448, 70, 23))
	make_button("下一页", Rect2(420, 447, 70, 23), _page_empty)
	make_button("充值", Rect2(637, 82, 55, 23), unavailable.bind("商城充值"))
	make_button("查询", Rect2(560, 83, 55, 23), unavailable.bind("紫晶查询"))
	make_button("兑换", Rect2(560, 108, 55, 23), unavailable.bind("紫晶兑换"))
	make_button("购买", Rect2(612, 410, 64, 23), unavailable.bind("商城购买"))
	make_button("退出", Rect2(616, 467, 65, 23), request_close)
	search_input = LineEdit.new()
	search_input.placeholder_text = "搜索商品"
	search_input.position = Vector2(290, 468)
	search_input.size = Vector2(240, 23)
	search_input.text_submitted.connect(_search)
	content_root.add_child(search_input)
	make_button("搜索", Rect2(539, 467, 65, 23), _search_current)
	_build_confirmation()
	_select_category(0)


## 每次通过底栏打开时显示进入确认，不访问外链或触发付费业务。
func open_shop() -> void:
	for child: Node in content_root.get_children():
		if child is Control:
			child.visible = child == confirmation
	confirmation.visible = true
	confirmation.move_to_front()


## 创建游戏内进入商城提示，确认与取消均可直接交互。
func _build_confirmation() -> void:
	var panel := TextureRect.new()
	panel.texture = preload("res://assets/ui/windows/navigation/shop_confirmation.png")
	confirmation = panel
	confirmation.position = Vector2(210, 170)
	confirmation.size = Vector2(300, 150)
	confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	content_root.add_child(confirmation)
	var message := Label.new()
	message.text = "为了保障您角色的安全，建议您在安全的环境下进入游戏商城。\n您确定要进入游戏商城吗？"
	message.position = Vector2(15, 18)
	message.size = Vector2(270, 85)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirmation.add_child(message)
	for index in range(2):
		var button := Button.new()
		button.text = ["确定", "取消"][index]
		button.position = Vector2(65 + index * 95, 112)
		button.size = Vector2(75, 24)
		button.pressed.connect(_confirm_entry if index == 0 else request_close)
		confirmation.add_child(button)


## 确认进入商城，仍不开放任何尚未定义的商品交易。
func _confirm_entry() -> void:
	for child: Node in content_root.get_children():
		if child is Control:
			child.show()
	confirmation.hide()


## 切换原版商品大类并重建对应子类。
## [param category] 三个原版大类的序号。
func _select_category(category: int) -> void:
	_category = category
	subcategories.clear()
	for label: String in SUBCATEGORIES[category]:
		subcategories.add_item(label)
	_select_subcategory(0)


## 展示未开放分类的空状态，不伪造售价或数量。
## [param index] 当前大类内的子分类序号。
func _select_subcategory(index: int) -> void:
	empty_label.text = "%s / %s\n\n售卖物品待定，当前暂无商品。" % [CATEGORIES[_category], SUBCATEGORIES[_category][index]]


## 空目录翻页时保持零页数并给出明确提示。
func _page_empty() -> void:
	notice_requested.emit("当前暂无商品可翻页")


## 使用输入框中的查询词执行本地空目录搜索。
func _search_current() -> void:
	_search(search_input.text)


## 展示商城搜索空结果，不发送购买或付费请求。
## [param keyword] 玩家输入的商品查询词。
func _search(keyword: String) -> void:
	empty_label.text = "搜索：%s\n\n商品目录尚未开放，没有匹配商品。" % keyword.strip_edges()
