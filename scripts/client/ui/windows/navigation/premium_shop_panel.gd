class_name PremiumShopPanel
extends NavigationWindow

signal command_requested(command: Dictionary)
signal attachment_upgrade_requested

const CATEGORIES := ["功能道具", "装饰特效", "充值物资", "接合器"]
const SHOP_FONT_SIZE := 16
const SUBCATEGORIES := [
	["经验类", "修复类", "升级类", "维护类", "传送类", "通讯类", "生活类", "辅助类"],
	["人物变形", "装备变形", "装备特效", "人物背景", "装备背景", "特效物品", "超炫信纸", "浓情贺卡", "Q版请柬"],
	["镶嵌类", "服装类", "特殊类", "消耗类", "护卫类", "千级装备", "初级物资", "礼包类"],
	["全部接合器", "新式接合器", "旧式接合器", "升级材料"],
]
var listing: LegacyShopOfferList
var _balance_label: Label
var _detail_label: RichTextLabel
var _detail_panel: PanelContainer
var _price_label: Label
var _buy_button: Button
var _purchase_dialog: ConfirmationDialog
var _offers: Array[Dictionary] = []
var _visible_offers: Array[Dictionary] = []
var _inventory_revision := -1
var _balance := 0
var _keyword := ""
var _selected_id := ""
var _pending_id := ""
var _pending_quantity := 1
var _quantity: SpinBox
var _subcategory := 0
var subcategories: OptionButton
var empty_label: Label
var search_input: LineEdit
var confirmation: Control
var _category := 0


## 按免费版商城创建分类、物品列表、详情区、搜索及进入确认；商品及余额由权威商城快照提供。
func _ready() -> void:
	build_window(Vector2(720, 502), preload("res://assets/ui/windows/navigation/premium_shop.png"), "")
	theme.default_font_size = SHOP_FONT_SIZE
	get_node("CloseButton").position = Vector2(690, 58)
	for index in range(CATEGORIES.size()):
		make_button(CATEGORIES[index], Rect2(16 + index * 84, 31, 80, 30), _select_category.bind(index))
	subcategories = OptionButton.new()
	subcategories.position = Vector2(24, 82)
	subcategories.size = Vector2(220, 26)
	subcategories.item_selected.connect(_select_subcategory)
	content_root.add_child(subcategories)
	listing = LegacyShopOfferList.new()
	listing.name = "Offers"
	listing.position = Vector2(32, 135)
	listing.size = Vector2(488, 324)
	listing.item_selected.connect(_select_offer)
	content_root.add_child(listing)
	empty_label = make_label("", Rect2(42, 160, 398, 100))
	empty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_balance_label = make_label("紫晶：0", Rect2(500, 38, 175, 26))
	_build_details()
	make_button("刷新", Rect2(600, 82, 75, 26), _refresh_shop)
	make_button("接合器强化", Rect2(354, 82, 136, 26), attachment_upgrade_requested.emit)
	make_button("退出", Rect2(616, 467, 65, 23), request_close)
	_purchase_dialog = ConfirmationDialog.new()
	_purchase_dialog.title = "确认购买"
	_purchase_dialog.ok_button_text = "购买"
	_purchase_dialog.cancel_button_text = "取消"
	_purchase_dialog.confirmed.connect(_confirm_purchase)
	add_child(_purchase_dialog)
	search_input = LineEdit.new()
	search_input.placeholder_text = "搜索商品"
	search_input.position = Vector2(290, 468)
	search_input.size = Vector2(240, 23)
	search_input.text_submitted.connect(_search)
	content_root.add_child(search_input)
	make_button("搜索", Rect2(539, 467, 65, 23), _search_current)
	_build_confirmation()
	_select_category(3)


