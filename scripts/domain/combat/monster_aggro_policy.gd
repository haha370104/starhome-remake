class_name MonsterAggroPolicy
extends RefCounted

const UNRESPONSIVE := &"unresponsive"
const RETALIATORY := &"retaliatory"
const AGGRESSIVE := &"aggressive"

var policy_id: StringName


## 初始化怪物索敌策略。
## [param initial_policy_id] unresponsive、retaliatory 或 aggressive。
func _init(initial_policy_id: StringName = UNRESPONSIVE) -> void:
	policy_id = initial_policy_id


## 判断策略标识是否属于支持集合。
## [param candidate] 待校验策略标识。
## 返回支持时为 true。
static func is_supported(candidate: StringName) -> bool:
	return candidate in [UNRESPONSIVE, RETALIATORY, AGGRESSIVE]


## 判断受击后是否会把攻击者设为目标。
## 返回仅反击或主动攻击策略时为 true。
func retaliates_when_hit() -> bool:
	return policy_id in [RETALIATORY, AGGRESSIVE]


## 判断无仇恨时是否会主动搜索附近玩家。
## 返回主动攻击策略时为 true。
func acquires_targets_unprovoked() -> bool:
	return policy_id == AGGRESSIVE
