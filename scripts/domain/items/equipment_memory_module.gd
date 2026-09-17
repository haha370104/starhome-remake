class_name EquipmentMemoryModule
extends GameItem

var module_type: int
var memory := EquipmentMemory.new()


## 构造不可堆叠的记忆模块，空载或携带一种独立成长。
## [param definition] 模块种类与原版表现。
## [param state] 实例身份、绑定及记忆事实。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	module_type = int(definition.get("module_type", 0))
	var restored := EquipmentMemory.restore(state.get("equipment_memory", {}))
	if restored.is_ok: memory = restored.value


## 将记忆事实和模块类型投影给背包及加工窗口。
## 返回安全物品快照。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["display_name"] = ("[已载入] " if memory.has_growth() else "[空白] ") + display_name
	if memory.has_growth(): view["description"] = description + "\n已保存装备成长；右键进入记忆模块窗口查看来源和具体数值。"
	view["module_type"] = module_type
	view["equipment_memory"] = memory.to_dictionary()
	return view
