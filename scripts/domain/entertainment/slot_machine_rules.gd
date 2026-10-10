class_name SlotMachineRules
extends RefCounted

const MIN_BET := 1
const MAX_BET := 100
const SYMBOLS := ["彩7", "BAR", "西瓜", "鸭子", "小猪", "奶酪"]
const MACHINES := {
	"slot_left": Vector2(792, 708),
	"slot_middle": Vector2(1056, 708),
	"slot_right": Vector2(1320, 708),
}
const LINES := [
	[0, 1, 2], [3, 4, 5], [6, 7, 8],
	[0, 3, 6], [1, 4, 7], [2, 5, 8],
	[0, 4, 8], [2, 4, 6],
]


## 判断地图是否使用已恢复的荣耀版娱乐大厅及其二层场景。
## [param map_id] 权威地图标识。
## 返回该地图是否有老虎机。
static func supports_map(map_id: String) -> bool:
	return map_id.ends_with("_funroom1") or map_id.ends_with("_2funroom1")


## 根据服务端随机数生成九个独立图案。
## [param random] 服务端拥有的随机数发生器。
## 返回按行排列的图案索引。
static func draw(random: RandomNumberGenerator) -> Array[int]:
	var symbols: Array[int] = []
	for _index in 9:
		symbols.append(random.randi_range(0, SYMBOLS.size() - 1))
	return symbols


## 结算八条横竖斜连线；彩7连线同时计入普通连线与额外彩金。
## [param symbols] 服务端生成的九个图案索引。[param bet] 已验证的下注额。
## 返回中奖连线、彩7连线和最终返奖；不中时返奖为零。
static func settle(symbols: Array[int], bet: int) -> Dictionary:
	var winning_lines: Array[int] = []
	var sevens := 0
	for index in LINES.size():
		var line: Array = LINES[index]
		var symbol: int = symbols[line[0]]
		if symbol == symbols[line[1]] and symbol == symbols[line[2]]:
			winning_lines.append(index)
			if symbol == 0:
				sevens += 1
	var count := winning_lines.size()
	var multiplier := int((count * (count + 1) + sevens * (sevens + 1)) / 2.0)
	return {"winning_lines": winning_lines, "seven_lines": sevens,
		"multiplier": multiplier, "payout": bet * multiplier}
