class_name VehicleWeapon
extends VehicleEquipment

var base_attack: int
var working_energy_per_shot: float
var attack_range: float
var attack_interval_seconds: float


## 初始化拥有攻击、能耗、射程和冷却行为的战车武器。
## [param definition] 武器配置定义。
## [param state] 存档中的武器实例状态。
func _init(definition: Dictionary = {}, state: Dictionary = {}) -> void:
	super(definition, state)
	base_attack = maxi(0, int(stat("base_attack", 0)))
	working_energy_per_shot = maxf(0.0, float(stat("working_energy_per_shot", 0.0)))
	attack_range = maxf(0.0, float(stat("range", 0.0)))
	attack_interval_seconds = maxf(0.0, float(stat("attack_interval_seconds", 0.0)))
