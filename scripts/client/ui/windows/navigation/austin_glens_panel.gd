class_name AustinGlensPanel
extends EquipmentProcessingPanel

const LABELS := ["提升品质颜色", "提升成长阶段", "提升基础属性", "提升附加能力", "祝福装备", "开启符文槽", "永久镶入符文"]
var operation_picker: OptionButton
var slot_picker: OptionButton
var selected_slot := 0


## 配置独立奥斯格兰成长窗口，复用已有工坊视觉和原版物品图。
func _init() -> void:
	window_title = "奥斯格兰 · 成长与专属符文"
	window_dimensions = Vector2(940, 720)
	material_title = "专属符文 · 背包"
	hint_text = "阶段、基础和附加最高10级，品质最高紫色。\n加工前先卸装；固定符文镶入后不能摘取。"
	summary_text = "四件独立成长"
	snapshot_key = "austin_glens"
	query_type = "query_austin_glens"
	purchase_type = "buy_austin_glens"
	purchase_title = "奥斯格兰装备与材料 · 星际币（复刻供给）"
	purchase_quantity_limit = 99
	mode = "color"
	execute_type = "change_austin_glens"


## 将列表下移，为成长操作和固定左右槽提供独立选择行。
func _ready() -> void:
	super()
	for child: Node in content_root.get_children():
		if child is Control and child.position.y >= 90: child.position.y += 48
	operation_picker = OptionButton.new()
	operation_picker.position = Vector2(24, 92)
	operation_picker.size = Vector2(300, 34)
	for label: String in LABELS: operation_picker.add_item(label)
	operation_picker.item_selected.connect(_select_mode)
	content_root.add_child(operation_picker)
	slot_picker = OptionButton.new()
	slot_picker.position = Vector2(578, 92)
	slot_picker.size = Vector2(338, 34)
	slot_picker.add_item("左侧专属符文槽")
	slot_picker.add_item("右侧专属符文槽")
	slot_picker.item_selected.connect(_select_slot)
	content_root.add_child(slot_picker)
	confirmation.dialog_autowrap = true
	_update_controls()


## 切换成长方向，只向权威服查询，不提前改变物品。
## [param index] 七种操作之一。
func _select_mode(index: int) -> void:
	if index < 0 or index >= AustinGlensRules.OPERATIONS.size(): return
	operation_picker.select(index)
	mode = AustinGlensRules.OPERATIONS[index]
	_update_controls()
	open_board()


## 只显示开孔或镶入所需的孔位选项。
func _update_controls() -> void:
	slot_picker.visible = mode in ["unlock", "inlay"]
	execute_button.text = LABELS[AustinGlensRules.OPERATIONS.find(mode)]
	confirmation.title = "确认" + execute_button.text


## 提供操作选择，不携带客户端计算的属性和价格。
## 返回纯意图字段。
func _selection_parameters() -> Dictionary:
	return {"mode": mode, "index": selected_slot}


## 固定本次材料消耗和永久符文后果，重复确认不会重新支付。
func _ask() -> void:
	super()
	_pending["confirmed"] = true


## 选择左右固定槽后重新报价。
## [param index] 零基孔位。
func _select_slot(index: int) -> void:
	selected_slot = index
	open_board()
