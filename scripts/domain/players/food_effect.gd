class_name FoodEffect
extends RefCounted

const SKILLS := ["", "energy_cannon", "missile", "rocket_launcher", "driving", "mining",
	"stealth", "radar", "repair", "manufacturing", "refining", "tailoring", "cooking"]
const NAMES := ["", "能量炮经验", "导弹经验", "火箭炮经验", "驾驶经验", "采矿经验", "隐身经验",
	"雷达经验", "维修经验", "制造经验", "提炼经验", "缝纫经验", "烹饪经验", "能量炮攻击", "导弹攻击",
	"火箭炮攻击", "战车生命上限", "战车防御", "人物每秒回血", "战车即时回血"]
var kind: int
var amount: int
var duration: int
var cooldown: int
var expires_at: int
var last_tick: int


## 将目录或可信存档行还原为明确的食品效果对象。
## [param row] 效果类型、数值、持续时间及到期时刻。
func _init(row: Dictionary = {}) -> void:
	kind = int(row.get("kind", 0))
	amount = int(row.get("amount", 0))
	duration = int(row.get("duration", 0))
	cooldown = int(row.get("cooldown", 0))
	expires_at = int(row.get("expires_at", 0))
	last_tick = int(row.get("last_tick", 0))


## 导出存档与网络边界所需的食品效果字段。
## 返回独立纯数据。
func to_dictionary() -> Dictionary:
	return {"kind": kind, "amount": amount, "duration": duration, "cooldown": cooldown,
		"expires_at": expires_at, "last_tick": last_tick}


## 格式化原版食品数值，经验效果使用百分比，其余使用绝对值。
## 返回效果与持续时间、冷却说明。
func description() -> String:
	return "%s +%d%s，%d秒，冷却%d秒" % [NAMES[kind], amount, "%" if kind <= 12 else "", duration, cooldown]
