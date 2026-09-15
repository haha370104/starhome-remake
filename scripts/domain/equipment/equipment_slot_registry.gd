class_name EquipmentSlotRegistry
extends RefCounted

const LOCATION_DEFINITIONS := {
	0: {"slot_id": "chassis", "name": "车体", "display_slot_id": -1},
	1: {"slot_id": "primary_weapon", "name": "主武器", "display_slot_id": -1},
	2: {"slot_id": "defense", "name": "防护装置", "display_slot_id": -1},
	3: {"slot_id": "propulsion", "name": "推进器", "display_slot_id": 6},
	5: {"slot_id": "front_armor", "name": "前护甲", "display_slot_id": 0},
	6: {"slot_id": "rear_armor", "name": "后护甲", "display_slot_id": 9},
	7: {"slot_id": "left_armor", "name": "左护甲", "display_slot_id": 7},
	8: {"slot_id": "right_armor", "name": "右护甲", "display_slot_id": 8},
	13: {"slot_id": "tactical", "name": "战术设备", "display_slot_id": 1},
	14: {"slot_id": "generator", "name": "发生器 / 副炮", "display_slot_id": 4},
	16: {"slot_id": "extension_a", "name": "旧式接合器 I", "display_slot_id": 2},
	17: {"slot_id": "extension_b", "name": "旧式接合器 II", "display_slot_id": 3},
	32: {"slot_id": "new_joint_a", "name": "新式接合器 I", "display_slot_id": 10},
	33: {"slot_id": "new_joint_b", "name": "新式接合器 II", "display_slot_id": 11},
	34: {"slot_id": "generator_b", "name": "发生器 II", "display_slot_id": 12},
	18: {"slot_id": "macro_atom", "name": "宏原子", "display_slot_id": 5},
	19: {"slot_id": "sama_condenser", "name": "撒玛聚能器", "display_slot_id": -1,
		"series": "sama", "special_row": 0},
	20: {"slot_id": "sama_pulser", "name": "撒玛脉冲器", "display_slot_id": -1,
		"series": "sama", "special_row": 1},
	21: {"slot_id": "sama_reactor", "name": "撒玛核变器", "display_slot_id": -1,
		"series": "sama", "special_row": 2},
	22: {"slot_id": "sama_turbulator", "name": "撒玛扰流器", "display_slot_id": -1,
		"series": "sama", "special_row": 3},
	23: {"slot_id": "force_field_armor", "name": "防御力场装甲", "display_slot_id": -1},
	24: {"slot_id": "austin_glory", "name": "奥斯格兰的光辉", "display_slot_id": -1,
		"series": "austin_glens", "special_row": 0},
	25: {"slot_id": "austin_honor", "name": "奥斯格兰的荣耀", "display_slot_id": -1,
		"series": "austin_glens", "special_row": 1},
	26: {"slot_id": "austin_evolution", "name": "奥斯格兰的进化", "display_slot_id": -1,
		"series": "austin_glens", "special_row": 2},
	27: {"slot_id": "austin_legacy", "name": "奥斯格兰的传承", "display_slot_id": -1,
		"series": "austin_glens", "special_row": 3},
	28: {"slot_id": "crystal_mountain", "name": "晶源体—山", "display_slot_id": -1,
		"series": "crystal", "special_row": 0},
	29: {"slot_id": "crystal_power", "name": "晶源体—力", "display_slot_id": -1,
		"series": "crystal", "special_row": 1},
	30: {"slot_id": "crystal_fire", "name": "晶源体—火", "display_slot_id": -1,
		"series": "crystal", "special_row": 2},
	31: {"slot_id": "crystal_speed", "name": "晶源体—疾", "display_slot_id": -1,
		"series": "crystal", "special_row": 3},
}

const DEFINITION_LOCATIONS := {
	"recruit_tank": 0,
	"recruit_energy_cannon": 1,
	"beginner_engine": 3,
	"starter_rocket_launcher": 13,
	"starter_missile": 13,
}

const DIALOG_ANCHORS := {
	0: Vector2i(170, 200),
	1: Vector2i(170, 200),
	3: Vector2i(130, 385),
	5: Vector2i(50, 80),
	6: Vector2i(330, 385),
	7: Vector2i(210, 385),
	8: Vector2i(270, 385),
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
	var definition: Dictionary = LOCATION_DEFINITIONS.get(location, {})
	return String(definition.get("name", "扩展槽位 %d" % location))


## 查询持久化与网络边界使用的稳定槽位标识。
## [param location] 荣耀客户端 Location 编号。
## 返回业务槽位标识；未知位置保留 extension_N 形式。
static func slot_id(location: int) -> String:
	var definition: Dictionary = LOCATION_DEFINITIONS.get(location, {})
	return String(definition.get("slot_id", "extension_%d" % location))


## 查询逻辑 Location 所属的十四格视觉编号。
## [param location] 荣耀客户端 Location 编号。
## 返回 0..13；中央预览或补丁槽返回 -1。
static func display_slot_id(location: int) -> int:
	var definition: Dictionary = LOCATION_DEFINITIONS.get(location, {})
	return int(definition.get("display_slot_id", -1))


## 查询右侧特殊装备系列。
## [param location] 荣耀客户端 Location 编号。
## 返回 sama、austin_glens、crystal；普通装备返回空字符串。
static func special_series(location: int) -> String:
	var definition: Dictionary = LOCATION_DEFINITIONS.get(location, {})
	return String(definition.get("series", ""))


## 查询右侧特殊装备视觉行。
## [param location] 荣耀客户端 Location 编号。
## 返回 0..3；普通装备返回 -1。
static func special_row(location: int) -> int:
	var definition: Dictionary = LOCATION_DEFINITIONS.get(location, {})
	return int(definition.get("special_row", -1))


## 查询旧客户端 `EquipInDlg()` 为该逻辑 Location 指定的面板业务锚点。
## [param location] 荣耀客户端 Location 编号。
## [param fallback] 尚未逆向的扩展位置使用的兼容锚点。
## 返回不包含 ALE 帧 origin 的面板坐标；渲染器应将两者相加得到纹理左上角。
## 设计：锚点属于装备槽语义，不由纹理尺寸或透明边界推算，避免不同车体素材发生漂移。
static func dialog_anchor(location: int, fallback: Vector2i = Vector2i(205, 245)) -> Vector2i:
	return DIALOG_ANCHORS.get(location, fallback)


## 判断给定定义是否允许安装到目标 Location。
## [param definition_id] 装备定义标识。
## [param location] 目标 Location 编号。
## 返回定义映射与目标相符时为 true。
static func accepts(definition_id: String, location: int) -> bool:
	return location_for_definition(definition_id) == location
