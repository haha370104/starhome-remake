class_name EnhancementStone
extends GameItem

var family := ""
var effect := ""
var rank := 0


## 从可信物品定义创建可堆叠强化材料，实例不能覆盖效果或等级。
## [param definition] 已校验目录定义。
## [param state] 数量、绑定、锁定与布局等实例事实。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	var rule: Dictionary = definition.get("enhancement", {})
	family = String(rule.get("family", ""))
	effect = String(rule.get("effect", ""))
	rank = int(rule.get("rank", 0))


## 查询下一档合成输出，仅类型和等级决定身份。
## 返回输出定义ID；已达上限时为空。
func next_definition_id() -> String:
	if rank >= (15 if family == "gem" else 6):
		return ""
	return "enhancement:%s:%s:%d" % [family, effect, rank + 1]


## 查询同类型同等级的合成消耗。
## 返回固定宝石二合一，前后缀品质三合一。
func synthesis_count() -> int:
	return 2 if family == "gem" else 3


## 导出材料类型和品质，供客户端以事实展示操作。
## 返回通用物品视图及强化石字段。
func to_view_dictionary() -> Dictionary:
	var view := super()
	view["enhancement_stone"] = {"family": family, "effect": effect, "rank": rank}
	return view
