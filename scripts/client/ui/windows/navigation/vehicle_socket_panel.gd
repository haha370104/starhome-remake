class_name VehicleSocketPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var equipment_list: ItemList
var material_list: ItemList
var details: RichTextLabel
var confirmation: ConfirmationDialog
var use_hammer: CheckBox
var shop: OptionButton
var quantity: SpinBox
var _summary: Label
var _slot_buttons: Array[Button] = []
var _action_buttons: Array[Button] = []
var _equipment: Array = []
var _materials: Array = []
var _offers: Array = []
var _id := ""
var _material_id := ""
var _index := 0
var _revision := -1
var _preview: Dictionary = {}
var _pending: Dictionary = {}


## 创建独立加工窗口，孔位、预览与材料各有固定区域，不叠盖其他窗口。
func _ready() -> void:
	build_modern_window(Vector2(940, 640), "战车装备 · 开槽与晶石")
	_summary = make_label("读取装备与材料…", Rect2(24, 57, 760, 28))
	_style_button(make_button("刷新", Rect2(816, 54, 100, 32), open_board))
	make_label("战车装备 · 已装配 / 背包", Rect2(24, 96, 260, 24))
	make_label("柔解剂与晶石", Rect2(298, 96, 260, 24))
	make_label("孔位与操作预览", Rect2(578, 96, 338, 24))
	equipment_list = _make_list(Rect2(24, 128, 260, 354), _select_equipment)
	material_list = _make_list(Rect2(298, 128, 260, 354), _select_material)
	for index: int in 12:
		var button := make_button(str(index + 1), Rect2(578 + (index % 4) * 85, 128 + floori(index / 4.0) * 40, 80, 34), _select_slot.bind(index))
		button.toggle_mode = true
		_style_button(button)
		_slot_buttons.append(button)
	details = RichTextLabel.new()
	details.position = Vector2(578, 256)
	details.size = Vector2(338, 246)
	details.add_theme_constant_override("line_separation", 4)
	content_root.add_child(details)
	use_hammer = CheckBox.new()
	use_hammer.text = "□ 精密锤摘取（免新增裂纹）"
	use_hammer.position = Vector2(578, 506)
	use_hammer.size = Vector2(338, 28)
	use_hammer.toggled.connect(_toggle_hammer)
	content_root.add_child(use_hammer)
	var actions := ["open_vehicle_socket", "inlay_vehicle_crystal", "extract_vehicle_crystal", "expand_vehicle_sockets"]
	var labels := ["开槽", "镶嵌", "摘取", "解锁扩展孔"]
	for index: int in 4:
		var button := make_button(labels[index], Rect2(578 + (index % 2) * 174, 544 + floori(index / 2.0) * 40, 164, 34), _ask.bind(actions[index]))
		_style_button(button)
		_action_buttons.append(button)
	make_label("加工材料 · 星际币购买", Rect2(24, 496, 520, 24))
	shop = OptionButton.new()
	shop.position = Vector2(24, 534)
	shop.size = Vector2(320, 34)
	shop.clip_text = true
	content_root.add_child(shop)
	quantity = SpinBox.new()
	quantity.position = Vector2(354, 534)
	quantity.size = Vector2(78, 34)
	quantity.min_value = 1
	quantity.max_value = 99
	content_root.add_child(quantity)
	_style_button(make_button("购买", Rect2(442, 534, 116, 34), _ask_purchase))
	var hint := make_label("加工前请先卸下装备。\n普通晶石与人物强化宝石是两套独立系统。", Rect2(24, 582, 532, 42))
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color("87a9bb"))
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认战车加工"
	confirmation.ok_button_text = "确认执行"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(_confirm)
	add_child(confirmation)
	visibility_changed.connect(_visibility_changed)
	_disable_actions()


## 创建统一样式的物品清单。
## [param rect] 位置和尺寸。
## [param selected] 用户选择回调。
## 返回已挂接清单。
func _make_list(rect: Rect2, selected: Callable) -> ItemList:
	var listing := ItemList.new()
	listing.position = rect.position
	listing.size = rect.size
	listing.fixed_icon_size = Vector2i(32, 32)
	listing.add_theme_constant_override("v_separation", 8)
	listing.add_theme_stylebox_override("panel", _surface_style("0b1620", "304b5e"))
	listing.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	listing.item_selected.connect(selected)
	content_root.add_child(listing)
	return listing


## 从已有入口定位装备或晶石，然后查询权威预览。
## [param id] 可选的实例标识。
## [param is_material] 是否属于材料。
func focus_item(id: String = "", is_material: bool = false) -> void:
	if is_material:
		_material_id = id
	else:
		_id = id
	open_board()


## 只查询当前选择，不携带自动存档版本要求。
func open_board() -> void:
	_disable_actions()
	command_requested.emit({"type": "query_vehicle_sockets", "instance_id": _id,
		"material_id": _material_id, "socket_index": _index, "use_hammer": use_hammer.button_pressed})


