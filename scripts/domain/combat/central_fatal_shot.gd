class_name CentralFatalShot
extends RefCounted

var controller: PlayerCentralController
var rules: CentralRules
var weapon_instance_id: String
var _contact_claimed := false


## 将开火时的永久芯片状态冻结在这一发弹体上，不随飞行中的升级改变。
## [param source] 开火角色状态。[param configured_rules] 共享只读规则。[param weapon_id] 实际炮实例。
func _init(source: PlayerCentralController, configured_rules: CentralRules, weapon_id: String) -> void:
	controller = PlayerCentralController.restore(source.to_dictionary()).value
	rules = configured_rules
	weapon_instance_id = weapon_id


## 为一发炮弹领取首个有效接触的判定权，穿透后续目标不能再次领取。
## 返回仅第一次调用为真；普通伤害已经击杀首个目标也会用尽判定权。
func claim_contact() -> bool:
	if _contact_claimed: return false
	_contact_claimed = true
	return true
