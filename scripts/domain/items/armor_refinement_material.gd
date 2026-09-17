class_name ArmorRefinementMaterial
extends GameItem

var refinement_location: int


## 区分通用芯片与四种部位精工石，界面和聚合不读取原客户端字段。
## [param definition] 已验证的物品定义。
## [param state] 堆叠实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	refinement_location = int(definition.get("refinement_location", 0))
