class_name ConsumableItem
extends GameItem

var energy := 0
var physical := 0
var effects: Array[FoodEffect] = []


## 从权威目录还原可使用物品，不接受客户端提供效果或价格。
## [param definition] 含使用规则的目录定义。
## [param state] 物品实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	var rule: Dictionary = definition.get("use_rule", {})
	energy = int(rule.get("energy", 0))
	physical = int(rule.get("physical", 0))
	for row: Dictionary in rule.get("effects", []):
		effects.append(FoodEffect.new(row))


## 根据实际使用效果生成说明，供背包菜单直接展示原版数值。
## 返回能源、体力、增益时长及冷却的可读说明。
func use_description() -> String:
	var lines := PackedStringArray()
	if energy > 0:
		lines.append("每包恢复战车储备能量 %d" % energy)
		lines.append("自动批量补给，仅使用当前堆叠")
		lines.append("剩余不足一包时消耗一包补满")
	if physical > 0:
		lines.append("恢复体力 %d（上限100）" % physical)
	for effect: FoodEffect in effects:
		lines.append(effect.description())
	return "\n".join(lines)
