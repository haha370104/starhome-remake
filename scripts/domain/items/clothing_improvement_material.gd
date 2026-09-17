class_name ClothingImprovementMaterial
extends GameItem

var improvement_attribute: String


## 将仿生纤维构造成单一改良方向的材料。
## [param definition] 受控目录定义。
## [param state] 实例数量、绑定等事实。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	improvement_attribute = String(definition.get("improvement_attribute", ""))
