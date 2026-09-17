class_name ArmorRefinementPanel
extends QuantityProcessingPanel


## 配置护甲精工的独立意图和快照，复用加工清单、数量与购买控件。
func _init() -> void:
	window_title = "护甲 · 精工"
	window_dimensions = Vector2(940, 670)
	material_title = "芯片 / 对应部位精工石"
	details_title = ""
	hint_text = "芯片 10 个必成，对应部位精工石 4 个必成。\n失败会销毁护甲及其中晶石，请核对预览。"
	summary_text = "护甲精工 · 最高八阶"
	snapshot_key = "armor_refinement"
	query_type = "query_armor_refinement"
	execute_type = "refine_armor"
	purchase_type = "buy_armor_refinement_item"
	purchase_title = "材料 / 基础护甲 · 星际币（复刻商售）"
	material_quantity = 4


## 显示该系统特有的失败销毁确认标题。
func _ready() -> void:
	super()
	confirmation.title = "确认精工：失败将销毁护甲及其中晶石"
	execute_button.text = "护甲精工"


## 用户确认完整预览后提交销毁后果确认标记。
func _ask() -> void:
	super()
	_pending["confirm_destruction"] = true
