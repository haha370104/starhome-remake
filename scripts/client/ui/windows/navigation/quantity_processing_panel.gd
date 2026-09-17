class_name QuantityProcessingPanel
extends EquipmentProcessingPanel

var stone_quantity: SpinBox
var material_quantity_limit := 99
var quantity_label := "本次使用颗数"


## 使用原规则允许的可变投入量，并在变化后查询权威成功率。
func _ready() -> void:
	super()
	make_label(quantity_label, Rect2(578, 91, 160, 28))
	stone_quantity = SpinBox.new()
	stone_quantity.position = Vector2(748, 89)
	stone_quantity.size = Vector2(168, 34)
	stone_quantity.min_value = 1
	stone_quantity.max_value = material_quantity_limit
	stone_quantity.value = material_quantity
	stone_quantity.value_changed.connect(_change_quantity)
	content_root.add_child(stone_quantity)


## 只提交投入数量，概率和结果完全使用服务器返回值。
## [param value] 玩家选择的强化石颗数。
func _change_quantity(value: float) -> void:
	material_quantity = int(value)
	open_board()
