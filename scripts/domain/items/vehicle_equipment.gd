class_name VehicleEquipment
extends Equipment

var equipment_location: int
var equip_kind: int
var weight: int
var _device_kind: String


## 初始化安装到战车固定 Location 的装备实例。
## [param definition] 战车装备定义。
## [param state] 存档中的装备实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	equipment_location = int(definition.get("equipment_location", -1))
	equip_kind = int(definition.get("equip_kind", -1))
	_device_kind = String(definition.get("kind", ""))
	weight = maxi(0, int(stat("weight", 0)))


## 判断装备是否接受指定的战车 Location。
## [param location] 荣耀客户端稳定槽位编号。
## 返回目标与定义 Location 一致时为 true。
func accepts_location(location: int) -> bool:
	return equipment_location == location


## 查询主装置的业务类型，供 HUD 和输入路由共享，避免各处解释旧客户端字段。
## 返回能量炮、采掘臂、维修臂的语义标识；非主装置或未知类型返回空字符串。
func primary_device_kind() -> String:
	if equipment_location != 1:
		return ""
	match _device_kind:
		"mining_arm", "repair_arm":
			return _device_kind
		"energy_cannon", "vehicle_weapon":
			return "energy_cannon"
	return ""


## 导出带固定 Location 的战车装备视图。
## 返回通用装备 DTO 加战车槽位信息。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["equipment_location"] = equipment_location
	view["location"] = equipment_location
	view["equip_kind"] = equip_kind
	return view
