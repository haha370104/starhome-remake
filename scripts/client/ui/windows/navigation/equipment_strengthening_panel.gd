class_name EquipmentStrengtheningPanel
extends QuantityProcessingPanel


## 在统一加工布局内展示十星强化，保持接合器、萤石和普通加工各自独立。
func _init() -> void:
	window_title = "装备 · 十星强化"
	window_dimensions = Vector2(940, 670)
	material_title = "强化石 · 背包"
	details_title = ""
	hint_text = "普通强化 4 颗必成，第十星 9 颗必成。\n使用更少颗数时，失败可能降低星级。"
	summary_text = "独立星级 · 最高十星"
	snapshot_key = "equipment_strengthening"
	query_type = "query_equipment_strengthening"
	execute_type = "strengthen_equipment"
	purchase_type = "buy_equipment_strengthening_material"
	purchase_title = "强化材料 · 星际币（复刻定价）"
	material_quantity = 4


## 设置本加工系统的确认标题。
func _ready() -> void:
	super()
	confirmation.title = "确认装备星级强化"
