class_name EquipmentMemoryPanel
extends EquipmentProcessingPanel

var mode_selector: OptionButton
var stabilizer: CheckButton


## 配置记忆模块的独立操作意图，复用清单、预览与购买。
func _init() -> void:
	window_title = "装备 · 记忆模块"
	window_dimensions = Vector2(940, 670)
	material_title = "空白 / 已载入模块"
	details_title = ""
	hint_text = "提取先选源装备，转移先选同类目标装备。\n稳压剂一次一份；操作前核对模块消耗后果。"
	summary_text = "分类型移动成长 · 原装备保留"
	snapshot_key = "equipment_memory"
	query_type = "query_equipment_memory"
	execute_type = "process_equipment_memory"
	purchase_type = "buy_equipment_memory_item"
	purchase_title = "记忆模块 / 电磁稳压剂 · 原版单价20星际币（复刻商售）"
	mode = "extract"


## 创建提取转移选择和保证成功的可选材料开关。
func _ready() -> void:
	super()
	mode_selector = OptionButton.new()
	mode_selector.position = Vector2(578, 90)
	mode_selector.size = Vector2(162, 32)
	mode_selector.add_item("提取到空模块")
	mode_selector.add_item("转移到装备")
	mode_selector.item_selected.connect(_select_mode)
	content_root.add_child(mode_selector)
	stabilizer = CheckButton.new()
	stabilizer.text = "使用稳压剂"
	stabilizer.position = Vector2(752, 90)
	stabilizer.size = Vector2(164, 32)
	stabilizer.toggled.connect(_toggle_stabilizer)
	content_root.add_child(stabilizer)
	execute_button.text = "执行提取 / 转移"
	confirmation.title = "确认成长去向和模块消耗"


## 固定操作模式与稳压剂选择，确认后不能被后续控件变化替换。
## 返回当前选择参数。
func _selection_parameters() -> Dictionary:
	var selection := super()
	selection["use_stabilizer"] = stabilizer != null and stabilizer.button_pressed
	return selection


## 用户看过完整失败说明后提交一次性确认标记。
func _ask() -> void:
	super()
	_pending["confirm_transfer"] = true


## 切换提取或转移并重新查询兼容性。
## [param index] 两种模式的索引。
func _select_mode(index: int) -> void:
	mode = "extract" if index == 0 else "transfer"
	open_board()


## 变更可选稳压剂后重新计算权威费用与概率。
## [param _enabled] 控件当前选择；命令从控件读取稳定状态。
func _toggle_stabilizer(_enabled: bool) -> void:
	open_board()
