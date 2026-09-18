class_name SamaPanel
extends EquipmentProcessingPanel

const LABELS := ["提升成长阶段", "提升品质", "转移成长与品质"]
var operation_picker: OptionButton


## 配置独立撒玛加工窗口，转出来源与保留的目标分别展示。
func _init() -> void:
	window_title = "撒玛 · 成长与品质转移"
	window_dimensions = Vector2(940, 720)
	material_title = "转出来源 · 成功后消失"
	hint_text = "左侧为保留的目标，转移时中间选择转出来源。\n品质不超过阶段；转移覆盖目标阶段及品质。"
	summary_text = "白 / 绿 / 蓝 / 紫阶段上限：1 / 3 / 6 / 10"
	snapshot_key = "sama"
	query_type = "query_sama"
	purchase_type = "buy_sama"
	purchase_title = "撒玛装备与材料 · 星际币（复刻供给）"
	purchase_quantity_limit = 999
	mode = "growth"
	execute_type = "change_sama"


## 复用已有列表布局，并增加独立成长方向选择。
func _ready() -> void:
	super()
	for child: Node in content_root.get_children():
		if child is Control and child.position.y >= 90: child.position.y += 48
	operation_picker = OptionButton.new()
	operation_picker.position = Vector2(24, 92)
	operation_picker.size = Vector2(532, 34)
	for label: String in LABELS: operation_picker.add_item(label)
	operation_picker.item_selected.connect(_select_mode)
	content_root.add_child(operation_picker)
	execute_button.text = LABELS[0]
	confirmation.dialog_autowrap = true


## 切换操作并向服务器重新查询价格，不执行本地成长。
## [param index] 阶段、品质或转移。
func _select_mode(index: int) -> void:
	if index < 0 or index >= SamaRules.OPERATIONS.size(): return
	operation_picker.select(index)
	mode = SamaRules.OPERATIONS[index]
	execute_button.text = LABELS[index]
	confirmation.title = "确认" + LABELS[index]
	open_board()


## 捕获本次消耗、覆盖和来源销毁确认，提交后清空请求。
func _ask() -> void:
	super()
	_pending["confirmed"] = true
