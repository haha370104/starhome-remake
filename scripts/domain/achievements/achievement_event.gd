class_name AchievementEvent
extends RefCounted

enum Kind { MONSTER_KILLED, MINERAL_COLLECTED, QUEST_COMPLETED }
const KIND_IDS := ["kill", "mine", "quest"]

var kind: Kind
var target_id: String
var quantity: int
var event_id: String


## 创建由权威结算产生的成就事实，不包含客户端可指定的积分或称号。
## [param event_kind] 击杀、采矿或任务完成。
## [param target] 怪物物种、矿物物品或任务的稳定标识。
## [param amount] 实际结算数量。
## [param identity] 跨重试与重启保持唯一的结算标识。
func _init(event_kind: Kind, target: String, amount: int, identity: String) -> void:
	kind = event_kind
	target_id = target
	quantity = amount
	event_id = identity


## 校验事件的标识、类别和数量边界。
## 返回事件是否可以进入成就聚合。
func is_valid() -> bool:
	return int(kind) >= 0 and int(kind) < KIND_IDS.size() and not target_id.is_empty() \
		and not event_id.is_empty() and quantity > 0 and quantity <= 1000000


## 生成隔离不同事件类别和目标的计数键。
## 返回稳定的领域计数键。
func counter_key() -> String:
	return "%s:%s" % [KIND_IDS[kind], target_id]
