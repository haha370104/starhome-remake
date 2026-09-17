class_name EquipmentForgingPanel
extends QuantityProcessingPanel


## 配置锻造窗口，投入量严格遵循原版一至三枚芯片。
func _init() -> void:
	window_title = "装备 · 锻造扩展"
	window_dimensions = Vector2(940, 670)
	material_title = "锻造芯片 · 背包"
	details_title = ""
	hint_text = "锻造会清除全部普通加工，可先用记忆模块保留。\n其他成长不变；多数芯片只扩展加工上限。"
	summary_text = "1 / 2 / 3枚芯片：25% / 60% / 95%"
	snapshot_key = "equipment_forging"
	query_type = "query_equipment_forging"
	execute_type = "forge_equipment"
	purchase_type = "buy_equipment_forging_material"
	purchase_title = "锻造芯片和补充合金 · 星际币"
	material_quantity = 3
	material_quantity_limit = 3
	purchase_quantity_limit = 999
	quantity_label = "本次投入芯片"


## 显式提示加工清除风险，长说明保持在确认框内。
func _ready() -> void:
	super()
	execute_button.text = "执行锻造"
	confirmation.title = "确认锻造：普通加工值将清除"
	confirmation.dialog_autowrap = true


## 在用户确认时提交风险确认，预览本身不执行。
func _ask() -> void:
	super()
	_pending["confirm_processing_loss"] = true