## 应用同版本快照；背包被其他操作改变时自动重查，旧确认仍受物品版本保护。
## [param bundle] 权威窗口组合数据。
func apply_socket_bundle(bundle: Dictionary) -> void:
	if not bundle.get("vehicle_sockets") is Dictionary:
		if visible and bundle.get("inventory") is Dictionary and _revision != int(bundle.inventory.revision):
			open_board()
		return
	_revision = int(bundle.inventory.revision)
	var snapshot: Dictionary = bundle.vehicle_sockets
	_equipment = snapshot.equipment
	_materials = snapshot.materials
	_offers = snapshot.offers
	_preview = snapshot.preview
	_summary.text = "星际币：%d    ·    同类普通晶石最多四颗有效" % int(snapshot.currency)
	_fill_list(equipment_list, _equipment, _id, true)
	_fill_list(material_list, _materials, _material_id, false)
	var old_shop := shop.selected
	shop.clear()
	for offer: Dictionary in _offers:
		shop.add_item("%s · %d /个" % [offer.display_name, offer.unit_price])
	if old_shop >= 0 and old_shop < shop.item_count:
		shop.select(old_shop)
	_render_slots()
	details.text = String(_preview.get("text", "请选择装备"))
	for index: int in 4:
		_action_buttons[index].disabled = not bool(_preview.get(["can_open", "can_inlay", "can_extract", "can_expand"][index], false))
	var operation: Dictionary = snapshot.operation
	if operation.has("message"):
		notice_requested.emit(String(operation.message))


## 用实例身份恢复选择，消耗完的堆叠不会自动替换成其他材料。
## [param listing] 目标清单。
## [param rows] 权威物品行。
## [param id] 已选身份。
## [param equipment] 是否为装备清单。
func _fill_list(listing: ItemList, rows: Array, id: String, equipment: bool) -> void:
	listing.clear()
	for row: Dictionary in rows:
		var text := String(row.display_name)
		text = ("[已装] " if row.installed else "[背包] ") + text if equipment else text + " ×%d" % int(row.amount)
		listing.add_item(text, ItemPresentationTextureResolver.resolve(row.presentation).get("texture"))
		listing.set_item_tooltip(listing.item_count - 1, text + "\n" + String(row.description))
		if row.instance_id == id:
			listing.select(listing.item_count - 1)


## 以按钮表示十二个候选孔，未解锁孔禁用且不接受意图。
func _render_slots() -> void:
	var slots: Array = []
	for row: Dictionary in _equipment:
		if row.instance_id == _id:
			slots = row.get("socket_views", [])
	for index: int in 12:
		var button := _slot_buttons[index]
		button.disabled = index >= slots.size()
		button.set_pressed_no_signal(index == _index and not button.disabled)
		if button.disabled:
			button.text = "%d 未解锁" % (index + 1)
			button.tooltip_text = "该装备尚未解锁此孔或不具备此孔资格"
		else:
			var slot: Dictionary = slots[index]
			button.text = "%d %s" % [index + 1, "晶石" if not String(slot.name).is_empty() else ("空孔" if slot.opened else "未开")]
			button.tooltip_text = "%s\n裂纹 %d / 3" % [slot.name, int(slot.cracks)] if not String(slot.name).is_empty() else button.text


## 选择装备后重置孔位并查询，不在界面计算概率。
## [param index] 装备行。
func _select_equipment(index: int) -> void:
	_id = String(_equipment[index].instance_id)
	_index = 0
	open_board()


## 选择材料后重新请求可执行预览。
## [param index] 材料行。
func _select_material(index: int) -> void:
	_material_id = String(_materials[index].instance_id)
	open_board()


## 选择孔位并同步所有操作按钮。
## [param index] 从零开始的孔编号。
func _select_slot(index: int) -> void:
	_index = index
	open_board()


## 摘取模式变化后重新查询工具消耗和风险。
## [param _pressed] 更新摘取方式文字的当前勾选状态。
func _toggle_hammer(_pressed: bool) -> void:
	use_hammer.text = ("■" if _pressed else "□") + " 精密锤摘取（免新增裂纹）"
	open_board()


## 捕获当前预览和背包版本，防止确认期间刷新覆盖原意图。
## [param action] 加工动作。
func _ask(action: String) -> void:
	_pending = {"type": action, "instance_id": _id, "material_id": _material_id,
		"socket_index": _index, "inventory_revision": _revision,
		"use_hammer": use_hammer.button_pressed, "risk_confirmed": true}
	confirmation.dialog_text = String(_preview.get("text", ""))
	confirmation.popup_centered(Vector2i(590, 470))


## 捕获商品、数量及版本，购买金额以权威单价展示。
func _ask_purchase() -> void:
	if shop.selected < 0 or shop.selected >= _offers.size():
		return
	var offer: Dictionary = _offers[shop.selected]
	_pending = {"type": "buy_vehicle_workshop_material", "definition_id": offer.definition_id,
		"quantity": int(quantity.value), "inventory_revision": _revision,
		"instance_id": _id, "material_id": _material_id, "socket_index": _index}
	confirmation.dialog_text = "购买 %s ×%d\n合计 %d 星际币" % [offer.display_name, int(quantity.value), int(offer.unit_price) * int(quantity.value)]
	confirmation.popup_centered(Vector2i(520, 240))


## 确认后仅提交一次已捕获意图。
func _confirm() -> void:
	if _pending.is_empty():
		return
	var command := _pending.duplicate(true)
	_pending.clear()
	_disable_actions()
	command_requested.emit(command)


## 等待权威预览期间禁用加工按钮。
func _disable_actions() -> void:
	for button: Button in _action_buttons:
		button.disabled = true


## 关闭窗口同时关闭确认框，避免隐藏窗口遗留确认。
func _visibility_changed() -> void:
	if not visible:
		confirmation.hide()
		_pending.clear()
