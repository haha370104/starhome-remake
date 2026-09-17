class_name ClothingImprovementPanel
extends QuantityProcessingPanel


## 为原版单方向纤维改良配置独立窗口，支持跨堆叠大批投入。
func _init() -> void:
	window_title = "季节时装 · 仿生纤维改良"
	window_dimensions = Vector2(940, 670)
	material_title = "七类仿生纤维"
	details_title = ""
	hint_text = "首次成功确定改良方向，每五级所需纤维翻倍。\n与前缀、特性、宝石分别保存，共同生效。"
	summary_text = "独立改良 · 最高100级"
	snapshot_key = "clothing_improvement"
	query_type = "query_clothing_improvement"
	execute_type = "improve_clothing"
	purchase_type = "buy_clothing_improvement_item"
	purchase_title = "纤维 / 季节时装 · 星际币（复刻商售）"
	material_quantity = 2
	material_quantity_limit = 1048576
	purchase_quantity_limit = 9999
	quantity_label = "本次投入纤维"


## 显示服装改良的确认和执行标题。
func _ready() -> void:
	super()
	confirmation.title = "确认服装改良"
	execute_button.text = "改良时装"
