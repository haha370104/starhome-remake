class_name CombatDefense
extends RefCounted


## 用复刻版统一减伤曲线结算防御，最高减伤75%，正伤害至少造成1点。
## [param damage] 防御前的非负伤害。
## [param defense] 战车或怪物最终防御。
## 返回扣除比例防御后的伤害；零伤害保持零。
static func mitigate(damage: int, defense: int) -> int:
	if damage <= 0:
		return 0
	var protection := maxf(0.0, defense)
	return maxi(1, roundi(damage * (1.0 - minf(0.75, protection / (protection + 200.0)))))
