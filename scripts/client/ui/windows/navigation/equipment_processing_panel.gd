class_name EquipmentProcessingPanel
extends ModernNavigationWindow

signal command_requested(command: Dictionary)

var equipment_list: ItemList
var material_list: ItemList
var details: RichTextLabel
var confirmation: ConfirmationDialog
var execute_button: Button
var _summary: Label
var _equipment: Array = []
var _materials: Array = []
var _id := ""
var _material_id := ""
var _revision := -1
var _preview: Dictionary = {}
var _pending: Dictionary = {}


## 构建与晶石窗口独立的基础加工界面，材料和结果始终限制在各自区域。
func _ready() -> void:
	build_modern_window(Vector2(940, 600), "普通装备 · 基础属性加工")
	_summary = make_label("读取装备…", Rect2(24, 57, 740, 28))
	_style_button(make_button("刷新", Rect2(816, 54, 100, 32), open_board))
	make_label("装备 · 已装配 / 背包", Rect2(24, 96, 260, 24))
	make_label("加工道具", Rect2(298, 96, 260, 24))
	make_label("属性、消耗与结果", Rect2(578, 96, 338, 24))
	equipment_list = _make_list(Rect2(24, 128, 260, 374), _select_equipment)
	material_list = _make_list(Rect2(298, 128, 260, 374), _select_material)
	details = RichTextLabel.new()
	details.position = Vector2(578, 128)
	details.size = Vector2(338, 374)
	details.add_theme_constant_override("line_separation", 5)
	content_root.add_child(details)
	var hint := make_label("先卸下待加工装备，再选择对应道具。\n硬质素和复合胶板可在提炼设施生产。", Rect2(24, 528, 532, 44))
	hint.add_theme_color_override("font_color", Color("87a9bb"))
	execute_button = make_button("执行加工", Rect2(578, 528, 338, 40), _ask)
	_style_button(execute_button)
	execute_button.disabled = true
	confirmation = ConfirmationDialog.new()
	confirmation.title = "确认基础加工"
	confirmation.ok_button_text = "确认执行"
	confirmation.cancel_button_text = "取消"
	confirmation.confirmed.connect(_confirm)
	add_child(confirmation)
	visibility_changed.connect(_visibility_changed)


## 创建带原版物品图和统一字体的清单。
## [param rect] 清单区域。
## [param selected] 选择回调。
## 返回已安装的清单。
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


## 从背包菜单定位装备或道具。
## [param id] 可选实例。
## [param is_material] 是否选择材料。
func focus_item(id: String = "", is_material: bool = false) -> void:
	if is_material:
		_material_id = id
	else:
		_id = id
	open_board()


## 查询当前选择的权威预览，不要求自动存档版本保持不变。
func open_board() -> void:
	execute_button.disabled = true
	command_requested.emit({"type": "query_equipment_processing", "instance_id": _id, "material_id": _material_id})


## 用服务端快照更新材料数量、可执行性与操作说明。
## [param bundle] 同事务面板快照。
func apply_processing_bundle(bundle: Dictionary) -> void:
	if not bundle.get("equipment_processing") is Dictionary:
		if visible and bundle.get("inventory") is Dictionary and _revision != int(bundle.inventory.revision):
			open_board()
		return
	_revision = int(bundle.inventory.revision)
	var snapshot: Dictionary = bundle.equipment_processing
	_equipment = snapshot.equipment
	_materials = snapshot.materials
	_preview = snapshot.preview
	_summary.text = "星际币：%d    ·    各属性独立加工至原版上限" % int(snapshot.currency)
	_fill_list(equipment_list, _equipment, _id, true)
	_fill_list(material_list, _materials, _material_id, false)
	var summary := ""
	for row: Dictionary in _equipment:
		if row.instance_id == _id:
			summary = String(row.display_name) + "\n" + String(row.attribute_summary) + "\n\n"
	details.text = summary + String(_preview.get("text", "请选择装备与加工材料"))
	execute_button.disabled = not bool(_preview.get("can_execute", false))
	if snapshot.operation.has("message"):
		notice_requested.emit(String(snapshot.operation.message))


## 按实例恢复选择，堆叠用完后不擅自选择其他材料。
## [param listing] 清单。
## [param rows] 权威数据。
## [param id] 已选实例。
## [param equipment] 是否是装备清单。
func _fill_list(listing: ItemList, rows: Array, id: String, equipment: bool) -> void:
	listing.clear()
	for row: Dictionary in rows:
		var text := String(row.display_name)
		text = ("[已装] " if row.installed else "[背包] ") + text if equipment else text + " ×%d" % int(row.amount)
		listing.add_item(text, ItemPresentationTextureResolver.resolve(row.presentation).get("texture"))
		listing.set_item_tooltip(listing.item_count - 1, text + "\n" + String(row.get("attribute_summary", row.description)))
		if row.instance_id == id:
			listing.select(listing.item_count - 1)


## 选择装备后重新查询。
## [param index] 装备行。
func _select_equipment(index: int) -> void:
	_id = String(_equipment[index].instance_id)
	open_board()


## 选择加工材料后重新查询。
## [param index] 材料行。
func _select_material(index: int) -> void:
	_material_id = String(_materials[index].instance_id)
	open_board()


## 固定本次预览与版本，确认期间的刷新不会替换用户选择。
func _ask() -> void:
	_pending = {"type": "process_equipment_attribute", "instance_id": _id,
		"material_id": _material_id, "inventory_revision": _revision}
	confirmation.dialog_text = String(_preview.get("text", ""))
	confirmation.popup_centered(Vector2i(580, 420))


## 确认时仅提交一次已捕获意图。
func _confirm() -> void:
	if _pending.is_empty():
		return
	var command := _pending.duplicate(true)
	_pending.clear()
	execute_button.disabled = true
	command_requested.emit(command)


## 关闭窗口时清除尚未提交的确认。
func _visibility_changed() -> void:
	if not visible:
		confirmation.hide()
		_pending.clear()
