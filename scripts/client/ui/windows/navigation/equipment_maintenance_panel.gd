class_name EquipmentMaintenancePanel
extends EquipmentProcessingPanel

var mode_selector: OptionButton
var shop: OptionButton
var quantity: SpinBox
var _offers: Array = []


## 复用装备与材料选择界面，维护规则和命令仍由独立服务处理。
func _init() -> void:
	window_title = "装备 · 常规维护与速修"
	window_dimensions = Vector2(940, 670)
	material_title = "速修箱 · 背包"
	details_title = ""
	hint_text = "常规维护：背包装备，返回基地或生产区。\n电磁/光导箱修已装配装备，离子箱修背包装备。"
	summary_text = "维护前请核对耐久上限变化"
	snapshot_key = "equipment_maintenance"
	query_type = "query_equipment_maintenance"
	execute_type = "maintain_equipment"


## 在稳定的选择与确认组件上增加维护模式和工具购买。
func _ready() -> void:
	super()
	mode_selector = OptionButton.new()
	mode_selector.position = Vector2(578, 90)
	mode_selector.size = Vector2(338, 32)
	mode_selector.add_item("常规维护 / 服装修补")
	mode_selector.add_item("使用速修箱")
	mode_selector.item_selected.connect(_select_mode)
	content_root.add_child(mode_selector)
	execute_button.text = "执行维护"
	confirmation.title = "确认装备维护"
	make_label("速修工具 · 星际币", Rect2(24, 580, 400, 24))
	shop = OptionButton.new()
	shop.position = Vector2(24, 612)
	shop.size = Vector2(390, 34)
	shop.clip_text = true
	content_root.add_child(shop)
	quantity = SpinBox.new()
	quantity.position = Vector2(426, 612)
	quantity.size = Vector2(120, 34)
	quantity.min_value = 1
	quantity.max_value = 99
	content_root.add_child(quantity)
	_style_button(make_button("购买工具", Rect2(578, 612, 338, 34), _ask_purchase))


## 从工具右键进入时直接选择速修模式，仍需用户明确选择目标。
## [param id] 初始装备或工具实例。
## [param is_material] 是否为速修工具。
func focus_item(id: String = "", is_material: bool = false) -> void:
	if is_material:
		mode_selector.select(1)
		mode = "quick"
		execute_type = "quick_repair_equipment"
		execute_button.text = "使用速修箱"
	super(id, is_material)


## 接收独立维护快照并保持商品选择，其他装备窗口的消息只触发必要刷新。
## [param bundle] 同版本面板数据。
func apply_maintenance_bundle(bundle: Dictionary) -> void:
	apply_processing_bundle(bundle)
	if not bundle.get(snapshot_key) is Dictionary:
		return
	_offers = bundle[snapshot_key].offers
	var selected := shop.selected
	shop.clear()
	for offer: Dictionary in _offers:
		shop.add_item("%s · %d /个" % [offer.display_name, offer.unit_price])
	if selected >= 0 and selected < shop.item_count:
		shop.select(selected)


## 切换维护方式只改变意图，恢复数值由服务器预览。
## [param index] 用户选择的模式。
func _select_mode(index: int) -> void:
	mode = "regular" if index == 0 else "quick"
	execute_type = "maintain_equipment" if index == 0 else "quick_repair_equipment"
	execute_button.text = "执行维护" if index == 0 else "使用速修箱"
	open_board()


## 对购买数量和服务端单价进行明确确认，防止连点多次购买。
func _ask_purchase() -> void:
	if shop.selected < 0 or shop.selected >= _offers.size():
		return
	var offer: Dictionary = _offers[shop.selected]
	_pending = {"type": "buy_maintenance_tool", "definition_id": offer.definition_id, "quantity": int(quantity.value),
		"inventory_revision": _revision, "instance_id": _id, "material_id": _material_id, "mode": mode}
	confirmation.dialog_text = "购买 %s ×%d\n合计 %d 星际币" % [offer.display_name, int(quantity.value), int(offer.unit_price) * int(quantity.value)]
	confirmation.popup_centered(Vector2i(520, 240))
