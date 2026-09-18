class_name EquipmentWorkshopNavigation
extends RefCounted

const PROJECTS := {
	"crystal_source": "晶源体 / 晶源核",
	"equipment_processing": "基础属性加工",
	"equipment_maintenance": "耐久维护 / 补弹",
	"extra_attributes": "萤石 / 耀石加工",
	"equipment_strengthening": "装备十星强化",
	"armor_refinement": "护甲精工",
	"clothing_improvement": "季节时装改良",
	"equipment_memory": "记忆模块 / 成长转移",
	"equipment_forging": "锻造 / 扩展上限",
	"equipment_dismantle": "拆解装备",
}


## 将独立装备加工窗口置前并定位物品，只复用窗口交互，不混合各系统的规则。
## [param window] 已注册且支持 focus_item 的加工窗口。
## [param viewport_size] 窗口管理层可见尺寸。
## [param id] 待定位实例。
## [param is_material] 是否为材料。
static func focus(window: NavigationWindow, viewport_size: Vector2, id: String, is_material: bool) -> void:
	window.show()
	window.move_to_front()
	window.clamp_to_viewport(viewport_size)
	window.call("focus_item", id, is_material)
