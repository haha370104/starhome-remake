class_name CrystalSourcePanel
extends EquipmentProcessingPanel

const MODES := ["quality", "growth", "inlay", "extract", "compose"]
const LABELS := ["提升品质", "提升成长", "镶嵌晶源核", "摘取晶源核", "晶源核五合一"]
var operation_picker: OptionButton
var slot_picker: OptionButton
var protection: CheckBox
var stabilizer_count: SpinBox
var stabilizer_label: Label
var selected_slot := 0
var stabilizers := 0
var protected := false


## 配置独立晶源体窗口，复用统一字体、物品图和加工项目导航。
func _init() -> void:
	window_title = "晶源体 · 成长与晶源核"
	window_dimensions = Vector2(940, 720)
	material_title = "晶源核 · 背包"
	hint_text = "品质、成长各最高15级；晶源核最高5级。\n装备综合等级要求400；加工前请先卸装。"
	summary_text = "晶源体独立成长"
	snapshot_key = "crystal_source"
	query_type = "query_crystal_source"
	purchase_type = "buy_crystal_source"
	purchase_title = "晶源体与基础材料 · 星际币（复刻定价）"
	purchase_quantity_limit = 999
	mode = "quality"
	execute_type = "grow_crystal_source"


## 在共用列表上方增加操作行，原有详情和购买栏整体下移，保持窗口边界。
func _ready() -> void:
	super()
	for child: Node in content_root.get_children():
		if child is Control and child.position.y >= 90: child.position.y += 48
	operation_picker = OptionButton.new()
	operation_picker.position = Vector2(24, 92)
	operation_picker.size = Vector2(260, 34)
	for label: String in LABELS: operation_picker.add_item(label)
	operation_picker.item_selected.connect(_select_mode)
	content_root.add_child(operation_picker)
	protection = CheckBox.new()
	protection.text = "使用水晶稳定剂（防品质退级）"
	protection.position = Vector2(298, 92)
	protection.size = Vector2(440, 34)
	protection.toggled.connect(_toggle_protection)
	content_root.add_child(protection)
	slot_picker = OptionButton.new()
	slot_picker.position = Vector2(578, 92)
	slot_picker.size = Vector2(338, 34)
	for index in 3: slot_picker.add_item("选择晶源核槽 %d" % (index + 1))
	slot_picker.item_selected.connect(_select_slot)
	content_root.add_child(slot_picker)
	stabilizer_label = make_label("晶源核稳定剂数量", Rect2(298, 94, 240, 30))
	stabilizer_count = SpinBox.new()
	stabilizer_count.position = Vector2(578, 92)
	stabilizer_count.size = Vector2(160, 34)
	stabilizer_count.min_value = 0
	stabilizer_count.max_value = 7
	stabilizer_count.value_changed.connect(_change_stabilizers)
	content_root.add_child(stabilizer_count)
	confirmation.dialog_autowrap = true
	_update_controls()


## 根据操作切换明确的服务端命令，切换本身只查询。
## [param index] 五个操作之一。
func _select_mode(index: int) -> void:
	if index < 0 or index >= MODES.size(): return
	operation_picker.select(index)
	mode = MODES[index]
	execute_type = "grow_crystal_source" if index < 2 else ["inlay_crystal_source", "extract_crystal_source", "compose_crystal_source"][index - 2]
	_update_controls()
	open_board()


## 显示当前操作需要的选项，不让隐藏选项参与其他系统。
func _update_controls() -> void:
	protection.visible = mode == "quality"
	slot_picker.visible = mode in ["inlay", "extract"]
	stabilizer_count.visible = mode == "compose"
	stabilizer_label.visible = mode == "compose"
	execute_button.text = LABELS[MODES.find(mode)]
	confirmation.title = "确认" + execute_button.text


## 提交当前模式、孔位和可选保护，服务器自己计算结果。
## 返回查询与确认共用的纯意图。
func _selection_parameters() -> Dictionary:
	return {"mode": mode, "index": selected_slot, "stabilizers": stabilizers if mode == "compose" else 0, "protected": protected if mode == "quality" else false}


## 固定本次风险和费用，确认期间的刷新不改变待执行意图。
func _ask() -> void:
	super()
	_pending["confirmed"] = true


## 更新品质退级保护后重新报价。
## [param enabled] 当前勾选状态。
func _toggle_protection(enabled: bool) -> void:
	protected = enabled
	open_board()


## 选择独立核心孔，避免操作普通装备孔位。
## [param index] 三个核心槽的序号。
func _select_slot(index: int) -> void:
	selected_slot = index
	open_board()


## 使用权威规则重新计算核心合成成功率。
## [param value] 稳定剂数量。
func _change_stabilizers(value: float) -> void:
	stabilizers = int(value)
	open_board()
