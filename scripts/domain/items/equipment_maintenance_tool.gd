class_name EquipmentMaintenanceTool
extends GameItem

var scope: String = ""
var repair_kind: String = ""
var amount: int = 0


## 赋予速修工具明确类型与作用范围，背包菜单不按名称猜测用途。
## [param definition] 目录确认的工具定义。
## [param state] 物品实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	scope = String(definition.get("maintenance_tool", {}).get("scope", ""))
	repair_kind = String(definition.get("maintenance_tool", {}).get("kind", ""))
	amount = int(definition.get("maintenance_tool", {}).get("amount", 0))
