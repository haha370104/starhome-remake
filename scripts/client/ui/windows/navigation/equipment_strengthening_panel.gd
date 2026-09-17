class_name EquipmentStrengtheningPanel
extends EquipmentProcessingPanel

var stone_quantity: SpinBox


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


## 使用原规则允许的可变投入量，并在变化后查询权威成功率。
func _ready() -> void:
	super()
	confirmation.title = "确认装备星级强化"
	make_label("本次使用颗数", Rect2(578, 91, 160, 28))
	stone_quantity = SpinBox.new()
	stone_quantity.position = Vector2(748, 89)
	stone_quantity.size = Vector2(168, 34)
	stone_quantity.min_value = 1
	stone_quantity.max_value = 99
	stone_quantity.value = material_quantity
	stone_quantity.value_changed.connect(_change_quantity)
	content_root.add_child(stone_quantity)


## 只提交投入数量，概率和结果完全使用服务器返回值。
## [param value] 玩家选择的强化石颗数。
func _change_quantity(value: float) -> void:
	material_quantity = int(value)
	open_board()