## 用固定侧栏与纵向容器约束详情、数量和购买按钮，长文本只在详情内部滚动。
func _build_details() -> void:
	_detail_panel = PanelContainer.new()
	_detail_panel.position = Vector2(558, 130)
	_detail_panel.size = Vector2(120, 120)
	_detail_panel.clip_contents = true
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 5
	style.content_margin_right = 5
	style.content_margin_top = 5
	style.content_margin_bottom = 5
	_detail_panel.add_theme_stylebox_override("panel", style)
	content_root.add_child(_detail_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_detail_panel.add_child(column)
	var heading := Label.new()
	heading.text = "商品详情"
	heading.add_theme_color_override("font_color", Color("91d4e4"))
	column.add_child(heading)
	_detail_label = RichTextLabel.new()
	_detail_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail_label.fit_content = false
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.scroll_active = true
	_detail_label.add_theme_font_size_override("normal_font_size", SHOP_FONT_SIZE)
	_detail_label.add_theme_constant_override("line_separation", 3)
	_detail_label.text = "请选择商品"
	column.add_child(_detail_label)
	var purchase_panel := PanelContainer.new()
	purchase_panel.position = Vector2(558, 264)
	purchase_panel.size = Vector2(120, 194)
	purchase_panel.clip_contents = true
	purchase_panel.add_theme_stylebox_override("panel", style)
	content_root.add_child(purchase_panel)
	column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	purchase_panel.add_child(column)
	_price_label = Label.new()
	_price_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_price_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_price_label)
	_quantity = SpinBox.new()
	_quantity.min_value = 1
	_quantity.max_value = 99
	_quantity.value = 1
	_quantity.tooltip_text = "购买数量"
	_quantity.get_line_edit().custom_minimum_size.x = 64
	_quantity.value_changed.connect(_quantity_changed)
	column.add_child(_quantity)
	_buy_button = make_button("购买", Rect2(0, 0, 110, 30), _request_purchase)
	_buy_button.reparent(column)
	_buy_button.custom_minimum_size.y = 30
	_buy_button.disabled = true


## 每次通过底栏打开时显示进入确认，不访问外链或触发付费业务。
func open_shop() -> void:
	_refresh_shop()
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
	confirmation.position = Vector2(210, 155)
	confirmation.size = Vector2(300, 180)
	confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	content_root.add_child(confirmation)
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = "为了保障您角色的安全，建议您在安全的环境下进入游戏商城。\n您确定要进入游戏商城吗？"
	message.position = Vector2(15, 18)
	message.size = Vector2(270, 105)
	confirmation.add_child(message)
	for index in range(2):
		var button := Button.new()
		button.text = ["确定", "取消"][index]
		button.position = Vector2(65 + index * 95, 140)
		button.size = Vector2(75, 24)
		button.pressed.connect(_confirm_entry if index == 0 else request_close)
		confirmation.add_child(button)


## 确认进入商城，展示已登记的接合器商品。
func _confirm_entry() -> void:
	for child: Node in content_root.get_children():
		if child is Control:
			child.show()
	confirmation.hide()
	_render_offers()


## 切换原版商品大类并重建对应子类。
## [param category] 三个原版大类的序号。
func _select_category(category: int) -> void:
	_category = category
	_keyword = ""
	search_input.text = ""
	subcategories.clear()
	for label: String in SUBCATEGORIES[category]:
		subcategories.add_item(label)
	_select_subcategory(0)


## 展示未开放分类的空状态，不伪造售价或数量。
## [param index] 当前大类内的子分类序号。
func _select_subcategory(index: int) -> void:
	_subcategory = index
	subcategories.select(index)
	_render_offers()


## 按权威快照重建商品列表，保持当前选择和筛选条件。
## [param bundle] 含紫晶商城和背包版本的服务端快照。
func apply_shop_bundle(bundle: Dictionary) -> void:
	var shop: Dictionary = bundle.get("premium_shop", {})
	_offers.assign(shop.get("offers", []))
	_balance = int(shop.get("amethyst", 0))
	_inventory_revision = int(bundle.get("inventory", {}).get("revision", -1))
	_balance_label.text = "紫晶：%d" % _balance
	_render_offers()
	if shop.get("operation", {}).get("action", "") == "premium_buy":
		notice_requested.emit("购买成功，商品已放入背包")


## 只发送查询意图，不允许客户端修改余额。
func _refresh_shop() -> void:
	command_requested.emit({"type": "query_premium_shop"})


