class_name ExtraAttributeMaterial
extends GameItem

var channel_id: String


## 将萤石或耀石的通道身份交给界面，具体资格由装备成长模型校验。
## [param definition] 目录组装的材料定义。
## [param state] 堆叠事实。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	channel_id = String(definition.get("extra_attribute_channel", ""))
