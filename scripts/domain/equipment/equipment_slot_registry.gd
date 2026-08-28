class_name EquipmentSlotRegistry
extends RefCounted

const VISIBLE_LOCATIONS := {
	0: "底盘",
	1: "主武器",
	2: "防御装置",
	3: "推进装置",
	5: "前装甲",
	6: "后装甲",
	7: "左装甲",
	8: "右装甲",
	13: "战术装置",
	14: "副能源",
	16: "控制装置",
	17: "增幅器",
	18: "能源核心",
}

const DEFINITION_LOCATIONS := {
	"recruit_tank": 0,
	"recruit_energy_cannon": 1,
	"beginner_engine": 3,
}


## 查询定义允许安装的稳定 Location 编号。
## [param definition_id] 装备定义标识。
## 返回 Location；未知定义返回 -1 并由服务端拒绝安装。
static func location_for_definition(definition_id: String) -> int:
	return int(DEFINITION_LOCATIONS.get(definition_id, -1))


## 查询 Location 的中文显示名，同时保留未知扩展槽位。
## [param location] 荣耀客户端 Location 编号。
## 返回适合 UI 展示的槽位名。
static func display_name(location: int) -> String:
	return String(VISIBLE_LOCATIONS.get(location, "扩展槽位 %d" % location))


## 判断给定定义是否允许安装到目标 Location。
## [param definition_id] 装备定义标识。
## [param location] 目标 Location 编号。
## 返回定义映射与目标相符时为 true。
static func accepts(definition_id: String, location: int) -> bool:
	return location_for_definition(definition_id) == location
