class_name ExtraAttributePanel
extends EquipmentProcessingPanel


## 复用装备、材料、结果和购买组件，额外属性保持独立服务与状态。
func _init() -> void:
	window_title = "装备 · 萤石与耀石加工"
	window_dimensions = Vector2(940, 670)
	material_title = "萤石 / 耀石 · 背包"
	hint_text = "先卸下待加工装备，再选择对应材料。\n各属性独立计数；成功率和失败退级请见右侧。"
	summary_text = "原版额外属性 · 地面装备"
	snapshot_key = "extra_attributes"
	query_type = "query_extra_attributes"
	execute_type = "process_extra_attribute"
	purchase_type = "buy_extra_attribute_material"
	purchase_title = "材料购买 · 萤石 2 万 / 耀石 5 万星际币（复刻定价）"


## 为确认框设置正确的加工名称。
func _ready() -> void:
	super()
	confirmation.title = "确认萤石 / 耀石加工"
