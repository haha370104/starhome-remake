class_name EquipmentProcessingMaterial
extends GameItem

var attribute: String = ""
var points: int = 0


## 将经目录确认的加工材料赋予明确类型，界面不按中文名称猜用途。
## [param definition] 包含加工规则的只读物品定义。
## [param state] 物品实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	attribute = String(definition.get("processing_material", {}).get("attribute", ""))
	points = int(definition.get("processing_material", {}).get("points", 0))