## 重建当前分类的商品显示及选中详情。
func _render_offers() -> void:
	listing.clear()
	_visible_offers.clear()
	for offer: Dictionary in _offers:
		var is_material: bool = offer.get("family", "") == "upgrade_material"
		var material_tab := (_category == 3 and _subcategory == 3) or (_category == 0 and _subcategory == 2)
		if material_tab != is_material or (not material_tab and _category != 3):
			continue
		if not material_tab and _subcategory == 1 and offer.get("family") != "new_joint":
			continue
		if not material_tab and _subcategory == 2 and offer.get("family") != "old_joint":
			continue
		if not _keyword.is_empty() and not String(offer.get("display_name", "")).contains(_keyword):
			continue
		_visible_offers.append(offer)
		var series := "材料" if is_material else ("新式" if offer.get("family") == "new_joint" else "旧式")
		listing.add_item("[%s] %s    %d 紫晶" % [series, offer.display_name, int(offer.price)])
	empty_label.text = "没有匹配商品" if not _keyword.is_empty() else "当前分类暂无商品"
	empty_label.visible = _visible_offers.is_empty()
	_buy_button.disabled = true
	_detail_label.text = "请选择商品"
	_price_label.text = ""
	_price_label.hide()
	_quantity.hide()
	for index in range(_visible_offers.size()):
		if _visible_offers[index].definition_id == _selected_id:
			listing.select(index)
			_select_offer(index)
			break


## 显示商品用途、类别与价格，同名生命接合器也能区分。
## [param index] 当前可见商品索引。
func _select_offer(index: int) -> void:
	var offer := _visible_offers[index]
	_selected_id = String(offer.definition_id)
	_quantity.set_value_no_signal(1)
	_quantity.visible = offer.family == "upgrade_material"
	_update_detail(offer)
	_detail_label.scroll_to_line(0)


## 在选择购买数量时同步总价与余额检查，报价仍只用于展示。
## [param value] 数量控件的新值。
func _quantity_changed(value: float) -> void:
	if value < 1:
		return
	var selected := listing.get_selected_items()
	if not selected.is_empty():
		_update_detail(_visible_offers[selected[0]])


## 展示材料批量报价或接合器各阶段材料预算。
## [param offer] 服务端下发的商品投影。
func _update_detail(offer: Dictionary) -> void:
	var is_material: bool = offer.family == "upgrade_material"
	var series := "升级材料" if is_material else ("新式" if offer.family == "new_joint" else "旧式")
	var amount := int(_quantity.value) if is_material else 1
	var total := int(offer.price) * amount
	_detail_label.text = "%s\n%s\n\n%s" % [series, offer.display_name, offer.description]
	_price_label.text = "单价：\n%d 紫晶\n合计：\n%d 紫晶" % [int(offer.price), total]
	_price_label.show()
	if not is_material:
		_detail_label.text += "\n同系列最多装备 2 个\n\n升级材料预算："
		for plan: Dictionary in offer.get("upgrade_plans", []):
			_detail_label.text += "\n+%d→+%d：%d 紫晶" % [int(plan.current_level), int(plan.target_level), int(plan.premium_cost)]
		_detail_label.text += "\n点击上方‘接合器强化’可升级自有装备。"
	_buy_button.disabled = _inventory_revision < 0 or _balance < total
	_buy_button.tooltip_text = "紫晶不足" if _balance < total else ""


## 购买前展示具体物品和紫晶金额，确认不会触发真实货币支付。
func _request_purchase() -> void:
	var selected := listing.get_selected_items()
	if selected.is_empty() or _buy_button.disabled:
		return
	var offer := _visible_offers[selected[0]]
	_pending_id = String(offer.definition_id)
	_pending_quantity = int(_quantity.value) if offer.family == "upgrade_material" else 1
	_purchase_dialog.dialog_text = "购买 %s ×%d，花费 %d 紫晶？" % [offer.display_name, _pending_quantity, int(offer.price) * _pending_quantity]
	_purchase_dialog.popup_centered(Vector2i(360, 150))


## 确认后提交商品标识和版本，实际价格由服务器决定。
func _confirm_purchase() -> void:
	if _pending_id.is_empty():
		return
	_buy_button.disabled = true
	command_requested.emit({"type": "buy_premium_item", "definition_id": _pending_id,
		"quantity": _pending_quantity, "inventory_revision": _inventory_revision})
	_pending_id = ""


## 使用输入框的文本筛选当前商品。
func _search_current() -> void:
	_search(search_input.text)


## 搜索公开商品目录，不发送服务器交易请求。
## [param keyword] 商品名称关键词。
func _search(keyword: String) -> void:
	_keyword = keyword.strip_edges()
	_render_offers()
